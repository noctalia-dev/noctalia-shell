#include "system/night_light_manager.h"

#include "core/log.h"
#include "core/process.h"

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <csignal>
#include <format>
#include <string>
#include <sys/wait.h>
#include <thread>
#include <vector>

namespace {

  constexpr Logger kLog("nightlight");

} // namespace

NightLightManager::~NightLightManager() { stopProcess(); }

void NightLightManager::reload(const NightLightConfig& config) {
  m_config = config;
  apply();
}

void NightLightManager::setEnabled(bool enabled) {
  m_enabledOverride = enabled;
  apply();
}

void NightLightManager::toggleEnabled() { setEnabled(!enabled()); }

void NightLightManager::setWeatherCoordinates(std::optional<double> latitude, std::optional<double> longitude) {
  if (latitude.has_value() && !std::isfinite(*latitude)) {
    latitude.reset();
  }
  if (longitude.has_value() && !std::isfinite(*longitude)) {
    longitude.reset();
  }
  if (m_weatherLatitude == latitude && m_weatherLongitude == longitude) {
    return;
  }
  m_weatherLatitude = latitude;
  m_weatherLongitude = longitude;
  apply();
}

void NightLightManager::setForceEnabled(bool enabled) {
  m_forceOverride = enabled;
  apply();
}

void NightLightManager::toggleForceEnabled() { setForceEnabled(!forceEnabled()); }

void NightLightManager::clearForceOverride() {
  m_forceOverride.reset();
  apply();
}

bool NightLightManager::enabled() const { return effectiveConfiguredEnabled(); }

bool NightLightManager::forceEnabled() const { return effectiveForce(); }

bool NightLightManager::active() { return hasRunningProcess(); }

bool NightLightManager::effectiveConfiguredEnabled() const {
  if (m_enabledOverride.has_value()) {
    return *m_enabledOverride;
  }
  return m_config.enabled;
}

bool NightLightManager::effectiveEnabled() const {
  return effectiveConfiguredEnabled() || m_forceOverride.value_or(false);
}

bool NightLightManager::effectiveForce() const {
  if (m_forceOverride.has_value()) {
    return *m_forceOverride;
  }
  return m_config.force;
}

bool NightLightManager::hasRunningProcess() {
  if (m_pid <= 0) {
    return false;
  }

  int status = 0;
  const pid_t result = ::waitpid(static_cast<pid_t>(m_pid), &status, WNOHANG);
  if (result == 0) {
    return true;
  }
  if (result == static_cast<pid_t>(m_pid)) {
    m_pid = -1;
    return false;
  }
  if (result < 0 && (errno == ECHILD || errno == ESRCH)) {
    m_pid = -1;
    return false;
  }

  return true;
}

std::optional<std::string> NightLightManager::normalizedClock(std::string_view value) const {
  if (value.size() != 5 || value[2] != ':') {
    return std::nullopt;
  }
  if (!std::isdigit(static_cast<unsigned char>(value[0])) || !std::isdigit(static_cast<unsigned char>(value[1])) ||
      !std::isdigit(static_cast<unsigned char>(value[3])) || !std::isdigit(static_cast<unsigned char>(value[4]))) {
    return std::nullopt;
  }

  const int hour = (value[0] - '0') * 10 + (value[1] - '0');
  const int minute = (value[3] - '0') * 10 + (value[4] - '0');
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return std::nullopt;
  }
  return std::string(value);
}

void NightLightManager::apply() {
  if (!effectiveEnabled()) {
    stopProcess();
    m_lastArgs.clear();
    return;
  }

  const auto args = buildCommandArgs();
  if (!args.has_value()) {
    stopProcess();
    m_lastArgs.clear();
    return;
  }

  if (hasRunningProcess() && *args == m_lastArgs) {
    return;
  }

  stopProcess();
  startProcess(*args);
}

std::optional<std::vector<std::string>> NightLightManager::buildCommandArgs() const {
  constexpr const char* kExecutable = "wlsunset";
  if (!process::commandExists(kExecutable)) {
    kLog.warn("nightlight executable not found: {}", kExecutable);
    return std::nullopt;
  }

  const int dayTemp = std::clamp(m_config.dayTemperature, 1000, 10000);
  const int nightTemp = std::clamp(m_config.nightTemperature, 1000, 10000);

  if (dayTemp <= nightTemp) {
    kLog.warn("nightlight invalid temperatures: day={}K must be > night={}K", dayTemp, nightTemp);
    return std::nullopt;
  }

  std::vector<std::string> args;
  args.emplace_back(kExecutable);
  // wlsunset: -t = low/night temperature, -T = high/day temperature
  args.push_back("-t");
  args.push_back(std::to_string(nightTemp));
  args.push_back("-T");
  args.push_back(std::to_string(dayTemp));

  if (effectiveForce()) {
    // Force night mode while still keeping valid day/night temp ordering.
    args.push_back("-s"); // sunset
    args.push_back("00:00");
    args.push_back("-S"); // sunrise
    args.push_back("23:59");
    args.push_back("-d");
    args.push_back("1");
  } else {
    const auto start = normalizedClock(m_config.startTime);
    const auto stop = normalizedClock(m_config.stopTime);
    const bool hasStart = !m_config.startTime.empty();
    const bool hasStop = !m_config.stopTime.empty();
    if (start.has_value() && stop.has_value()) {
      // start_time = night start (sunset), stop_time = day start (sunrise)
      args.push_back("-s");
      args.push_back(*start);
      args.push_back("-S");
      args.push_back(*stop);
    } else {
      if ((hasStart && !start.has_value()) || (hasStop && !stop.has_value())) {
        kLog.warn("nightlight invalid start/stop time format; expected HH:MM");
      }

      std::optional<double> latitude;
      std::optional<double> longitude;
      if (m_config.latitude.has_value() && m_config.longitude.has_value()) {
        latitude = m_config.latitude;
        longitude = m_config.longitude;
      } else if (m_config.latitude.has_value() || m_config.longitude.has_value()) {
        kLog.warn("nightlight needs both latitude and longitude when overriding location mode");
        return std::nullopt;
      } else if (m_weatherLatitude.has_value() && m_weatherLongitude.has_value()) {
        latitude = m_weatherLatitude;
        longitude = m_weatherLongitude;
        if (!m_config.autoDetect) {
          kLog.debug("nightlight using weather coordinates as fallback (auto_detect=false)");
        }
      }

      if (!latitude.has_value() || !longitude.has_value()) {
        kLog.warn("nightlight has no schedule: set start_time/stop_time or latitude/longitude, or enable weather");
        return std::nullopt;
      }

      args.push_back("-l");
      args.push_back(std::format("{:.6f}", *latitude));
      args.push_back("-L");
      args.push_back(std::format("{:.6f}", *longitude));
    }
  }

  return args;
}

void NightLightManager::startProcess(const std::vector<std::string>& args) {
  const int dayTemp = std::clamp(m_config.dayTemperature, 1000, 10000);
  const int nightTemp = std::clamp(m_config.nightTemperature, 1000, 10000);
  const auto pid = process::launchDetachedTracked(args);
  if (!pid.has_value()) {
    kLog.warn("failed to start nightlight process");
    return;
  }

  m_pid = *pid;
  m_lastArgs = args;
  kLog.info("nightlight started pid={} force={} day={}K night={}K", m_pid, effectiveForce(), dayTemp, nightTemp);
}

void NightLightManager::stopProcess() {
  if (!hasRunningProcess()) {
    return;
  }

  const pid_t pid = static_cast<pid_t>(m_pid);
  ::kill(pid, SIGTERM);

  constexpr int kAttempts = 20;
  for (int i = 0; i < kAttempts; ++i) {
    int status = 0;
    const pid_t result = ::waitpid(pid, &status, WNOHANG);
    if (result == pid) {
      m_pid = -1;
      return;
    }
    if (result < 0 && (errno == ECHILD || errno == ESRCH)) {
      m_pid = -1;
      return;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(25));
  }

  ::kill(pid, SIGKILL);
  int status = 0;
  (void)::waitpid(pid, &status, 0);
  m_pid = -1;
}
