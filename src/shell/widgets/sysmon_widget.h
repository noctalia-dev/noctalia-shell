#pragma once

#include "shell/widget/widget.h"

#include <array>
#include <string>

class Glyph;
class Label;
class ProgressBar;
class RectNode;
class SystemMonitorService;

enum class SysmonStat { CpuUsage, CpuTemp, RamUsed, RamPct, SwapPct, DiskPct };
enum class SysmonDisplayMode { Text, Graph, Gauge };

class SysmonWidget : public Widget {
public:
  SysmonWidget(SystemMonitorService* monitor, SysmonStat stat, std::string diskPath,
               SysmonDisplayMode displayMode);
  ~SysmonWidget() override;

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  [[nodiscard]] std::string formatValue() const;
  [[nodiscard]] double currentNormalized() const;
  [[nodiscard]] static const char* glyphName(SysmonStat stat);
  void pushHistory(double normalized);
  void updateBars();

  SystemMonitorService* m_monitor;
  SysmonStat m_stat;
  SysmonDisplayMode m_displayMode;
  std::string m_diskPath;
  std::string m_lastText;

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
  std::array<ProgressBar*, kHistorySamples> m_bars{};

  // Gauge mode
  ProgressBar* m_gauge = nullptr;
};
