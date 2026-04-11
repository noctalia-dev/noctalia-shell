#include "shell/wallpaper/panel/thumbnail_service.h"

#include "core/log.h"
#include "render/core/image_decoder.h"

#include <GLES2/gl2.h>

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <sys/eventfd.h>
#include <unistd.h>
#include <utility>

namespace {

constexpr Logger kLog("thumb");
constexpr int kThumbnailTargetPx = 192;
constexpr std::size_t kMaxWorkers = 8;

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

void halveRgba(std::vector<std::uint8_t>& pixels, int& width, int& height) {
  const int newW = width / 2;
  const int newH = height / 2;
  if (newW <= 0 || newH <= 0) {
    return;
  }

  std::vector<std::uint8_t> out(static_cast<std::size_t>(newW * newH * 4));
  const int srcRow = width * 4;
  for (int y = 0; y < newH; ++y) {
    for (int x = 0; x < newW; ++x) {
      const int sx = x * 2;
      const int sy = y * 2;
      const int p0 = sy * srcRow + sx * 4;
      const int p1 = p0 + 4;
      const int p2 = p0 + srcRow;
      const int p3 = p2 + 4;
      const int dst = (y * newW + x) * 4;
      for (int c = 0; c < 4; ++c) {
        const int sum = static_cast<int>(pixels[p0 + c]) + pixels[p1 + c] + pixels[p2 + c] + pixels[p3 + c];
        out[dst + c] = static_cast<std::uint8_t>(sum / 4);
      }
    }
  }
  pixels = std::move(out);
  width = newW;
  height = newH;
}

} // namespace

ThumbnailService::ThumbnailService() {
  m_eventFd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
  if (m_eventFd < 0) {
    kLog.warn("failed to create eventfd; thumbnail service will run synchronously-only");
  }

  const unsigned hc = std::thread::hardware_concurrency();
  const std::size_t n = std::clamp<std::size_t>(hc == 0 ? 2 : hc / 2, 2, kMaxWorkers);
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
  (void)::write(m_eventFd, &one, sizeof(one));
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
    auto& pixels = decoded->pixels;

    while (std::max(w, h) > kThumbnailTargetPx * 2 && w >= 2 && h >= 2) {
      halveRgba(pixels, w, h);
    }

    result.rgba = std::move(pixels);
    result.width = w;
    result.height = h;
    pushResult(std::move(result));
  }
}
