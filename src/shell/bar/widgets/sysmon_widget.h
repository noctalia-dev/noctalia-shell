#pragma once

#include "core/timer_manager.h"
#include "shell/bar/widget.h"

#include <chrono>
#include <string>

class Glyph;
class GraphNode;
class Label;
class ProgressBar;
class RectNode;
class SystemMonitorService;
struct SystemStats;

enum class SysmonStat { CpuUsage, CpuTemp, RamUsed, RamPct, SwapPct, DiskPct };
enum class SysmonDisplayMode { Text, Graph, Gauge };

class SysmonWidget : public Widget {
public:
  SysmonWidget(SystemMonitorService* monitor, SysmonStat stat, std::string diskPath, SysmonDisplayMode displayMode,
               bool showLabel = true);
  ~SysmonWidget() override;

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void onFrameTick(float deltaMs) override;
  [[nodiscard]] bool needsFrameTick() const override;
  bool syncLabelText(const std::string& raw);
  void syncGaugeProgress(double normalized);
  [[nodiscard]] std::string formatValue() const;
  [[nodiscard]] double currentNormalized();
  [[nodiscard]] static const char* glyphName(SysmonStat stat);
  void scheduleNextUpdate(std::chrono::steady_clock::time_point latestSampleAt);
  void updateGraph();
  [[nodiscard]] static float scrollProgressForSample(std::chrono::steady_clock::time_point sampledAt);
  [[nodiscard]] static double normalizedFromStats(SysmonStat stat, const SystemStats& stats, double& tempMin,
                                                  double& tempMax);

  SystemMonitorService* m_monitor;
  SysmonStat m_stat;
  SysmonDisplayMode m_displayMode;
  bool m_showLabel;
  std::string m_diskPath;
  std::string m_lastRawValue;
  bool m_isVerticalBar = false;
  bool m_lastLabelVertical = false;

  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;

  static constexpr int kHistorySamples = 30;
  bool m_graphInitialized = false;
  std::chrono::steady_clock::time_point m_lastSampleAt{};
  double m_tempMin = 30.0;
  double m_tempMax = 80.0;
  RectNode* m_chartBg = nullptr;
  GraphNode* m_graphNode = nullptr;
  float m_scrollProgress = 1.0f;
  Timer m_updateTimer;

  // Gauge mode
  ProgressBar* m_gauge = nullptr;
};
