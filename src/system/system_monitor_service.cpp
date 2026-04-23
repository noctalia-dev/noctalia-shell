#include "system/system_monitor_service.h"

#include "core/log.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <sys/statvfs.h>
#include <vector>

namespace {

  [[nodiscard]] SystemStats makeInitialHistoryStats() {
    SystemStats stats;
    stats.cpuTempC = 40.0;
    return stats;
  }

  template <typename T, std::size_t N>
  [[nodiscard]] std::vector<T> historyWindowFromRing(const std::array<T, N>& ring, int head, int windowSize) {
    if (windowSize <= 0) {
      return {};
    }

    const int ringSize = static_cast<int>(N);
    const int clampedWindow = std::min(windowSize, ringSize);
    std::vector<T> result;
    result.reserve(static_cast<std::size_t>(clampedWindow));
    const int start = (head - clampedWindow + ringSize) % ringSize;
    for (int i = 0; i < clampedWindow; ++i) {
      const int idx = (start + i) % ringSize;
      result.push_back(ring[static_cast<std::size_t>(idx)]);
    }
    return result;
  }

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

  constexpr Logger kLog("sysmon");

} // namespace

SystemMonitorService::SystemMonitorService() {
  m_latest = makeInitialHistoryStats();
  m_history.fill(m_latest);
  start();
}

SystemMonitorService::~SystemMonitorService() { stop(); }

bool SystemMonitorService::isRunning() const noexcept { return m_running.load(); }

SystemStats SystemMonitorService::latest() const {
  std::lock_guard lock{m_statsMutex};
  return m_latest;
}

std::vector<SystemStats> SystemMonitorService::history(int windowSize) const {
  std::lock_guard lock{m_statsMutex};
  return historyWindowFromRing(m_history, m_historyHead, windowSize);
}

void SystemMonitorService::retainCpuTemp() { m_cpuTempRefs.fetch_add(1, std::memory_order_relaxed); }

void SystemMonitorService::releaseCpuTemp() { m_cpuTempRefs.fetch_sub(1, std::memory_order_relaxed); }

void SystemMonitorService::retainDiskPath(const std::string& path) {
  const float initialPercent = readDiskUsagePercent(path);
  std::lock_guard lock{m_statsMutex};
  auto& disk = m_diskHistories[path];
  if (disk.refs == 0) {
    disk.latestPercent = initialPercent;
    disk.history.fill(initialPercent);
  }
  ++disk.refs;
}

void SystemMonitorService::releaseDiskPath(const std::string& path) {
  std::lock_guard lock{m_statsMutex};
  const auto it = m_diskHistories.find(path);
  if (it == m_diskHistories.end()) {
    return;
  }
  --it->second.refs;
  if (it->second.refs <= 0) {
    m_diskHistories.erase(it);
  }
}

float SystemMonitorService::diskUsagePercent(const std::string& path) const {
  std::lock_guard lock{m_statsMutex};
  const auto it = m_diskHistories.find(path);
  return it != m_diskHistories.end() ? it->second.latestPercent : 0.0f;
}

std::vector<float> SystemMonitorService::diskHistory(const std::string& path, int windowSize) const {
  std::lock_guard lock{m_statsMutex};
  const auto it = m_diskHistories.find(path);
  if (it == m_diskHistories.end() || windowSize <= 0) {
    return {};
  }
  return historyWindowFromRing(it->second.history, m_historyHead, windowSize);
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
  auto prevCpu = readCpuTotals();

  while (m_running.load()) {
    SystemStats next{};
    next.sampledAt = std::chrono::steady_clock::now();
    std::vector<std::string> diskPaths;
    std::optional<double> previousCpuTemp;

    const auto currentCpu = readCpuTotals();
    if (prevCpu.has_value() && currentCpu.has_value()) {
      const std::uint64_t totalDelta = currentCpu->total - prevCpu->total;
      const std::uint64_t idleDelta = currentCpu->idle - prevCpu->idle;
      if (totalDelta > 0) {
        next.cpuUsagePercent = 100.0 * (1.0 - static_cast<double>(idleDelta) / static_cast<double>(totalDelta));
      }
    }
    if (currentCpu.has_value()) {
      prevCpu = currentCpu;
    }

    const auto memKb = readMemoryKb();
    if (memKb.has_value()) {
      next.ramTotalMb = memKb->totalKb / 1024;
      next.ramUsedMb = memKb->usedKb / 1024;
      if (memKb->totalKb > 0) {
        next.ramUsagePercent = 100.0 * static_cast<double>(memKb->usedKb) / static_cast<double>(memKb->totalKb);
      }
      next.swapTotalMb = memKb->swapTotalKb / 1024;
      next.swapUsedMb = memKb->swapUsedKb / 1024;
    }

    const auto currentNetBytes = readNetBytes();
    if (currentNetBytes.has_value()) {
      double totalRx = 0.0;
      double totalTx = 0.0;
      for (const auto& [iface, cur] : *currentNetBytes) {
        const auto it = m_prevNetBytes.find(iface);
        if (it != m_prevNetBytes.end()) {
          if (cur.rx >= it->second.rx) {
            totalRx += static_cast<double>(cur.rx - it->second.rx);
          }
          if (cur.tx >= it->second.tx) {
            totalTx += static_cast<double>(cur.tx - it->second.tx);
          }
        }
      }
      m_prevNetBytes = *currentNetBytes;
      next.netRxBytesPerSec = totalRx;
      next.netTxBytesPerSec = totalTx;
    }

    const auto la = readLoadAvg();
    if (la.has_value()) {
      next.loadAvg1 = (*la)[0];
      next.loadAvg5 = (*la)[1];
      next.loadAvg15 = (*la)[2];
    }

    {
      std::lock_guard lock{m_statsMutex};
      previousCpuTemp = m_latest.cpuTempC;
      diskPaths.reserve(m_diskHistories.size());
      for (const auto& [path, disk] : m_diskHistories) {
        if (disk.refs > 0) {
          diskPaths.push_back(path);
        }
      }
    }

    if (m_cpuTempRefs.load(std::memory_order_relaxed) > 0) {
      next.cpuTempC = readCpuTempCelsius();
    }
    if (!next.cpuTempC.has_value()) {
      next.cpuTempC = previousCpuTemp.value_or(40.0);
    }

    std::vector<std::pair<std::string, float>> diskPercents;
    diskPercents.reserve(diskPaths.size());
    for (const auto& path : diskPaths) {
      diskPercents.emplace_back(path, readDiskUsagePercent(path));
    }

    {
      std::lock_guard lock{m_statsMutex};
      const int writeIndex = m_historyHead;
      m_latest = next;
      m_history[writeIndex] = next;
      for (const auto& [path, percent] : diskPercents) {
        const auto it = m_diskHistories.find(path);
        if (it == m_diskHistories.end() || it->second.refs <= 0) {
          continue;
        }
        it->second.latestPercent = percent;
        it->second.history[writeIndex] = percent;
      }
      m_historyHead = (m_historyHead + 1) % kHistorySize;
    }

    // if (next.cpuTempC.has_value()) {
    //   kLog.debug("cpu={:.1f}% ram={:.1f}% ({}/{} MB) swap={}/{} MB temp={:.1f}C", next.cpuUsagePercent,
    //              next.ramUsagePercent, next.ramUsedMb, next.ramTotalMb, next.swapUsedMb, next.swapTotalMb,
    //              *next.cpuTempC);
    // } else {
    //   kLog.debug("cpu={:.1f}% ram={:.1f}% ({}/{} MB) swap={}/{} MB temp=n/a", next.cpuUsagePercent,
    //              next.ramUsagePercent, next.ramUsedMb, next.ramTotalMb, next.swapUsedMb, next.swapTotalMb);
    // }

    std::this_thread::sleep_for(std::chrono::seconds(1));
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
  std::string cpuLabel;
  std::uint64_t user = 0;
  std::uint64_t nice = 0;
  std::uint64_t system = 0;
  std::uint64_t idle = 0;
  std::uint64_t iowait = 0;
  std::uint64_t irq = 0;
  std::uint64_t softirq = 0;
  std::uint64_t steal = 0;

  iss >> cpuLabel >> user >> nice >> system >> idle >> iowait >> irq >> softirq >> steal;
  if (cpuLabel != "cpu") {
    return std::nullopt;
  }

  CpuTotals totals{};
  totals.idle = idle + iowait;
  totals.total = user + nice + system + idle + iowait + irq + softirq + steal;
  return totals;
}

std::optional<SystemMonitorService::MemData> SystemMonitorService::readMemoryKb() {
  std::ifstream file{"/proc/meminfo"};
  if (!file.is_open()) {
    return std::nullopt;
  }

  std::string key;
  std::uint64_t value_kb = 0;
  std::string unit;

  std::uint64_t totalKb = 0;
  std::uint64_t availableKb = 0;
  std::uint64_t swapTotalKb = 0;
  std::uint64_t swapFreeKb = 0;

  while (file >> key >> value_kb >> unit) {
    if (key == "MemTotal:") {
      totalKb = value_kb;
    } else if (key == "MemAvailable:") {
      availableKb = value_kb;
    } else if (key == "SwapTotal:") {
      swapTotalKb = value_kb;
    } else if (key == "SwapFree:") {
      swapFreeKb = value_kb;
    }

    // SwapFree appears last, after that there's nothing we need
    if (key == "SwapFree:") {
      break;
    }
  }

  if (totalKb == 0 || availableKb == 0 || availableKb > totalKb) {
    return std::nullopt;
  }

  MemData data;
  data.totalKb = totalKb;
  data.usedKb = totalKb - availableKb;
  data.swapTotalKb = swapTotalKb;
  data.swapUsedKb = swapTotalKb > swapFreeKb ? swapTotalKb - swapFreeKb : 0;
  return data;
}

std::optional<double> SystemMonitorService::readCpuTempCelsius() {
  namespace fs = std::filesystem;

  const fs::path hwmon_root{"/sys/class/hwmon"};
  if (fs::exists(hwmon_root) && fs::is_directory(hwmon_root)) {
    int bestScore = -1;
    std::optional<double> best_temp;

    for (const auto& hwmon_entry : fs::directory_iterator{hwmon_root}) {
      if (!hwmon_entry.is_directory()) {
        continue;
      }

      const std::string hwmonName = readSmallTextFile(hwmon_entry.path() / "name").value_or("");
      for (const auto& file_entry : fs::directory_iterator{hwmon_entry.path()}) {
        if (!file_entry.is_regular_file()) {
          continue;
        }

        const std::string fileName = file_entry.path().filename().string();
        if (!fileName.starts_with("temp") || !fileName.ends_with("_input")) {
          continue;
        }

        const std::string base = fileName.substr(0, fileName.size() - 6);
        const std::string label = readSmallTextFile(hwmon_entry.path() / (base + "_label")).value_or("");
        const auto tempC = readTempInputCelsius(file_entry.path());
        if (!tempC.has_value()) {
          continue;
        }

        const int score = scoreHwmonSensor(hwmonName, label);
        if (score > bestScore) {
          bestScore = score;
          best_temp = *tempC;
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

    const auto zoneName = entry.path().filename().string();
    if (!zoneName.starts_with("thermal_zone")) {
      continue;
    }

    const std::string zoneType = readSmallTextFile(entry.path() / "type").value_or("");
    const fs::path temp_path = entry.path() / "temp";
    const auto tempC = readTempInputCelsius(temp_path);
    if (!tempC.has_value()) {
      continue;
    }

    if (isCpuThermalZoneType(zoneType)) {
      return tempC;
    }

    if (!fallback_temp.has_value()) {
      fallback_temp = tempC;
    }
  }

  return fallback_temp;
}

float SystemMonitorService::readDiskUsagePercent(const std::string& path) {
  struct statvfs sv{};
  if (::statvfs(path.c_str(), &sv) == 0 && sv.f_blocks > 0) {
    const double used = static_cast<double>(sv.f_blocks - sv.f_bfree);
    const double total = static_cast<double>(sv.f_blocks);
    return static_cast<float>(100.0 * used / total);
  }
  return 0.0f;
}

std::optional<std::unordered_map<std::string, SystemMonitorService::NetIfaceBytes>>
SystemMonitorService::readNetBytes() {
  std::ifstream file{"/proc/net/dev"};
  if (!file.is_open()) {
    return std::nullopt;
  }

  std::unordered_map<std::string, NetIfaceBytes> result;
  std::string line;
  // Skip 2 header lines
  std::getline(file, line);
  std::getline(file, line);

  while (std::getline(file, line)) {
    const auto colonPos = line.find(':');
    if (colonPos == std::string::npos) {
      continue;
    }

    std::string iface = line.substr(0, colonPos);
    while (!iface.empty() && iface.front() == ' ') {
      iface.erase(iface.begin());
    }
    if (iface == "lo") {
      continue;
    }

    std::istringstream iss{line.substr(colonPos + 1)};
    std::uint64_t rxBytes = 0;
    std::uint64_t val = 0;
    iss >> rxBytes;
    // Skip 7 fields (rx_packets, errs, drop, fifo, frame, compressed, multicast)
    for (int i = 0; i < 7 && iss; ++i) {
      iss >> val;
    }
    std::uint64_t txBytes = 0;
    iss >> txBytes;

    if (rxBytes == 0 && txBytes == 0) {
      continue;
    }

    result[iface] = {rxBytes, txBytes};
  }

  return result;
}

std::optional<std::array<double, 3>> SystemMonitorService::readLoadAvg() {
  std::ifstream file{"/proc/loadavg"};
  if (!file.is_open()) {
    return std::nullopt;
  }

  std::array<double, 3> la{};
  file >> la[0] >> la[1] >> la[2];
  if (file.fail()) {
    return std::nullopt;
  }
  return la;
}
