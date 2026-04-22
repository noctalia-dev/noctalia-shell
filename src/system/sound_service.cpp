#include "system/sound_service.h"

#include "core/log.h"
#include "core/process.h"
#include "core/resource_paths.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <format>
#include <string>
#include <vector>

namespace {

  constexpr Logger kLog("sound");
  constexpr float kMaxSoundPlaybackVolume = 3.0f;

  std::filesystem::path expandUserPath(std::string_view rawPath) {
    if (rawPath.empty()) {
      return {};
    }

    if (rawPath[0] != '~') {
      return std::filesystem::path(std::string(rawPath));
    }

    const char* home = std::getenv("HOME");
    if (home == nullptr || home[0] == '\0') {
      return std::filesystem::path(std::string(rawPath));
    }

    if (rawPath.size() == 1) {
      return std::filesystem::path(home);
    }
    if (rawPath[1] == '/') {
      return std::filesystem::path(home) / std::string(rawPath.substr(2));
    }

    // "~user" expansion is intentionally not supported.
    return std::filesystem::path(std::string(rawPath));
  }

} // namespace

SoundService::SoundService() : m_soundFiles(buildSoundTable()), m_backend(detectBackend()) {
  if (m_backend.has_value()) {
    kLog.info("sound service active via {}", backendName(*m_backend));
  } else {
    kLog.warn("sound service disabled: no supported playback backend found (pw-play/paplay/aplay)");
  }
}

void SoundService::play(SoundId soundId, std::string_view overridePath, float volume) const {
  if (!m_backend.has_value()) {
    return;
  }

  const std::filesystem::path filePath = resolvePath(soundId, overridePath);
  if (filePath.empty() || !std::filesystem::exists(filePath)) {
    kLog.warn("sound file not found: {}", filePath.string());
    return;
  }

  playWithBackend(*m_backend, filePath, std::clamp(volume, 0.0f, kMaxSoundPlaybackVolume));
}

std::array<std::filesystem::path, static_cast<std::size_t>(SoundId::Count)> SoundService::buildSoundTable() {
  return {
      paths::assetPath("sounds/notification-generic.wav"),
      paths::assetPath("sounds/volume-change.wav"),
      paths::assetPath("sounds/alarm-beep.wav"),
  };
}

std::optional<SoundService::Backend> SoundService::detectBackend() {
  if (process::commandExists("pw-play")) {
    return Backend::PwPlay;
  }
  if (process::commandExists("paplay")) {
    return Backend::Paplay;
  }
  if (process::commandExists("aplay")) {
    return Backend::Aplay;
  }
  return std::nullopt;
}

std::string_view SoundService::backendName(Backend backend) {
  switch (backend) {
  case Backend::PwPlay:
    return "pw-play";
  case Backend::Paplay:
    return "paplay";
  case Backend::Aplay:
    return "aplay";
  }
  return "unknown";
}

std::filesystem::path SoundService::resolvePath(SoundId soundId, std::string_view overridePath) const {
  if (!overridePath.empty()) {
    std::filesystem::path customPath = expandUserPath(overridePath);
    if (customPath.is_relative()) {
      const std::filesystem::path bundledPath = paths::assetsRoot() / customPath;
      if (std::filesystem::exists(bundledPath)) {
        return bundledPath;
      }
    }
    return customPath;
  }

  const std::size_t index = static_cast<std::size_t>(soundId);
  if (index >= m_soundFiles.size()) {
    return {};
  }
  return m_soundFiles[index];
}

void SoundService::playWithBackend(Backend backend, const std::filesystem::path& filePath, float volume) const {
  const std::string path = filePath.string();
  bool launched = false;
  switch (backend) {
  case Backend::PwPlay:
    launched = process::runAsync(
        std::vector<std::string>{"pw-play", "--volume", std::format("{:.3f}", static_cast<double>(volume)), path});
    break;
  case Backend::Paplay:
    launched = process::runAsync(std::vector<std::string>{
        "paplay",
        "--volume",
        std::to_string(static_cast<int>(std::lround(std::clamp(volume, 0.0f, kMaxSoundPlaybackVolume) * 65536.0f))),
        path,
    });
    break;
  case Backend::Aplay:
    launched = process::runAsync(std::vector<std::string>{"aplay", "-q", path});
    break;
  }
  if (!launched) {
    kLog.warn("failed to play sound via {}", backendName(backend));
  }
}
