#pragma once

#include "config/config_service.h"
#include "core/timer_manager.h"

#include <chrono>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <sys/types.h>
#include <vector>

class IpcService;

class NightLightManager {
public:
  using ChangeCallback = std::function<void()>;

  NightLightManager() = default;
  ~NightLightManager();

  void reload(const NightLightConfig& config);
  void setWeatherCoordinates(std::optional<double> latitude, std::optional<double> longitude);
  void setEnabled(bool enabled);
  void toggleEnabled();
  void setForceEnabled(bool enabled);
  void toggleForceEnabled();
  void clearForceOverride();
  void setChangeCallback(ChangeCallback callback);

  [[nodiscard]] bool enabled() const;
  [[nodiscard]] bool forceEnabled() const;
  [[nodiscard]] bool active();

  void registerIpc(IpcService& ipc);

private:
  [[nodiscard]] bool effectiveConfiguredEnabled() const;
  [[nodiscard]] bool effectiveEnabled() const;
  [[nodiscard]] bool effectiveForce() const;
  [[nodiscard]] bool isManualMode() const;
  [[nodiscard]] bool isManualNightPhase() const;
  [[nodiscard]] std::chrono::milliseconds msUntilNextManualBoundary() const;
  [[nodiscard]] bool hasRunningProcess();
  [[nodiscard]] std::optional<std::string> normalizedClock(std::string_view value) const;
  [[nodiscard]] std::optional<std::vector<std::string>> buildCommandArgs() const;
  void scheduleManualTimer();
  void apply();
  void startProcess(const std::vector<std::string>& args);
  void stopAllWlsunsetInstances();
  void stopProcess();

  ChangeCallback m_changeCallback;
  NightLightConfig m_config;
  std::optional<bool> m_enabledOverride;
  std::optional<bool> m_forceOverride;
  std::optional<double> m_weatherLatitude;
  std::optional<double> m_weatherLongitude;
  std::vector<std::string> m_lastArgs;
  Timer m_scheduleTimer;
  pid_t m_pid = -1;
};
