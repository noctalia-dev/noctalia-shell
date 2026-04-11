#pragma once

#include "config/config_service.h"

#include <optional>
#include <string>
#include <string_view>
#include <vector>

class NightLightManager {
public:
  NightLightManager() = default;
  ~NightLightManager();

  void reload(const NightLightConfig& config);
  void setWeatherCoordinates(std::optional<double> latitude, std::optional<double> longitude);
  void setEnabled(bool enabled);
  void toggleEnabled();
  void setForceEnabled(bool enabled);
  void toggleForceEnabled();
  void clearForceOverride();

  [[nodiscard]] bool enabled() const;
  [[nodiscard]] bool forceEnabled() const;
  [[nodiscard]] bool active();

private:
  [[nodiscard]] bool effectiveConfiguredEnabled() const;
  [[nodiscard]] bool effectiveEnabled() const;
  [[nodiscard]] bool effectiveForce() const;
  [[nodiscard]] bool hasRunningProcess();
  [[nodiscard]] std::optional<std::string> normalizedClock(std::string_view value) const;
  [[nodiscard]] std::optional<std::vector<std::string>> buildCommandArgs() const;
  void apply();
  void startProcess(const std::vector<std::string>& args);
  void stopProcess();

  NightLightConfig m_config;
  std::optional<bool> m_enabledOverride;
  std::optional<bool> m_forceOverride;
  std::optional<double> m_weatherLatitude;
  std::optional<double> m_weatherLongitude;
  std::vector<std::string> m_lastArgs;
  int m_pid = -1;
};
