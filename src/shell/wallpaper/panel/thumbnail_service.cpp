#include "shell/wallpaper/panel/thumbnail_service.h"

#include "core/log.h"
#include "render/core/image_decoder.h"

#include <GLES2/gl2.h>
#include <webp/encode.h>

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <optional>
#include <stb_image_resize2.h>
#include <sys/eventfd.h>
#include <system_error>
#include <unistd.h>
#include <utility>

namespace {

  constexpr Logger kLog("thumb");
  constexpr int kThumbnailTargetPx = 192;
  constexpr float kThumbnailWebPQuality = 82.0f;
  constexpr std::size_t kMinWorkers = 2;
  constexpr std::size_t kMaxWorkers = 4;

  std::vector<std::uint8_t> readFile(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) {
      return {};
    }
    const auto sz = file.tellg();
    if (sz <= 0) {
      return {};
    }
    std::vector<std::uint8_t> data(static_cast<std::size_t>(sz));
    file.seekg(0);
    file.read(reinterpret_cast<char*>(data.data()), sz);
    if (!file) {
      return {};
    }
    return data;
  }

  std::filesystem::path thumbnailCacheDir() {
    if (const char* xdg = std::getenv("XDG_CACHE_HOME"); xdg != nullptr && xdg[0] != '\0') {
      return std::filesystem::path(xdg) / "noctalia" / "thumbnails";
    }
    if (const char* home = std::getenv("HOME"); home != nullptr && home[0] != '\0') {
      return std::filesystem::path(home) / ".cache" / "noctalia" / "thumbnails";
    }
    return std::filesystem::path("/tmp") / "noctalia" / "thumbnails";
  }

  std::uint64_t fnv1a64(std::string_view text) {
    std::uint64_t hash = 14695981039346656037ull;
    for (const unsigned char ch : text) {
      hash ^= static_cast<std::uint64_t>(ch);
      hash *= 1099511628211ull;
    }
    return hash;
  }

  std::string hex64(std::uint64_t value) {
    static constexpr char kDigits[] = "0123456789abcdef";
    std::string out(16, '0');
    for (int i = 15; i >= 0; --i) {
      out[static_cast<std::size_t>(i)] = kDigits[value & 0xF];
      value >>= 4;
    }
    return out;
  }

  std::optional<std::filesystem::path> cachePathForSource(const std::string& sourcePath) {
    namespace fs = std::filesystem;
    std::error_code ec;
    const auto size = fs::file_size(sourcePath, ec);
    if (ec) {
      return std::nullopt;
    }

    const auto mtime = fs::last_write_time(sourcePath, ec);
    if (ec) {
      return std::nullopt;
    }

    const auto ticks = mtime.time_since_epoch().count();
    const std::string key = sourcePath + '\n' + std::to_string(size) + '\n' + std::to_string(ticks) + '\n' +
                            std::to_string(kThumbnailTargetPx) + '\n' + "wallpaper-thumb-v1";
    return thumbnailCacheDir() / (hex64(fnv1a64(key)) + ".webp");
  }

  bool writeFile(const std::filesystem::path& path, const std::uint8_t* data, std::size_t size) {
    std::error_code ec;
    std::filesystem::create_directories(path.parent_path(), ec);
    if (ec) {
      return false;
    }

    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    if (!file) {
      return false;
    }
    file.write(reinterpret_cast<const char*>(data), static_cast<std::streamsize>(size));
    return static_cast<bool>(file);
  }

  std::vector<std::uint8_t> rgbaToRgb(const std::vector<std::uint8_t>& rgba) {
    const std::size_t pixelCount = rgba.size() / 4;
    std::vector<std::uint8_t> rgb(pixelCount * 3);
    for (std::size_t i = 0; i < pixelCount; ++i) {
      rgb[i * 3 + 0] = rgba[i * 4 + 0];
      rgb[i * 3 + 1] = rgba[i * 4 + 1];
      rgb[i * 3 + 2] = rgba[i * 4 + 2];
    }
    return rgb;
  }

  std::vector<std::uint8_t> rgbToRgba(const std::vector<std::uint8_t>& rgb) {
    const std::size_t pixelCount = rgb.size() / 3;
    std::vector<std::uint8_t> rgba(pixelCount * 4);
    for (std::size_t i = 0; i < pixelCount; ++i) {
      rgba[i * 4 + 0] = rgb[i * 3 + 0];
      rgba[i * 4 + 1] = rgb[i * 3 + 1];
      rgba[i * 4 + 2] = rgb[i * 3 + 2];
      rgba[i * 4 + 3] = 255;
    }
    return rgba;
  }

  bool resizeThumbnail(std::vector<std::uint8_t>& pixels, int& width, int& height) {
    const int maxDim = std::max(width, height);
    if (maxDim <= kThumbnailTargetPx || width <= 0 || height <= 0) {
      return true;
    }

    const float scale = static_cast<float>(kThumbnailTargetPx) / static_cast<float>(maxDim);
    const int resizedW = std::max(1, static_cast<int>(std::lround(static_cast<float>(width) * scale)));
    const int resizedH = std::max(1, static_cast<int>(std::lround(static_cast<float>(height) * scale)));

    std::vector<std::uint8_t> out(static_cast<std::size_t>(resizedW) * static_cast<std::size_t>(resizedH) * 3);
    unsigned char* result =
        stbir_resize_uint8_linear(pixels.data(), width, height, 0, out.data(), resizedW, resizedH, 0, STBIR_RGB);
    if (result == nullptr) {
      return false;
    }

    pixels = std::move(out);
    width = resizedW;
    height = resizedH;
    return true;
  }

} // namespace

ThumbnailService::ThumbnailService() {
  m_eventFd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
  if (m_eventFd < 0) {
    kLog.warn("failed to create eventfd; thumbnail service will run synchronously-only");
  }

  const unsigned hc = std::thread::hardware_concurrency();
  const std::size_t suggested = (hc == 0) ? kMinWorkers : std::max<std::size_t>(kMinWorkers, hc / 2);
  const std::size_t n = std::clamp<std::size_t>(suggested, kMinWorkers, kMaxWorkers);
  m_workers.reserve(n);
  for (std::size_t i = 0; i < n; ++i) {
    m_workers.emplace_back([this]() { workerLoop(); });
  }
  kLog.info("spawned {} decode worker(s)", n);
}

ThumbnailService::~ThumbnailService() {
  {
    std::lock_guard<std::mutex> lock(m_queueMutex);
    m_shutdown.store(true);
  }
  m_queueCv.notify_all();
  for (auto& t : m_workers) {
    if (t.joinable()) {
      t.join();
    }
  }

  deleteAllTextures();

  if (m_eventFd >= 0) {
    ::close(m_eventFd);
    m_eventFd = -1;
  }
}

void ThumbnailService::setReadyCallback(ReadyCallback callback) { m_readyCallback = std::move(callback); }

TextureHandle ThumbnailService::request(const std::string& path) {
  auto hit = m_textures.find(path);
  if (hit != m_textures.end()) {
    return hit->second;
  }
  if (m_failedPaths.contains(path)) {
    return {};
  }

  {
    std::lock_guard<std::mutex> lock(m_queueMutex);
    m_canceled.erase(path);
    if (m_inFlight.contains(path)) {
      return {};
    }
    m_inFlight.insert(path);
    m_jobQueue.push_back(path);
  }
  m_queueCv.notify_one();
  return {};
}

void ThumbnailService::release(const std::string& path) {
  auto it = m_textures.find(path);
  if (it != m_textures.end()) {
    if (it->second.id != 0) {
      glDeleteTextures(1, &it->second.id);
    }
    m_textures.erase(it);
  }
  m_failedPaths.erase(path);

  std::lock_guard<std::mutex> lock(m_queueMutex);
  if (m_inFlight.contains(path)) {
    m_canceled.insert(path);
  }
}

void ThumbnailService::releaseAll() {
  deleteAllTextures();
  m_failedPaths.clear();

  std::lock_guard<std::mutex> lock(m_queueMutex);
  m_jobQueue.clear();
  for (const auto& p : m_inFlight) {
    m_canceled.insert(p);
  }
}

void ThumbnailService::uploadPending() {
  std::deque<DecodedJob> jobs;
  {
    std::lock_guard<std::mutex> lock(m_resultMutex);
    jobs = std::move(m_results);
    m_results.clear();
  }
  if (jobs.empty()) {
    return;
  }

  for (auto& job : jobs) {
    bool dropped = false;
    {
      std::lock_guard<std::mutex> lock(m_queueMutex);
      m_inFlight.erase(job.path);
      if (auto c = m_canceled.find(job.path); c != m_canceled.end()) {
        m_canceled.erase(c);
        dropped = true;
      }
    }
    if (dropped) {
      continue;
    }
    if (job.failed || job.rgba.empty() || job.width <= 0 || job.height <= 0) {
      m_failedPaths.insert(job.path);
      continue;
    }

    GLuint tex = 0;
    glGenTextures(1, &tex);
    if (tex == 0) {
      kLog.warn("glGenTextures failed for {}", job.path);
      m_failedPaths.insert(job.path);
      continue;
    }
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, job.width, job.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, job.rgba.data());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    m_textures[job.path] = TextureHandle{.id = tex, .width = job.width, .height = job.height};
  }
}

void ThumbnailService::doAddPollFds(std::vector<pollfd>& fds) {
  if (m_eventFd < 0) {
    return;
  }
  fds.push_back({.fd = m_eventFd, .events = POLLIN, .revents = 0});
}

void ThumbnailService::dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) {
  if (m_eventFd < 0 || startIdx >= fds.size()) {
    return;
  }
  if ((fds[startIdx].revents & POLLIN) == 0) {
    return;
  }

  std::uint64_t ignored = 0;
  while (::read(m_eventFd, &ignored, sizeof(ignored)) > 0) {
  }

  if (m_readyCallback) {
    m_readyCallback();
  }
}

void ThumbnailService::signalMain() {
  if (m_eventFd < 0) {
    return;
  }
  const std::uint64_t one = 1;
  const ssize_t written = ::write(m_eventFd, &one, sizeof(one));
  if (written < 0 && errno != EAGAIN) {
    kLog.warn("failed to signal thumbnail eventfd: errno={}", errno);
  }
}

void ThumbnailService::pushResult(DecodedJob job) {
  {
    std::lock_guard<std::mutex> lock(m_resultMutex);
    m_results.push_back(std::move(job));
  }
  signalMain();
}

void ThumbnailService::deleteAllTextures() {
  for (auto& [path, handle] : m_textures) {
    if (handle.id != 0) {
      glDeleteTextures(1, &handle.id);
    }
  }
  m_textures.clear();
}

void ThumbnailService::workerLoop() {
  while (true) {
    std::string path;
    {
      std::unique_lock<std::mutex> lock(m_queueMutex);
      m_queueCv.wait(lock, [this]() { return m_shutdown.load() || !m_jobQueue.empty(); });
      if (m_shutdown.load()) {
        return;
      }
      path = std::move(m_jobQueue.front());
      m_jobQueue.pop_front();
    }

    DecodedJob result;
    result.path = path;

    if (const auto cachePath = cachePathForSource(path); cachePath.has_value()) {
      auto cachedBytes = readFile(cachePath->string());
      if (!cachedBytes.empty()) {
        if (auto cached = decodeRasterImage(cachedBytes.data(), cachedBytes.size())) {
          result.rgba = std::move(cached->pixels);
          result.width = cached->width;
          result.height = cached->height;
          pushResult(std::move(result));
          continue;
        }

        std::error_code ec;
        std::filesystem::remove(*cachePath, ec);
      }
    }

    auto bytes = readFile(path);
    if (bytes.empty()) {
      result.failed = true;
      pushResult(std::move(result));
      continue;
    }

    auto decoded = decodeRasterImage(bytes.data(), bytes.size());
    if (!decoded) {
      result.failed = true;
      pushResult(std::move(result));
      continue;
    }

    int w = decoded->width;
    int h = decoded->height;
    auto pixels = rgbaToRgb(decoded->pixels);

    if (!resizeThumbnail(pixels, w, h)) {
      result.failed = true;
      pushResult(std::move(result));
      continue;
    }

    if (const auto cachePath = cachePathForSource(path); cachePath.has_value()) {
      std::uint8_t* encoded = nullptr;
      const std::size_t encodedSize = WebPEncodeRGB(pixels.data(), w, h, w * 3, kThumbnailWebPQuality, &encoded);
      if (encoded != nullptr && encodedSize > 0) {
        (void)writeFile(*cachePath, encoded, encodedSize);
        WebPFree(encoded);
      }
    }

    result.rgba = rgbToRgba(pixels);
    result.width = w;
    result.height = h;
    pushResult(std::move(result));
  }
}
