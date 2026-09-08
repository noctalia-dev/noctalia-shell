#include "shell/wallpaper/visualizer_service.h"

#include "config/config_service.h"
#include "core/log.h"
#include "dbus/mpris/mpris_service.h"
#include "render/visualizer/projectm_renderer.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <random>
#include <string_view>
#include <system_error>

namespace {

  constexpr Logger kLog{"visualizer-service"};

  // Minimum gap between automatic preset advances. Prevents MPRIS metadata
  // refreshes (which fire during track-start) from thrashing libprojectM's
  // cross-fade pipeline.
  constexpr std::chrono::seconds kMinAdvanceGap{4};

  bool hasPresetExtension(const std::filesystem::path& path) {
    auto ext = path.extension().string();
    std::ranges::transform(ext, ext.begin(), [](unsigned char c) { return std::tolower(c); });
    return ext == ".milk" || ext == ".prjm";
  }

  std::string xdgDataHomePresetsDir() {
    if (const char* env = std::getenv("XDG_DATA_HOME"); env != nullptr && env[0] != '\0') {
      return std::string{env} + "/waylivepaper/presets";
    }
    if (const char* home = std::getenv("HOME"); home != nullptr && home[0] != '\0') {
      return std::string{home} + "/.local/share/waylivepaper/presets";
    }
    return {};
  }

} // namespace

VisualizerService::VisualizerService() = default;
VisualizerService::~VisualizerService() { shutdown(); }

void VisualizerService::initialize(ProjectMRenderer* renderer, ConfigService* config, MprisService* mpris) {
  m_renderer = renderer;
  m_config = config;
  m_mpris = mpris;
  onConfigChanged();
}

void VisualizerService::shutdown() {
  cancelRotation();
  m_renderer = nullptr;
  m_config = nullptr;
  m_mpris = nullptr;
  m_presets.clear();
  m_currentPreset.clear();
  m_lastScannedDir.clear();
  m_lastSeenTrackId.clear();
  m_seenFirstTrack = false;
  m_sessionLocked = false;
}

bool VisualizerService::enabled() const noexcept {
  return m_config != nullptr && m_config->config().wallpaper.livePaper.enabled;
}

void VisualizerService::onConfigChanged() {
  if (m_config == nullptr || m_renderer == nullptr) {
    return;
  }
  applyConfigToRenderer();

  if (!enabled()) {
    cancelRotation();
    return;
  }
  // Rescan if the resolved presets directory has changed (or this is the first
  // call). Scanning is the slow path so we avoid doing it every time another
  // unrelated TOML field flips.
  const std::string dir = resolvePresetsDir();
  if (dir != m_lastScannedDir) {
    rescanPresets();
  }
  if (m_currentPreset.empty() && !m_presets.empty()) {
    advancePreset();
  }
  scheduleRotation();
}

void VisualizerService::applyConfigToRenderer() {
  if (m_renderer == nullptr || m_config == nullptr) {
    return;
  }
  const auto& lp = m_config->config().wallpaper.livePaper;
  // Working framebuffer size first: resize() recreates the FBO/texture and is
  // a no-op when the size is unchanged, so it costs nothing on the common
  // reload where only an unrelated field flipped. Mesh/fps are re-applied
  // afterwards because resize() also resizes libprojectM's internal mesh.
  m_renderer->resize(static_cast<std::uint32_t>(lp.renderWidth), static_cast<std::uint32_t>(lp.renderHeight));
  m_renderer->setMeshSize(lp.meshW, lp.meshH);
  m_renderer->setFps(lp.fps);
  m_renderer->setTextureSearchPaths(resolveTextureSearchPaths());
}

std::vector<std::string> VisualizerService::resolveTextureSearchPaths() const {
  const std::string dir = resolvePresetsDir();
  if (dir.empty()) {
    return {};
  }
  std::vector<std::string> paths;
  // Conventional layout: textures/ is a sibling of presets/ under the same
  // parent (e.g. ~/.local/share/waylivepaper/textures).
  const std::filesystem::path presetsPath{dir};
  const auto texturesPath = presetsPath.parent_path() / "textures";
  std::error_code ec;
  if (std::filesystem::is_directory(texturesPath, ec)) {
    paths.push_back(texturesPath.string());
  }
  if (std::filesystem::is_directory(presetsPath, ec)) {
    paths.push_back(dir);
  }
  return paths;
}

void VisualizerService::onMprisChanged() {
  if (!enabled() || m_mpris == nullptr) {
    return;
  }
  auto active = m_mpris->activePlayer();
  if (!active.has_value()) {
    return;
  }
  if (active->trackId == m_lastSeenTrackId) {
    return; // metadata refresh, not an actual new track
  }
  m_lastSeenTrackId = active->trackId;
  if (!m_seenFirstTrack) {
    m_seenFirstTrack = true;
    return;
  }
  advancePreset();
}

void VisualizerService::setSessionLocked(bool locked) {
  if (m_sessionLocked == locked) {
    return;
  }
  m_sessionLocked = locked;
  // While locked we pin the running preset (see header). Cancel any scheduled
  // rotation; when the session is unlocked, scheduleRotation() reinstates the
  // timer if interval_seconds > 0.
  if (m_sessionLocked) {
    cancelRotation();
  } else {
    scheduleRotation();
  }
}

void VisualizerService::advancePreset() {
  if (m_renderer == nullptr || m_presets.empty()) {
    return;
  }
  if (m_sessionLocked) {
    return;
  }
  const auto now = std::chrono::steady_clock::now();
  if (m_lastAdvanceAt.time_since_epoch().count() != 0 && (now - m_lastAdvanceAt) < kMinAdvanceGap) {
    return;
  }
  m_lastAdvanceAt = now;
  std::string next = pickRandomPreset();
  if (next.empty() || next == m_currentPreset) {
    // Try once more for variety when the random pick repeats; if the list has
    // a single entry we just stay on it.
    next = pickRandomPreset();
  }
  if (next.empty()) {
    return;
  }
  m_currentPreset = std::move(next);
  kLog.debug("loading preset: {}", m_currentPreset);
  m_renderer->loadPreset(m_currentPreset);
}

void VisualizerService::setEnabled(bool enabledValue) {
  if (m_config == nullptr) {
    return;
  }
  if (m_config->config().wallpaper.livePaper.enabled == enabledValue) {
    return;
  }
  // ConfigService owns the on-disk source of truth; mutate via its generic
  // override layer so the change persists across restarts. ConfigService
  // re-parses + re-emits change callbacks, which calls back into our
  // onConfigChanged() to start/stop rotation.
  m_config->setOverride({"wallpaper", "live_paper", "enabled"}, ConfigOverrideValue{enabledValue});
}

void VisualizerService::toggleEnabled() { setEnabled(!enabled()); }

void VisualizerService::rescanPresets() {
  m_presets.clear();
  const std::string dir = resolvePresetsDir();
  m_lastScannedDir = dir;
  if (dir.empty()) {
    kLog.warn("no presets directory configured");
    return;
  }
  std::error_code ec;
  std::filesystem::path root{dir};
  if (!std::filesystem::is_directory(root, ec)) {
    kLog.warn("presets directory {} is not a directory ({})", dir, ec.message());
    return;
  }
  // Do NOT follow symlinks: presets_dir is user-controlled (via TOML or
  // XDG_DATA_HOME), and a self-referencing symlink would either loop forever
  // here or silently duplicate presets in the rotation. We still skip files
  // that aren't readable rather than aborting the whole scan.
  for (auto it = std::filesystem::recursive_directory_iterator(
           root, std::filesystem::directory_options::skip_permission_denied, ec
       );
       it != std::filesystem::recursive_directory_iterator(); it.increment(ec)) {
    if (ec) {
      kLog.warn("recursive scan error at {}: {}", it->path().string(), ec.message());
      continue;
    }
    if (!std::filesystem::is_regular_file(it->symlink_status(ec)) || ec) {
      continue;
    }
    if (hasPresetExtension(it->path())) {
      m_presets.push_back(it->path().string());
    }
  }
  kLog.info("scanned {} presets under {}", m_presets.size(), dir);
}

void VisualizerService::scheduleRotation() {
  cancelRotation();
  if (m_config == nullptr || !enabled()) {
    return;
  }
  const int interval = m_config->config().wallpaper.livePaper.intervalSeconds;
  if (interval <= 0) {
    return;
  }
  m_rotationTimer.startRepeating(std::chrono::seconds(interval), [this]() { advancePreset(); });
}

void VisualizerService::cancelRotation() { m_rotationTimer.stop(); }

std::string VisualizerService::pickRandomPreset() {
  if (m_presets.empty()) {
    return {};
  }
  static thread_local std::mt19937 rng{std::random_device{}()};
  std::uniform_int_distribution<std::size_t> dist(0, m_presets.size() - 1);
  return m_presets[dist(rng)];
}

std::string VisualizerService::resolvePresetsDir() const {
  if (m_config == nullptr) {
    return {};
  }
  const auto& lp = m_config->config().wallpaper.livePaper;
  if (!lp.presetsDir.empty()) {
    return lp.presetsDir;
  }
  return xdgDataHomePresetsDir();
}
