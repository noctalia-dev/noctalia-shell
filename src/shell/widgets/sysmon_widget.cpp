#include "shell/widgets/sysmon_widget.h"

#include "render/core/renderer.h"
#include "system/system_monitor_service.h"
#include "ui/controls/icon.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <format>
#include <sys/statvfs.h>

SysmonWidget::SysmonWidget(SystemMonitorService* monitor, SysmonStat stat, std::string diskPath)
    : m_monitor(monitor), m_stat(stat), m_diskPath(std::move(diskPath)) {}

void SysmonWidget::create(Renderer& renderer) {
  auto container = std::make_unique<Node>();

  auto icon = std::make_unique<Icon>();
  icon->setIcon(iconName(m_stat));
  icon->setIconSize(Style::fontSizeBody * m_contentScale);
  icon->setColor(palette.onSurface);
  m_icon = icon.get();
  container->addChild(std::move(icon));

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  m_label = label.get();
  container->addChild(std::move(label));

  m_root = std::move(container);
  update(renderer);
}

void SysmonWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (m_icon == nullptr || m_label == nullptr || rootNode == nullptr) {
    return;
  }

  m_icon->measure(renderer);
  m_label->measure(renderer);

  m_icon->setPosition(0.0f, 0.0f);
  m_label->setPosition(m_icon->width() + Style::spaceXs, 0.0f);

  rootNode->setSize(m_label->x() + m_label->width(), m_icon->height());
}

void SysmonWidget::update(Renderer& renderer) {
  if (m_icon == nullptr || m_label == nullptr) {
    return;
  }

  auto text = formatValue();
  if (text == m_lastText) {
    return;
  }

  m_lastText = std::move(text);
  m_label->setText(m_lastText);
  m_label->measure(renderer);
  requestRedraw();

  Widget::update(renderer);
}

std::string SysmonWidget::formatValue() const {
  if (m_stat == SysmonStat::DiskPct) {
    struct statvfs sv {};
    if (::statvfs(m_diskPath.c_str(), &sv) == 0 && sv.f_blocks > 0) {
      const double used = static_cast<double>(sv.f_blocks - sv.f_bfree);
      const double total = static_cast<double>(sv.f_blocks);
      return std::format("{:.0f}%", used / total * 100.0);
    }
    return "--";
  }

  if (m_monitor == nullptr) {
    return "--";
  }

  const auto stats = m_monitor->latest();

  switch (m_stat) {
  case SysmonStat::CpuUsage:
    return std::format("{:.0f}%", stats.cpuUsagePercent);

  case SysmonStat::CpuTemp:
    if (stats.cpuTempC.has_value()) {
      return std::format("{:.0f}°C", *stats.cpuTempC);
    }
    return "--";

  case SysmonStat::RamUsed:
    if (stats.ramUsedMb >= 1024) {
      return std::format("{:.1f}G", static_cast<double>(stats.ramUsedMb) / 1024.0);
    }
    return std::format("{}M", stats.ramUsedMb);

  case SysmonStat::RamPct:
    return std::format("{:.0f}%", stats.ramUsagePercent);

  case SysmonStat::SwapPct:
    if (stats.swapTotalMb > 0) {
      return std::format("{:.0f}%",
                         100.0 * static_cast<double>(stats.swapUsedMb) / static_cast<double>(stats.swapTotalMb));
    }
    return "--";

  case SysmonStat::DiskPct:
    break; // handled above
  }

  return "--";
}

const char* SysmonWidget::iconName(SysmonStat stat) {
  switch (stat) {
  case SysmonStat::CpuUsage:
    return "cpu-usage";
  case SysmonStat::CpuTemp:
    return "cpu-temperature";
  case SysmonStat::RamUsed:
  case SysmonStat::RamPct:
    return "memory";
  case SysmonStat::SwapPct:
  case SysmonStat::DiskPct:
    return "storage";
  }
  return "cpu-usage";
}
