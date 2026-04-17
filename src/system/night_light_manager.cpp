#include "system/night_light_manager.h"

#include "core/log.h"
#include "core/process.h"
#include "ipc/ipc_service.h"

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <ctime>
#include <format>
#include <string>
#include <sys/wait.h>
#include <vector>

namespace {

  constexpr Logger kLog("nightlight");

  // Parses a validated "HH:MM" string (already checked by normalizedClock) into minutes since midnight.
  int timeToMinutes(std::string_view hhmm) {
    return (hhmm[0] - '0') * 600 + (hhmm[1] - '0') * 60 + (hhmm[3] - '0') * 10 + (hhmm[4] - '0');
  }

} // namespace

NightLightManager::~NightLightManager() { stopProcess(); }

void NightLightManager::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void NightLightManager::reload(const NightLightConfig& config) {
  m_config = config;
  m_enabledOverride.reset();
  m_forceOverride.reset();
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

bool NightLightManager::isManualMode() const {
  return !effectiveForce() && normalizedClock(m_config.startTime).has_value() &&
         normalizedClock(m_config.stopTime).has_value();
}

bool NightLightManager::isManualNightPhase() const {
  const auto now = std::chrono::system_clock::now();
  const std::time_t t = std::chrono::system_clock::to_time_t(now);
  std::tm local{};
  ::localtime_r(&t, &local);
  const int nowMin = local.tm_hour * 60 + local.tm_min;

  const int sunsetMin = timeToMinutes(m_config.startTime); // night start
  const int sunriseMin = timeToMinutes(m_config.stopTime); // day start

  if (sunsetMin < sunriseMin) {
    // Inverted schedule (e.g. 03:00–07:00): night is the window [sunset, sunrise)
    return nowMin >= sunsetMin && nowMin < sunriseMin;
  }
  // Normal schedule (e.g. 20:00–06:00): night wraps midnight
  return nowMin >= sunsetMin || nowMin < sunriseMin;
}

std::chrono::milliseconds NightLightManager::msUntilNextManualBoundary() const {
  const auto now = std::chrono::system_clock::now();
  const std::time_t t = std::chrono::system_clock::to_time_t(now);
  std::tm local{};
  ::localtime_r(&t, &local);
  const int nowMin = local.tm_hour * 60 + local.tm_min;
  const int nowSec = local.tm_sec;

  const int sunsetMin = timeToMinutes(m_config.startTime);
  const int sunriseMin = timeToMinutes(m_config.stopTime);
  const int targetMin = isManualNightPhase() ? sunriseMin : sunsetMin;

  int diffMin = targetMin - nowMin;
  if (diffMin <= 0) {
    diffMin += 1440; // wrap to next day
  }

  // Subtract elapsed seconds of the current minute so the timer fires at the exact boundary minute.
  const auto ms = std::chrono::milliseconds(diffMin * 60 * 1000 - nowSec * 1000);
  return std::max(ms, std::chrono::milliseconds(1000));
}

void NightLightManager::scheduleManualTimer() {
  const auto delay = msUntilNextManualBoundary();
  kLog.debug("nightlight manual schedule: next phase boundary in {}s", delay.count() / 1000);
  m_scheduleTimer.start(delay, [this]() {
    kLog.info("nightlight manual schedule: phase boundary reached, re-applying");
    apply();
  });
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
  // In manual mode the timer drives phase transitions; keep it running whenever enabled.
  if (effectiveEnabled() && isManualMode()) {
    scheduleManualTimer();
  } else {
    m_scheduleTimer.stop();
  }

  if (!effectiveEnabled()) {
    stopProcess();
    m_lastArgs.clear();
    if (m_changeCallback) {
      m_changeCallback();
    }
    return;
  }

  const auto args = buildCommandArgs();
  if (!args.has_value()) {
    stopProcess();
    m_lastArgs.clear();
    if (m_changeCallback) {
      m_changeCallback();
    }
    return;
  }

  if (hasRunningProcess() && *args == m_lastArgs) {
    return;
  }

  stopProcess();
  startProcess(*args);
  if (m_changeCallback) {
    m_changeCallback();
  }
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
      // Manual mode: the shell evaluates the phase itself to avoid wlsunset's assumption
      // that sunset < sunrise (which breaks schedules that cross midnight).
      if (!isManualNightPhase()) {
        return std::nullopt; // Day phase — don't run wlsunset.
      }
      // Night phase: run wlsunset in permanent force mode.
      args.push_back("-s");
      args.push_back("00:00");
      args.push_back("-S");
      args.push_back("23:59");
      args.push_back("-d");
      args.push_back("1");
    } else {
      if (hasStart && !start.has_value()) {
        kLog.warn("nightlight invalid start_time '{}'; expected zero-padded HH:MM (e.g. 20:30)", m_config.startTime);
      }
      if (hasStop && !stop.has_value()) {
        kLog.warn("nightlight invalid stop_time '{}'; expected zero-padded HH:MM (e.g. 06:30)", m_config.stopTime);
      }

      std::optional<double> latitude;
      std::optional<double> longitude;
      if (m_config.latitude.has_value() && m_config.longitude.has_value()) {
        latitude = m_config.latitude;
        longitude = m_config.longitude;
      } else if (m_config.latitude.has_value() || m_config.longitude.has_value()) {
        kLog.warn("nightlight needs both latitude and longitude when overriding location mode");
        return std::nullopt;
      } else if (m_config.useWeatherLocation && m_weatherLatitude.has_value() && m_weatherLongitude.has_value()) {
        latitude = m_weatherLatitude;
        longitude = m_weatherLongitude;
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

  process::terminateTracked(static_cast<int>(m_pid));
  m_pid = -1;
}

void NightLightManager::registerIpc(IpcService& ipc) {
  ipc.registerHandler(
      "enable-nightlight",
      [this](const std::string&) -> std::string {
        setEnabled(true);
        return "ok\n";
      },
      "enable-nightlight", "Enable night light schedule");

  ipc.registerHandler(
      "disable-nightlight",
      [this](const std::string&) -> std::string {
        setEnabled(false);
        return "ok\n";
      },
      "disable-nightlight", "Disable night light schedule");

  ipc.registerHandler(
      "toggle-nightlight",
      [this](const std::string&) -> std::string {
        toggleEnabled();
        return "ok\n";
      },
      "toggle-nightlight", "Toggle night light schedule");

  ipc.registerHandler(
      "toggle-force-nightlight",
      [this](const std::string&) -> std::string {
        toggleForceEnabled();
        return "ok\n";
      },
      "toggle-force-nightlight", "Toggle forced night light mode");
}
