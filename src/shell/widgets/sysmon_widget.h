#pragma once

#include "shell/widget/widget.h"

#include <string>

class Icon;
class Label;
class SystemMonitorService;

enum class SysmonStat { CpuUsage, CpuTemp, RamUsed, RamPct, SwapPct, DiskPct };

class SysmonWidget : public Widget {
public:
  SysmonWidget(SystemMonitorService* monitor, SysmonStat stat, std::string diskPath);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  [[nodiscard]] std::string formatValue() const;
  [[nodiscard]] static const char* iconName(SysmonStat stat);

  SystemMonitorService* m_monitor;
  SysmonStat m_stat;
  std::string m_diskPath;
  std::string m_lastText;

  Icon* m_icon = nullptr;
  Label* m_label = nullptr;
};
