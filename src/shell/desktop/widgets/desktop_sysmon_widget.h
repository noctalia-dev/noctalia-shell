#pragma once

#include "shell/desktop/desktop_widget.h"
#include "ui/palette.h"

#include <array>
#include <cstdint>
#include <optional>
#include <string>

class Glyph;
class GraphNode;
class Label;
class SystemMonitorService;

enum class DesktopSysmonStat : std::uint8_t { CpuUsage, CpuTemp, RamPct, SwapPct };

class DesktopSysmonWidget : public DesktopWidget {
public:
  DesktopSysmonWidget(SystemMonitorService* monitor, DesktopSysmonStat stat, std::optional<DesktopSysmonStat> stat2,
                      ThemeColor lineColor, ThemeColor lineColor2, bool showLabel, bool shadow);
  ~DesktopSysmonWidget() override;

  void create() override;
  [[nodiscard]] bool wantsSecondTicks() const override { return true; }
  [[nodiscard]] bool needsFrameTick() const override;
  void onFrameTick(float deltaMs, Renderer& renderer) override;

private:
  void doLayout(Renderer& renderer) override;
  void doUpdate(Renderer& renderer) override;

  [[nodiscard]] double normalizedFor(DesktopSysmonStat stat) const;
  [[nodiscard]] std::string formatValueFor(DesktopSysmonStat stat) const;
  void pushHistory();
  void updateGraph();
  [[nodiscard]] static const char* glyphName(DesktopSysmonStat stat);

  SystemMonitorService* m_monitor;
  DesktopSysmonStat m_stat;
  std::optional<DesktopSysmonStat> m_stat2;
  ThemeColor m_lineColor;
  ThemeColor m_lineColor2;
  bool m_showLabel;
  bool m_shadow;

  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;
  GraphNode* m_graphNode = nullptr;

  static constexpr int kHistorySamples = 60;
  std::array<double, kHistorySamples> m_history1{};
  std::array<double, kHistorySamples> m_history2{};
  int m_historyHead = 0;
  float m_scrollProgress = 1.0f;
  std::string m_lastRawValue;

  mutable double m_tempMin1 = 30.0;
  mutable double m_tempMax1 = 80.0;
  mutable double m_tempMin2 = 30.0;
  mutable double m_tempMax2 = 80.0;
};
