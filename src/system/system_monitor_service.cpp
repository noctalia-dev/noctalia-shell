#include "system/system_monitor_service.h"

#include "core/log.h"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

std::optional<std::string> readSmallTextFile(const std::filesystem::path& path) {
  std::ifstream file{path};
  if (!file.is_open()) {
    return std::nullopt;
  }

  std::string text;
  std::getline(file, text);
  if (text.empty()) {
    return std::nullopt;
  }

  while (!text.empty() && (text.back() == '\n' || text.back() == '\r' || text.back() == ' ' || text.back() == '\t')) {
    text.pop_back();
  }
  return text;
}

std::optional<double> readTempInputCelsius(const std::filesystem::path& path) {
  std::ifstream file{path};
  if (!file.is_open()) {
    return std::nullopt;
  }

  long long raw = 0;
  file >> raw;
  if (file.fail() || raw <= 0) {
    return std::nullopt;
  }

  // Most Linux temp files are millidegrees Celsius.
  if (raw >= 1000) {
    return static_cast<double>(raw) / 1000.0;
  }
  return static_cast<double>(raw);
}

std::string toLower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return value;
}

int scoreHwmonSensor(const std::string& hwmon_name, const std::string& label) {
  int score = 0;
  const std::string name = toLower(hwmon_name);
  const std::string lbl = toLower(label);

  if (name.find("coretemp") != std::string::npos || name.find("k10temp") != std::string::npos ||
      name.find("zenpower") != std::string::npos || name.find("cpu") != std::string::npos) {
    score += 20;
  }

  if (lbl.find("package") != std::string::npos || lbl.find("tctl") != std::string::npos ||
      lbl.find("tdie") != std::string::npos || lbl.find("cpu") != std::string::npos) {
    score += 30;
  }

  return score;
}

bool isCpuThermalZoneType(const std::string& type) {
  const std::string t = toLower(type);
  return t.find("x86_pkg_temp") != std::string::npos || t.find("cpu") != std::string::npos ||
         t.find("soc") != std::string::npos || t.find("package") != std::string::npos;
}

} // namespace

SystemMonitorService::SystemMonitorService() { start(); }

SystemMonitorService::~SystemMonitorService() { stop(); }

bool SystemMonitorService::isRunning() const noexcept { return m_running.load(); }

SystemStats SystemMonitorService::latest() const {
  std::lock_guard lock{m_statsMutex};
  return m_latest;
}

void SystemMonitorService::start() {
  if (m_running.load()) {
    return;
  }

  m_running = true;
  m_thread = std::thread([this]() { samplingLoop(); });
}

void SystemMonitorService::stop() {
  m_running = false;
  if (m_thread.joinable()) {
    m_thread.join();
  }
}

void SystemMonitorService::samplingLoop() {
  auto prev_cpu = readCpuTotals();

  while (m_running.load()) {
    SystemStats next{};

    const auto current_cpu = readCpuTotals();
    if (prev_cpu.has_value() && current_cpu.has_value()) {
      const std::uint64_t total_delta = current_cpu->total - prev_cpu->total;
      const std::uint64_t idle_delta = current_cpu->idle - prev_cpu->idle;
      if (total_delta > 0) {
        next.cpuUsagePercent = 100.0 * (1.0 - static_cast<double>(idle_delta) / static_cast<double>(total_delta));
      }
    }
    if (current_cpu.has_value()) {
      prev_cpu = current_cpu;
    }

    const auto ram_kb = readRamKb();
    if (ram_kb.has_value()) {
      const std::uint64_t total_kb = ram_kb->first;
      const std::uint64_t used_kb = ram_kb->second;
      next.ramTotalMb = total_kb / 1024;
      next.ramUsedMb = used_kb / 1024;
      if (total_kb > 0) {
        next.ramUsagePercent = 100.0 * static_cast<double>(used_kb) / static_cast<double>(total_kb);
      }
    }

    next.cpuTempC = readCpuTempCelsius();

    {
      std::lock_guard lock{m_statsMutex};
      m_latest = next;
    }

    if (next.cpuTempC.has_value()) {
      logDebug("system monitor cpu={:.1f}% ram={:.1f}% ({}/{} MB) temp={:.1f}C", next.cpuUsagePercent,
               next.ramUsagePercent, next.ramUsedMb, next.ramTotalMb, *next.cpuTempC);
    } else {
      logDebug("system monitor cpu={:.1f}% ram={:.1f}% ({}/{} MB) temp=n/a", next.cpuUsagePercent,
               next.ramUsagePercent, next.ramUsedMb, next.ramTotalMb);
    }

    std::this_thread::sleep_for(std::chrono::seconds(2));
  }
}

std::optional<SystemMonitorService::CpuTotals> SystemMonitorService::readCpuTotals() {
  std::ifstream file{"/proc/stat"};
  if (!file.is_open()) {
    return std::nullopt;
  }

  std::string line;
  if (!std::getline(file, line)) {
    return std::nullopt;
  }

  std::istringstream iss{line};
  std::string cpu_label;
  std::uint64_t user = 0;
  std::uint64_t nice = 0;
  std::uint64_t system = 0;
  std::uint64_t idle = 0;
  std::uint64_t iowait = 0;
  std::uint64_t irq = 0;
  std::uint64_t softirq = 0;
  std::uint64_t steal = 0;

  iss >> cpu_label >> user >> nice >> system >> idle >> iowait >> irq >> softirq >> steal;
  if (cpu_label != "cpu") {
    return std::nullopt;
  }

  CpuTotals totals{};
  totals.idle = idle + iowait;
  totals.total = user + nice + system + idle + iowait + irq + softirq + steal;
  return totals;
}

std::optional<std::pair<std::uint64_t, std::uint64_t>> SystemMonitorService::readRamKb() {
  std::ifstream file{"/proc/meminfo"};
  if (!file.is_open()) {
    return std::nullopt;
  }

  std::string key;
  std::uint64_t value_kb = 0;
  std::string unit;

  std::uint64_t total_kb = 0;
  std::uint64_t available_kb = 0;

  while (file >> key >> value_kb >> unit) {
    if (key == "MemTotal:") {
      total_kb = value_kb;
    } else if (key == "MemAvailable:") {
      available_kb = value_kb;
    }

    if (total_kb > 0 && available_kb > 0) {
      break;
    }
  }

  if (total_kb == 0 || available_kb == 0 || available_kb > total_kb) {
    return std::nullopt;
  }

  const std::uint64_t used_kb = total_kb - available_kb;
  return std::make_pair(total_kb, used_kb);
}

std::optional<double> SystemMonitorService::readCpuTempCelsius() {
  namespace fs = std::filesystem;

  const fs::path hwmon_root{"/sys/class/hwmon"};
  if (fs::exists(hwmon_root) && fs::is_directory(hwmon_root)) {
    int best_score = -1;
    std::optional<double> best_temp;

    for (const auto& hwmon_entry : fs::directory_iterator{hwmon_root}) {
      if (!hwmon_entry.is_directory()) {
        continue;
      }

      const std::string hwmon_name = readSmallTextFile(hwmon_entry.path() / "name").value_or("");
      for (const auto& file_entry : fs::directory_iterator{hwmon_entry.path()}) {
        if (!file_entry.is_regular_file()) {
          continue;
        }

        const std::string file_name = file_entry.path().filename().string();
        if (!file_name.starts_with("temp") || !file_name.ends_with("_input")) {
          continue;
        }

        const std::string base = file_name.substr(0, file_name.size() - 6);
        const std::string label = readSmallTextFile(hwmon_entry.path() / (base + "_label")).value_or("");
        const auto temp_c = readTempInputCelsius(file_entry.path());
        if (!temp_c.has_value()) {
          continue;
        }

        const int score = scoreHwmonSensor(hwmon_name, label);
        if (score > best_score) {
          best_score = score;
          best_temp = *temp_c;
        }
      }
    }

    if (best_temp.has_value()) {
      return best_temp;
    }
  }

  const fs::path thermal_root{"/sys/class/thermal"};
  if (!fs::exists(thermal_root) || !fs::is_directory(thermal_root)) {
    return std::nullopt;
  }

  std::optional<double> fallback_temp;
  for (const auto& entry : fs::directory_iterator{thermal_root}) {
    if (!entry.is_directory()) {
      continue;
    }

    const auto zone_name = entry.path().filename().string();
    if (!zone_name.starts_with("thermal_zone")) {
      continue;
    }

    const std::string zone_type = readSmallTextFile(entry.path() / "type").value_or("");
    const fs::path temp_path = entry.path() / "temp";
    const auto temp_c = readTempInputCelsius(temp_path);
    if (!temp_c.has_value()) {
      continue;
    }

    if (isCpuThermalZoneType(zone_type)) {
      return temp_c;
    }

    if (!fallback_temp.has_value()) {
      fallback_temp = temp_c;
    }
  }

  return fallback_temp;
}
