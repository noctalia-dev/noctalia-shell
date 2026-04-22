#pragma once

#include <array>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <optional>
#include <thread>
#include <vector>

struct SystemStats {
  double cpuUsagePercent{0.0};
  double ramUsagePercent{0.0};
  std::uint64_t ramUsedMb{0};
  std::uint64_t ramTotalMb{0};
  std::uint64_t swapUsedMb{0};
  std::uint64_t swapTotalMb{0};
  std::optional<double> cpuTempC;
};

class SystemMonitorService {
public:
  SystemMonitorService();
  ~SystemMonitorService();

  SystemMonitorService(const SystemMonitorService&) = delete;
  SystemMonitorService& operator=(const SystemMonitorService&) = delete;

  static constexpr int kHistorySize = 120;

  [[nodiscard]] bool isRunning() const noexcept;
  [[nodiscard]] SystemStats latest() const;
  [[nodiscard]] std::vector<SystemStats> history() const;
  [[nodiscard]] int historyCount() const;

  void retainCpuTemp();
  void releaseCpuTemp();

private:
  struct CpuTotals {
    std::uint64_t total{0};
    std::uint64_t idle{0};
  };

  void start();
  void stop();
  void samplingLoop();

  [[nodiscard]] static std::optional<CpuTotals> readCpuTotals();
  struct MemData {
    std::uint64_t totalKb{0};
    std::uint64_t usedKb{0};
    std::uint64_t swapTotalKb{0};
    std::uint64_t swapUsedKb{0};
  };
  [[nodiscard]] static std::optional<MemData> readMemoryKb();
  [[nodiscard]] static std::optional<double> readCpuTempCelsius();

  std::atomic<bool> m_running{false};
  std::atomic<int> m_cpuTempRefs{0};
  std::thread m_thread;

  mutable std::mutex m_statsMutex;
  SystemStats m_latest;
  std::array<SystemStats, kHistorySize> m_history{};
  int m_historyHead = 0;
  int m_historyCount = 0;
};
