#include "shell/widgets/sysmon_widget.h"

#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "render/scene/rect_node.h"
#include "system/system_monitor_service.h"
#include "ui/controls/icon.h"
#include "ui/controls/label.h"
#include "ui/controls/progress_bar.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <format>
#include <sys/statvfs.h>

SysmonWidget::SysmonWidget(SystemMonitorService* monitor, SysmonStat stat, std::string diskPath,
                           SysmonDisplayMode displayMode)
    : m_monitor(monitor), m_stat(stat), m_displayMode(displayMode), m_diskPath(std::move(diskPath)) {
  if (m_stat == SysmonStat::CpuTemp && m_monitor != nullptr) {
    m_monitor->retainCpuTemp();
  }
}

SysmonWidget::~SysmonWidget() {
  if (m_stat == SysmonStat::CpuTemp && m_monitor != nullptr) {
    m_monitor->releaseCpuTemp();
  }
}

void SysmonWidget::create(Renderer& renderer) {
  auto container = std::make_unique<Node>();

  auto icon = std::make_unique<Icon>();
  icon->setIcon(iconName(m_stat));
  icon->setIconSize(Style::fontSizeBody * m_contentScale);
  icon->setColor(palette.onSurface);
  m_icon = icon.get();
  container->addChild(std::move(icon));

  if (m_displayMode == SysmonDisplayMode::Graph) {
    auto chartBg = std::make_unique<RectNode>();
    RoundedRectStyle bgStyle;
    bgStyle.fill = palette.surfaceVariant;
    bgStyle.radius = Style::radiusSm;
    bgStyle.softness = 0.5f;
    chartBg->setStyle(bgStyle);
    m_chartBg = static_cast<RectNode*>(container->addChild(std::move(chartBg)));

    for (int i = 0; i < kHistorySamples; i++) {
      auto bar = std::make_unique<ProgressBar>();
      bar->setOrientation(ProgressBarOrientation::Vertical);
      bar->setFillColor(palette.primary);
      bar->setTrackColor(Color{0, 0, 0, 0});
      bar->setRadius(0.0f);
      bar->setProgress(0.0f);
      m_bars[i] = static_cast<ProgressBar*>(m_chartBg->addChild(std::move(bar)));
    }
  }

  if (m_displayMode == SysmonDisplayMode::Gauge) {
    auto gauge = std::make_unique<ProgressBar>();
    gauge->setOrientation(ProgressBarOrientation::Vertical);
    gauge->setFillColor(palette.primary);
    gauge->setTrackColor(palette.surfaceVariant);
    gauge->setProgress(0.0f);
    m_gauge = static_cast<ProgressBar*>(container->addChild(std::move(gauge)));
  }

  if (m_displayMode != SysmonDisplayMode::Gauge) {
    auto label = std::make_unique<Label>();
    label->setBold(true);
    label->setFontSize(Style::fontSizeBody * m_contentScale);
    m_label = label.get();
    container->addChild(std::move(label));
  }

  m_root = std::move(container);
  update(renderer);
}

void SysmonWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (m_icon == nullptr || rootNode == nullptr) {
    return;
  }

  m_icon->measure(renderer);
  const float iconH = m_icon->height();

  if (m_displayMode == SysmonDisplayMode::Gauge && m_gauge != nullptr) {
    const float gaugeW = std::max(3.0f, roundf(iconH * 0.25f));
    m_gauge->setRadius(gaugeW / 2.0f);

    m_icon->setPosition(0.0f, 0.0f);
    m_gauge->setPosition(m_icon->width() + static_cast<float>(Style::spaceXs), 0.0f);
    m_gauge->setSize(gaugeW, iconH);

    rootNode->setSize(m_gauge->x() + gaugeW, iconH);
    return;
  }

  if (m_label == nullptr) {
    return;
  }
  m_label->measure(renderer);

  if (m_displayMode == SysmonDisplayMode::Graph && m_chartBg != nullptr) {
    const float chartW = 50.0f * m_contentScale;

    m_icon->setPosition(0.0f, 0.0f);
    m_chartBg->setPosition(m_icon->width() + static_cast<float>(Style::spaceXs), 0.0f);
    m_chartBg->setSize(chartW, iconH);

    const float barW = chartW / static_cast<float>(kHistorySamples);
    for (int i = 0; i < kHistorySamples; i++) {
      m_bars[i]->setPosition(static_cast<float>(i) * barW, 0.0f);
      m_bars[i]->setSize(barW, iconH);
    }

    m_label->setPosition(m_chartBg->x() + chartW + static_cast<float>(Style::spaceXs), 0.0f);
    rootNode->setSize(m_label->x() + m_label->width(), iconH);
  } else {
    m_icon->setPosition(0.0f, 0.0f);
    m_label->setPosition(m_icon->width() + static_cast<float>(Style::spaceXs), 0.0f);
    rootNode->setSize(m_label->x() + m_label->width(), iconH);
  }
}

void SysmonWidget::update(Renderer& renderer) {
  if (m_icon == nullptr) {
    return;
  }

  const double normalized = currentNormalized();

  if (m_displayMode == SysmonDisplayMode::Gauge) {
    if (m_gauge != nullptr) {
      // Sub-pixel snap: hide fill below 1px (matches QML NLinearGauge behaviour)
      const float gaugeH = m_gauge->height();
      const float progress = (gaugeH > 0.0f && normalized * gaugeH < 1.0f) ? 0.0f
                                                                             : static_cast<float>(normalized);
      m_gauge->setProgress(progress);
      requestRedraw();
    }
    Widget::update(renderer);
    return;
  }

  if (m_label == nullptr) {
    return;
  }

  auto text = formatValue();
  if (text != m_lastText) {
    m_lastText = std::move(text);
    m_label->setText(m_lastText);
    m_label->measure(renderer);
    requestRedraw();
  }

  if (m_displayMode == SysmonDisplayMode::Graph) {
    pushHistory(normalized);
    updateBars();
    requestRedraw();
  }

  Widget::update(renderer);
}

void SysmonWidget::pushHistory(double normalized) {
  m_history[m_historyHead] = std::clamp(normalized, 0.0, 1.0);
  m_historyHead = (m_historyHead + 1) % kHistorySamples;
}

void SysmonWidget::updateBars() {
  for (int i = 0; i < kHistorySamples; i++) {
    const int idx = (m_historyHead + i) % kHistorySamples; // oldest → leftmost
    m_bars[i]->setProgress(static_cast<float>(m_history[idx]));
  }
}

double SysmonWidget::currentNormalized() const {
  if (m_stat == SysmonStat::DiskPct) {
    struct statvfs sv {};
    if (::statvfs(m_diskPath.c_str(), &sv) == 0 && sv.f_blocks > 0) {
      return static_cast<double>(sv.f_blocks - sv.f_bfree) / static_cast<double>(sv.f_blocks);
    }
    return 0.0;
  }

  if (m_monitor == nullptr) {
    return 0.0;
  }

  const auto stats = m_monitor->latest();

  switch (m_stat) {
  case SysmonStat::CpuUsage:
    return stats.cpuUsagePercent / 100.0;

  case SysmonStat::CpuTemp:
    if (stats.cpuTempC.has_value()) {
      const double temp = *stats.cpuTempC;
      // Expand persistent range
      if (temp < m_tempMin)
        const_cast<SysmonWidget*>(this)->m_tempMin = temp;
      if (temp > m_tempMax)
        const_cast<SysmonWidget*>(this)->m_tempMax = temp;
      const double range = m_tempMax - m_tempMin;
      if (range <= 0.0)
        return 0.5;
      return std::clamp((temp - m_tempMin) / range, 0.0, 1.0);
    }
    return 0.0;

  case SysmonStat::RamUsed:
    if (stats.ramTotalMb > 0) {
      return static_cast<double>(stats.ramUsedMb) / static_cast<double>(stats.ramTotalMb);
    }
    return 0.0;

  case SysmonStat::RamPct:
    return stats.ramUsagePercent / 100.0;

  case SysmonStat::SwapPct:
    if (stats.swapTotalMb > 0) {
      return static_cast<double>(stats.swapUsedMb) / static_cast<double>(stats.swapTotalMb);
    }
    return 0.0;

  case SysmonStat::DiskPct:
    break; // handled above
  }

  return 0.0;
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
