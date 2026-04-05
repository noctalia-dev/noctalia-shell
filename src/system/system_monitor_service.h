#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <optional>
#include <thread>

struct SystemStats {
  double cpuUsagePercent{0.0};
  double ramUsagePercent{0.0};
  std::uint64_t ramUsedMb{0};
  std::uint64_t ramTotalMb{0};
  std::optional<double> cpuTempC;
};

class SystemMonitorService {
public:
  SystemMonitorService();
  ~SystemMonitorService();

  SystemMonitorService(const SystemMonitorService&) = delete;
  SystemMonitorService& operator=(const SystemMonitorService&) = delete;

  [[nodiscard]] bool isRunning() const noexcept;
  [[nodiscard]] SystemStats latest() const;

private:
  struct CpuTotals {
    std::uint64_t total{0};
    std::uint64_t idle{0};
  };

  void start();
  void stop();
  void samplingLoop();

  [[nodiscard]] static std::optional<CpuTotals> readCpuTotals();
  [[nodiscard]] static std::optional<std::pair<std::uint64_t, std::uint64_t>> readRamKb();
  [[nodiscard]] static std::optional<double> readCpuTempCelsius();

  std::atomic<bool> m_running{false};
  std::thread m_thread;

  mutable std::mutex m_statsMutex;
  SystemStats m_latest;
};
