#pragma once

#include "shell/bar/widget.h"

#include <array>
#include <string>

class Glyph;
class GraphNode;
class Label;
class ProgressBar;
class RectNode;
class SystemMonitorService;

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
  [[nodiscard]] double currentNormalized() const;
  [[nodiscard]] static const char* glyphName(SysmonStat stat);
  void pushHistory(double normalized);
  void updateGraph();

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

  // Graph mode
  static constexpr int kHistorySamples = 30;
  std::array<double, kHistorySamples> m_history{};
  int m_historyHead = 0;
  double m_tempMin = 30.0;
  double m_tempMax = 80.0;
  // Graph mode
  RectNode* m_chartBg = nullptr;
  GraphNode* m_graphNode = nullptr;
  float m_scrollProgress = 1.0f;

  // Gauge mode
  ProgressBar* m_gauge = nullptr;
};
