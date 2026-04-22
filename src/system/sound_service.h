#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string_view>

enum class SoundId : std::size_t {
  NotificationGeneric = 0,
  VolumeChange = 1,
  AlarmBeep = 2,
  Count,
};

class SoundService {
public:
  SoundService();

  void play(SoundId soundId, std::string_view overridePath = {}, float volume = 1.0f) const;

private:
  enum class Backend : std::uint8_t {
    PwPlay,
    Paplay,
    Aplay,
  };

  [[nodiscard]] static std::array<std::filesystem::path, static_cast<std::size_t>(SoundId::Count)> buildSoundTable();
  [[nodiscard]] static std::optional<Backend> detectBackend();
  [[nodiscard]] static std::string_view backendName(Backend backend);

  [[nodiscard]] std::filesystem::path resolvePath(SoundId soundId, std::string_view overridePath) const;
  void playWithBackend(Backend backend, const std::filesystem::path& filePath, float volume) const;

  std::array<std::filesystem::path, static_cast<std::size_t>(SoundId::Count)> m_soundFiles;
  std::optional<Backend> m_backend;
};
