#include "shell/control_center/system_tab.h"

#include "i18n/i18n.h"
#include "render/scene/graph_node.h"
#include "shell/panel/panel_manager.h"
#include "system/distro_info.h"
#include "system/hardware_info.h"
#include "system/system_monitor_service.h"
#include "time/time_format.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"

#include <algorithm>
#include <cmath>
#include <format>
#include <vector>

using namespace control_center;

namespace {

  constexpr float kGraphHeight = 80.0f;
  constexpr float kGraphLineWidth = 0.75f;
  constexpr float kGraphFillOpacity = 0.15f;
  constexpr double kNetMinScaleBps = 10.0 * 1024.0;
  const auto kSampleInterval = std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::seconds(1));

  Flex* makeHeaderRow(Flex& parent, const std::string& title, float scale) {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setGap(Style::spaceSm * scale);

    auto label = std::make_unique<Label>();
    label->setText(title);
    label->setBold(true);
    label->setFontSize(Style::fontSizeTitle * scale);
    label->setColor(roleColor(ColorRole::OnSurface));
    label->setFlexGrow(1.0f);
    row->addChild(std::move(label));

    auto* ptr = row.get();
    parent.addChild(std::move(row));
    return ptr;
  }

  Label* makeValueLabel(Flex& parent, float scale) {
    auto label = std::make_unique<Label>();
    label->setFontSize(Style::fontSizeBody * scale);
    label->setColor(roleColor(ColorRole::OnSurfaceVariant));
    auto* ptr = label.get();
    parent.addChild(std::move(label));
    return ptr;
  }

  Flex* makeIconLabel(Flex& parent, const char* glyphName, float scale) {
    auto group = std::make_unique<Flex>();
    group->setDirection(FlexDirection::Horizontal);
    group->setAlign(FlexAlign::Center);
    group->setGap(Style::spaceXs * scale);

    auto icon = std::make_unique<Glyph>();
    icon->setGlyph(glyphName);
    icon->setGlyphSize(Style::fontSizeBody * scale);
    icon->setColor(roleColor(ColorRole::OnSurfaceVariant));
    group->addChild(std::move(icon));

    auto* ptr = group.get();
    parent.addChild(std::move(group));
    return ptr;
  }

  GraphNode* addGraph(Flex& parent, float scale) {
    auto graph = std::make_unique<GraphNode>();
    graph->setGraphFillOpacity(kGraphFillOpacity);
    graph->setSize(0.0f, kGraphHeight * scale);
    auto* ptr = graph.get();
    parent.addChild(std::move(graph));
    return ptr;
  }

  std::string formatMemoryUsedTotal(const SystemStats& stats) {
    if (stats.ramTotalMb == 0) {
      return memoryTotalLabel();
    }
    const double usedGb = static_cast<double>(stats.ramUsedMb) / 1024.0;
    const double totalGb = static_cast<double>(stats.ramTotalMb) / 1024.0;
    return std::format("{:.1f} / {:.1f} GB", usedGb, totalGb);
  }

  std::string buildSystemInfoText(const SystemStats& stats) {
    const auto uptime = systemUptime();
    const std::string uptimeText =
        uptime.has_value() ? formatDuration(*uptime) : i18n::tr("control-center.system.unknown");
    return i18n::tr("control-center.system.info", "distro", distroLabel(), "compositor", compositorLabel(), "kernel",
                    kernelRelease(), "uptime", uptimeText, "osAge", osAgeLabel(), "board", motherboardLabel(), "cpu",
                    cpuModelName(), "gpu", gpuLabel(), "memory", formatMemoryUsedTotal(stats), "disk",
                    diskRootUsageLabel());
  }

} // namespace

SystemTab::SystemTab(SystemMonitorService* monitor) : m_monitor(monitor) {
  if (m_monitor != nullptr) {
    m_monitor->retainCpuTemp();
  }
}

SystemTab::~SystemTab() {
  if (m_monitor != nullptr) {
    m_monitor->releaseCpuTemp();
  }
}

std::unique_ptr<Flex> SystemTab::create() {
  const float sc = contentScale();

  // Root: horizontal two-column layout (3:2 ratio like weather_tab)
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Horizontal);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * sc);
  m_root = tab.get();

  // --- Left column: 3 graph cards ---
  auto leftCol = std::make_unique<Flex>();
  leftCol->setDirection(FlexDirection::Vertical);
  leftCol->setAlign(FlexAlign::Stretch);
  leftCol->setGap(Style::spaceSm * sc);
  leftCol->setFlexGrow(3.0f);

  // CPU card
  {
    auto card = std::make_unique<Flex>();
    applySectionCardStyle(*card, sc);
    card->setFlexGrow(1.0f);
    m_cpuCard = card.get();

    auto* header = makeHeaderRow(*card, i18n::tr("control-center.system.titles.cpu"), sc);
    m_cpuPctLabel = makeValueLabel(*header, sc);
    m_cpuTempLabel = makeValueLabel(*header, sc);
    m_cpuGraph = addGraph(*card, sc);

    leftCol->addChild(std::move(card));
  }

  // Memory card
  {
    auto card = std::make_unique<Flex>();
    applySectionCardStyle(*card, sc);
    card->setFlexGrow(1.0f);
    m_ramCard = card.get();

    auto* header = makeHeaderRow(*card, i18n::tr("control-center.system.titles.memory"), sc);
    m_ramLabel = makeValueLabel(*header, sc);
    m_ramGraph = addGraph(*card, sc);

    leftCol->addChild(std::move(card));
  }

  // Network card
  {
    auto card = std::make_unique<Flex>();
    applySectionCardStyle(*card, sc);
    card->setFlexGrow(1.0f);
    m_netCard = card.get();

    auto* header = makeHeaderRow(*card, i18n::tr("control-center.system.titles.network"), sc);
    auto* rxGroup = makeIconLabel(*header, "download-speed", sc);
    m_rxLabel = makeValueLabel(*rxGroup, sc);
    auto* txGroup = makeIconLabel(*header, "upload-speed", sc);
    m_txLabel = makeValueLabel(*txGroup, sc);
    m_netGraph = addGraph(*card, sc);

    leftCol->addChild(std::move(card));
  }

  tab->addChild(std::move(leftCol));

  // --- Right column: load average + system info ---
  auto rightCol = std::make_unique<Flex>();
  rightCol->setDirection(FlexDirection::Vertical);
  rightCol->setAlign(FlexAlign::Stretch);
  rightCol->setGap(Style::spaceSm * sc);
  rightCol->setFlexGrow(2.0f);

  // Load Average card
  {
    auto card = std::make_unique<Flex>();
    applySectionCardStyle(*card, sc);
    card->setFlexGrow(0.0f);
    card->setMinHeight(Style::controlHeightLg * 1.9f * sc);
    m_loadCard = card.get();

    addTitle(*card, i18n::tr("control-center.system.titles.load-average"), sc);
    m_loadLabel = makeValueLabel(*card, sc);

    rightCol->addChild(std::move(card));
  }

  // System Info card
  {
    auto card = std::make_unique<Flex>();
    applySectionCardStyle(*card, sc);
    card->setFlexGrow(1.0f);
    card->setMinHeight(Style::controlHeightLg * 6.2f * sc);
    m_infoCard = card.get();

    addTitle(*card, i18n::tr("control-center.system.titles.system-info"), sc);

    auto infoLabel = std::make_unique<Label>();
    infoLabel->setFontSize(Style::fontSizeBody * sc);
    infoLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));

    infoLabel->setText(
        buildSystemInfoText(m_monitor != nullptr && m_monitor->isRunning() ? m_monitor->latest() : SystemStats{}));
    m_infoLabel = infoLabel.get();
    card->addChild(std::move(infoLabel));

    rightCol->addChild(std::move(card));
  }

  tab->addChild(std::move(rightCol));
  return tab;
}

void SystemTab::setActive(bool active) { m_active = active; }

void SystemTab::onClose() {
  m_root = nullptr;
  m_cpuGraph = nullptr;
  m_ramGraph = nullptr;
  m_netGraph = nullptr;
  m_cpuCard = nullptr;
  m_ramCard = nullptr;
  m_netCard = nullptr;
  m_loadCard = nullptr;
  m_infoCard = nullptr;
  m_cpuPctLabel = nullptr;
  m_cpuTempLabel = nullptr;
  m_ramLabel = nullptr;
  m_rxLabel = nullptr;
  m_txLabel = nullptr;
  m_loadLabel = nullptr;
  m_infoLabel = nullptr;
  m_graphInitialized = false;
  m_lastSampleAt = {};
  m_scrollProgress = 1.0f;
  m_tempMin = 30.0;
  m_tempMax = 80.0;
  m_netPeak = 0.0;
}

void SystemTab::onFrameTick(float deltaMs) {
  (void)deltaMs;

  if (!m_active || m_monitor == nullptr || !m_monitor->isRunning()) {
    return;
  }

  const auto latestSampleAt = m_monitor->latest().sampledAt;
  if (latestSampleAt != std::chrono::steady_clock::time_point{} && latestSampleAt != m_lastSampleAt) {
    updateGraphs();
    syncLabels();
    PanelManager::instance().requestLayout();
  }

  m_scrollProgress = scrollProgressForSample(m_lastSampleAt);

  if (m_cpuGraph != nullptr) {
    m_cpuGraph->setScroll1(m_scrollProgress);
    m_cpuGraph->setScroll2(m_scrollProgress);
  }
  if (m_ramGraph != nullptr) {
    m_ramGraph->setScroll1(m_scrollProgress);
  }
  if (m_netGraph != nullptr) {
    m_netGraph->setScroll1(m_scrollProgress);
    m_netGraph->setScroll2(m_scrollProgress);
  }

  PanelManager::instance().requestRedraw();
}

void SystemTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_root == nullptr) {
    return;
  }

  const float sc = contentScale();

  m_root->setSize(contentWidth, bodyHeight);
  m_root->layout(renderer);

  const float cardPadH = Style::spaceMd * sc * 2.0f;
  const float graphH = kGraphHeight * sc;

  auto sizeGraph = [&](GraphNode* g, Flex* card) {
    if (g == nullptr || card == nullptr) {
      return;
    }
    const float graphW = std::max(0.0f, card->width() - cardPadH);
    g->setSize(graphW, graphH);
    g->setLineWidth(kGraphLineWidth * sc);
  };

  sizeGraph(m_cpuGraph, m_cpuCard);
  sizeGraph(m_ramGraph, m_ramCard);
  sizeGraph(m_netGraph, m_netCard);

  const auto innerWidth = [](Flex* card) {
    if (card == nullptr) {
      return 1.0f;
    }
    return std::max(1.0f, card->width() - (card->paddingLeft() + card->paddingRight()));
  };

  if (m_infoLabel != nullptr && m_infoCard != nullptr) {
    m_infoLabel->setMaxWidth(innerWidth(m_infoCard));
  }

  // Apply width constraints in the same frame they are set so System Info
  // reaches its final card height immediately on open.
  m_root->layout(renderer);
}

void SystemTab::doUpdate(Renderer& renderer) {
  if (!m_active || m_monitor == nullptr) {
    return;
  }

  if (m_cpuGraph != nullptr) {
    m_cpuGraph->setLineColor1(resolveThemeColor(roleColor(ColorRole::Primary)));
    m_cpuGraph->setLineColor2(resolveThemeColor(roleColor(ColorRole::Error)));
  }
  if (m_ramGraph != nullptr) {
    m_ramGraph->setLineColor1(resolveThemeColor(roleColor(ColorRole::Secondary)));
  }
  if (m_netGraph != nullptr) {
    m_netGraph->setLineColor1(resolveThemeColor(roleColor(ColorRole::Tertiary)));
    m_netGraph->setLineColor2(resolveThemeColor(roleColor(ColorRole::Secondary)));
  }

  const bool monitorRunning = m_monitor->isRunning();

  if (m_infoLabel != nullptr) {
    m_infoLabel->setText(buildSystemInfoText(monitorRunning ? m_monitor->latest() : SystemStats{}));
    m_infoLabel->measure(renderer);
  }

  if (monitorRunning) {
    updateGraphs();
  } else {
    if (m_cpuGraph != nullptr) {
      m_cpuGraph->setCount1(0.0f);
      m_cpuGraph->setCount2(0.0f);
    }
    if (m_ramGraph != nullptr) {
      m_ramGraph->setCount1(0.0f);
    }
    if (m_netGraph != nullptr) {
      m_netGraph->setCount1(0.0f);
      m_netGraph->setCount2(0.0f);
    }
    m_graphInitialized = false;
    m_lastSampleAt = {};
    m_scrollProgress = 1.0f;
  }
  syncLabels();
}

void SystemTab::updateGraphs() {
  if (m_monitor == nullptr || !m_monitor->isRunning()) {
    return;
  }

  const auto hist = m_monitor->history();
  if (hist.size() < 4) {
    return;
  }

  const auto latestSampleAt = hist.back().sampledAt;
  const bool newData = latestSampleAt != m_lastSampleAt;
  if (!newData && m_graphInitialized) {
    return;
  }

  const int n = static_cast<int>(hist.size());
  const int texSize = n + 1;
  const auto sz = static_cast<std::size_t>(texSize);

  // CPU: usage (primary) + temp (secondary)
  if (m_cpuGraph != nullptr) {
    std::vector<float> usage(sz);
    std::vector<float> temp(sz);
    for (int i = 0; i < n; ++i) {
      const auto& s = hist[static_cast<std::size_t>(i)];
      usage[static_cast<std::size_t>(i)] = static_cast<float>(std::clamp(s.cpuUsagePercent / 100.0, 0.0, 1.0));

      if (s.cpuTempC.has_value()) {
        const double t = *s.cpuTempC;
        if (t < m_tempMin)
          m_tempMin = t;
        if (t > m_tempMax)
          m_tempMax = t;
        const double range = m_tempMax - m_tempMin;
        temp[static_cast<std::size_t>(i)] =
            range > 0.0 ? static_cast<float>(std::clamp((t - m_tempMin) / range, 0.0, 1.0)) : 0.5f;
      }
    }
    usage[n] = std::clamp(usage[n - 1] + (usage[n - 1] - usage[n - 2]) * 0.5f, 0.0f, 1.0f);
    temp[n] = std::clamp(temp[n - 1] + (temp[n - 1] - temp[n - 2]) * 0.5f, 0.0f, 1.0f);
    m_cpuGraph->setData(usage.data(), texSize, temp.data(), texSize);
    m_cpuGraph->setCount1(static_cast<float>(n));
    m_cpuGraph->setCount2(static_cast<float>(n));
  }

  // Memory
  if (m_ramGraph != nullptr) {
    std::vector<float> ram(sz);
    for (int i = 0; i < n; ++i) {
      ram[static_cast<std::size_t>(i)] =
          static_cast<float>(std::clamp(hist[static_cast<std::size_t>(i)].ramUsagePercent / 100.0, 0.0, 1.0));
    }
    ram[n] = std::clamp(ram[n - 1] + (ram[n - 1] - ram[n - 2]) * 0.5f, 0.0f, 1.0f);
    m_ramGraph->setData(ram.data(), texSize, nullptr, 0);
    m_ramGraph->setCount1(static_cast<float>(n));
  }

  // Network
  if (m_netGraph != nullptr) {
    double maxVal = kNetMinScaleBps;
    for (int i = 0; i < n; ++i) {
      const auto& s = hist[static_cast<std::size_t>(i)];
      maxVal = std::max({maxVal, s.netRxBytesPerSec, s.netTxBytesPerSec});
    }
    m_netPeak = maxVal;

    std::vector<float> rx(sz);
    std::vector<float> tx(sz);
    for (int i = 0; i < n; ++i) {
      const auto& s = hist[static_cast<std::size_t>(i)];
      rx[static_cast<std::size_t>(i)] = static_cast<float>(std::clamp(s.netRxBytesPerSec / m_netPeak, 0.0, 1.0));
      tx[static_cast<std::size_t>(i)] = static_cast<float>(std::clamp(s.netTxBytesPerSec / m_netPeak, 0.0, 1.0));
    }
    rx[n] = std::clamp(rx[n - 1] + (rx[n - 1] - rx[n - 2]) * 0.5f, 0.0f, 1.0f);
    tx[n] = std::clamp(tx[n - 1] + (tx[n - 1] - tx[n - 2]) * 0.5f, 0.0f, 1.0f);
    m_netGraph->setData(rx.data(), texSize, tx.data(), texSize);
    m_netGraph->setCount1(static_cast<float>(n));
    m_netGraph->setCount2(static_cast<float>(n));
  }

  m_graphInitialized = true;
  m_lastSampleAt = latestSampleAt;
  m_scrollProgress = scrollProgressForSample(m_lastSampleAt);

  if (m_cpuGraph != nullptr) {
    m_cpuGraph->setScroll1(m_scrollProgress);
    m_cpuGraph->setScroll2(m_scrollProgress);
  }
  if (m_ramGraph != nullptr) {
    m_ramGraph->setScroll1(m_scrollProgress);
  }
  if (m_netGraph != nullptr) {
    m_netGraph->setScroll1(m_scrollProgress);
    m_netGraph->setScroll2(m_scrollProgress);
  }

  if (m_scrollProgress < 1.0f) {
    PanelManager::instance().requestRedraw();
  }
}

void SystemTab::syncLabels() {
  if (m_monitor == nullptr || !m_monitor->isRunning()) {
    if (m_cpuPctLabel != nullptr) {
      m_cpuPctLabel->setText("--");
    }
    if (m_cpuTempLabel != nullptr) {
      m_cpuTempLabel->setText("--");
    }
    if (m_ramLabel != nullptr) {
      m_ramLabel->setText("--");
    }
    if (m_rxLabel != nullptr) {
      m_rxLabel->setText("--");
    }
    if (m_txLabel != nullptr) {
      m_txLabel->setText("--");
    }
    if (m_loadLabel != nullptr) {
      m_loadLabel->setText("--");
    }
    return;
  }

  const auto stats = m_monitor->latest();

  if (m_cpuPctLabel != nullptr) {
    m_cpuPctLabel->setText(std::format("{:.0f}%", stats.cpuUsagePercent));
  }
  if (m_cpuTempLabel != nullptr) {
    if (stats.cpuTempC.has_value()) {
      m_cpuTempLabel->setText(std::format("{:.0f}°C", *stats.cpuTempC));
    } else {
      m_cpuTempLabel->setText("--");
    }
  }
  if (m_ramLabel != nullptr) {
    const double usedGb = static_cast<double>(stats.ramUsedMb) / 1024.0;
    const double totalGb = static_cast<double>(stats.ramTotalMb) / 1024.0;
    m_ramLabel->setText(std::format("{:.1f} / {:.1f} GB · {:.0f}%", usedGb, totalGb, stats.ramUsagePercent));
  }
  if (m_rxLabel != nullptr) {
    m_rxLabel->setText(formatBytesPerSec(stats.netRxBytesPerSec));
  }
  if (m_txLabel != nullptr) {
    m_txLabel->setText(formatBytesPerSec(stats.netTxBytesPerSec));
  }
  if (m_loadLabel != nullptr) {
    m_loadLabel->setText(std::format("{:.2f}  /  {:.2f}  /  {:.2f}", stats.loadAvg1, stats.loadAvg5, stats.loadAvg15));
  }
}

float SystemTab::scrollProgressForSample(std::chrono::steady_clock::time_point sampledAt) {
  if (sampledAt == std::chrono::steady_clock::time_point{}) {
    return 1.0f;
  }
  const auto elapsed = std::chrono::steady_clock::now() - sampledAt;
  const auto clamped = std::clamp(elapsed, std::chrono::steady_clock::duration::zero(), kSampleInterval);
  return std::chrono::duration<float>(clamped).count() / std::chrono::duration<float>(kSampleInterval).count();
}

std::string SystemTab::formatBytesPerSec(double bytesPerSec) {
  if (bytesPerSec >= 1024.0 * 1024.0 * 1024.0) {
    return std::format("{:.1f} GB/s", bytesPerSec / (1024.0 * 1024.0 * 1024.0));
  }
  if (bytesPerSec >= 1024.0 * 1024.0) {
    return std::format("{:.1f} MB/s", bytesPerSec / (1024.0 * 1024.0));
  }
  if (bytesPerSec >= 1024.0) {
    return std::format("{:.1f} KB/s", bytesPerSec / 1024.0);
  }
  return std::format("{:.0f} B/s", bytesPerSec);
}
