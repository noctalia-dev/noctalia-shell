#include "shell/control_center/screen_time_tab.h"

#include "config/config_service.h"
#include "i18n/i18n.h"
#include "render/core/color.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "shell/tooltip/tooltip_content.h"
#include "system/app_identity.h"
#include "system/desktop_entry.h"
#include "system/icon_resolver.h"
#include "system/internal_app_metadata.h"
#include "system/screen_time_service.h"
#include "time/time_format.h"
#include "ui/controls/box.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/segmented.h"
#include "ui/controls/toggle.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

using namespace control_center;

namespace {

  constexpr float kChartHeight = 132.0f;
  constexpr float kBarGap = 2.0f;
  constexpr float kAppIconSize = 28.0f;
  constexpr float kUsageBarHeight = 4.0f;
  constexpr float kLegendSwatch = 6.0f;
  constexpr float kUsageDurationFontScale = 0.85f;

  IconResolver g_iconResolver;

  [[nodiscard]] std::string snapshotKey(int rangeDays, const ScreenTimeSnapshot& snapshot) {
    std::string key = std::to_string(rangeDays) + '|' + std::to_string(snapshot.total.count());
    key += snapshot.hourlyBuckets ? "|h" : "|d";
    for (const auto& bucket : snapshot.buckets) {
      key += ':';
      key += std::to_string(bucket.count());
    }
    for (const auto& series : snapshot.chartSeries) {
      key += '|';
      key += series.appKey;
      key += ':';
      key += std::to_string(series.total.count());
      for (const auto& bucket : series.buckets) {
        key += ':';
        key += std::to_string(bucket.count());
      }
    }
    for (const auto& app : snapshot.apps) {
      key += '|';
      key += app.appKey;
      key += '@';
      key += std::to_string(app.total.count());
    }
    return key;
  }

  Label* makeSectionHeader(Flex& parent, const std::string& text, float scale) {
    auto label = std::make_unique<Label>();
    label->setText(text);
    label->setBold(true);
    label->setFontSize(Style::fontSizeCaption * scale);
    label->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    auto* ptr = label.get();
    parent.addChild(std::move(label));
    return ptr;
  }

  [[nodiscard]] float usageDurationFontSize(float scale) {
    return Style::fontSizeMini * scale * kUsageDurationFontScale;
  }

  [[nodiscard]] std::vector<TooltipRow> appUsageTooltip(const std::string& displayName, std::chrono::seconds duration) {
    return {{displayName, formatDuration(duration)}};
  }

  [[nodiscard]] std::uint32_t hashAppKey(std::string_view appKey) {
    std::uint32_t hash = 2166136261u;
    for (const unsigned char byte : appKey) {
      hash ^= byte;
      hash *= 16777619u;
    }
    return hash;
  }

  [[nodiscard]] Color appSeriesColor(std::string_view appKey) {
    const Color primary = colorForRole(ColorRole::Primary);
    float baseH = 0.0f;
    float baseS = 0.0f;
    float baseV = 0.0f;
    rgbToHsv(primary, baseH, baseS, baseV);

    const float hashT = static_cast<float>(hashAppKey(appKey) % 1000u) / 1000.0f;
    const float hue = baseH + hashT * 0.72f;
    const float sat = std::clamp(baseS * (0.82f + hashT * 0.22f), 0.38f, 0.82f);
    const float val = std::clamp(baseV * (0.86f + (1.0f - hashT) * 0.14f), 0.52f, 0.90f);
    return hsv(hue, sat, val);
  }

  void assignSnapshotColors(ScreenTimeSnapshot& snapshot) {
    for (auto& app : snapshot.apps) {
      app.chartColor = fixedColorSpec(appSeriesColor(app.appKey));
    }
    for (auto& series : snapshot.chartSeries) {
      series.chartColor = fixedColorSpec(appSeriesColor(series.appKey));
    }
  }

} // namespace

ScreenTimeTab::ScreenTimeTab(ScreenTimeService* screenTime, ConfigService* config)
    : m_screenTime(screenTime), m_config(config) {}

std::unique_ptr<Flex> ScreenTimeTab::create() {
  const float scale = contentScale();

  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Stretch);
  m_root = tab.get();

  auto scroll = std::make_unique<ScrollView>();
  scroll->setFlexGrow(1.0f);
  scroll->setScrollbarVisible(true);
  scroll->clearFill();
  scroll->clearBorder();

  auto* content = scroll->content();
  content->setDirection(FlexDirection::Vertical);
  content->setAlign(FlexAlign::Stretch);
  content->setGap(Style::spaceLg * scale);

  auto usageCard = std::make_unique<Flex>();
  applySectionCardStyle(*usageCard, scale, panelCardOpacity());
  usageCard->setDirection(FlexDirection::Vertical);
  usageCard->setGap(Style::spaceMd * scale);
  m_usageCard = usageCard.get();

  auto enableRow = std::make_unique<Flex>();
  enableRow->setDirection(FlexDirection::Horizontal);
  enableRow->setAlign(FlexAlign::Center);
  enableRow->setGap(Style::spaceSm * scale);
  enableRow->setMinHeight(Style::controlHeightSm * scale);

  auto enableLabel = std::make_unique<Label>();
  enableLabel->setText(i18n::tr("control-center.screen-time.enabled"));
  enableLabel->setFontSize(Style::fontSizeBody * scale);
  enableLabel->setColor(colorSpecFromRole(ColorRole::OnSurface));
  enableLabel->setFlexGrow(1.0f);
  enableRow->addChild(std::move(enableLabel));

  auto enabledToggle = std::make_unique<Toggle>();
  enabledToggle->setToggleSize(ToggleSize::Small);
  enabledToggle->setScale(scale);
  enabledToggle->setCheckedImmediate(m_screenTime != nullptr && m_screenTime->enabled());
  enabledToggle->setOnChange([this](bool checked) {
    if (m_config != nullptr) {
      (void)m_config->setOverride({"shell", "screen_time_enabled"}, checked);
    } else if (m_screenTime != nullptr) {
      m_screenTime->setEnabled(checked);
    }
    syncEnabledUi();
    m_lastSnapshotKey.clear();
    PanelManager::instance().refresh();
  });
  m_enabledToggle = enabledToggle.get();
  enableRow->addChild(std::move(enabledToggle));
  usageCard->addChild(std::move(enableRow));

  auto disabled = std::make_unique<Label>();
  disabled->setFontSize(Style::fontSizeBody * scale);
  disabled->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  disabled->setText(i18n::tr("control-center.screen-time.disabled"));
  disabled->setVisible(false);
  m_disabledLabel = disabled.get();
  usageCard->addChild(std::move(disabled));

  auto rangePicker = std::make_unique<Segmented>();
  rangePicker->setScale(scale);
  rangePicker->setFontSize(Style::fontSizeCaption * scale);
  rangePicker->addOption(i18n::tr("control-center.screen-time.range.today"));
  rangePicker->addOption(i18n::tr("control-center.screen-time.range.3-days"));
  rangePicker->addOption(i18n::tr("control-center.screen-time.range.14-days"));
  rangePicker->setEqualSegmentWidths(true);
  m_rangeDays = 1;
  rangePicker->setSelectedIndex(0);
  rangePicker->setOnChange([this](std::size_t idx) {
    static constexpr int kRanges[] = {1, 3, 14};
    m_rangeDays = kRanges[std::min(idx, std::size_t{2})];
    m_lastSnapshotKey.clear();
    PanelManager::instance().refresh();
  });
  m_rangePicker = rangePicker.get();
  usageCard->addChild(std::move(rangePicker));

  auto total = std::make_unique<Label>();
  total->setBold(true);
  total->setFontSize(Style::fontSizeHeader * 1.6f * scale);
  total->setColor(colorSpecFromRole(ColorRole::OnSurface));
  m_totalLabel = total.get();
  usageCard->addChild(std::move(total));

  auto chartPlotRow = std::make_unique<Flex>();
  chartPlotRow->setDirection(FlexDirection::Horizontal);
  chartPlotRow->setAlign(FlexAlign::Stretch);
  chartPlotRow->setJustify(FlexJustify::Start);
  chartPlotRow->setGap(kBarGap * scale);
  chartPlotRow->setMinHeight(kChartHeight * scale);
  chartPlotRow->setMaxHeight(kChartHeight * scale);
  chartPlotRow->setFillWidth(true);
  m_chartPlotRow = chartPlotRow.get();

  auto chartLabelRow = std::make_unique<Flex>();
  chartLabelRow->setDirection(FlexDirection::Horizontal);
  chartLabelRow->setAlign(FlexAlign::Center);
  chartLabelRow->setJustify(FlexJustify::Start);
  chartLabelRow->setGap(kBarGap * scale);
  chartLabelRow->setFillWidth(true);
  m_chartLabelRow = chartLabelRow.get();

  for (std::size_t bucket = 0; bucket < m_bucketColumns.size(); ++bucket) {
    auto plotColumn = std::make_unique<Flex>();
    plotColumn->setDirection(FlexDirection::Vertical);
    plotColumn->setAlign(FlexAlign::Stretch);
    plotColumn->setJustify(FlexJustify::End);
    plotColumn->setFlexGrow(1.0f);
    plotColumn->setVisible(false);
    m_bucketColumns[bucket].plotColumn = plotColumn.get();

    auto plotSizer = std::make_unique<Box>();
    plotSizer->setFill(clearColorSpec());
    plotSizer->setSize(1.0f, kChartHeight * scale);
    plotColumn->addChild(std::move(plotSizer));

    auto track = std::make_unique<Box>();
    track->setFill(colorSpecFromRole(ColorRole::SurfaceVariant));
    track->setParticipatesInLayout(false);
    track->setZIndex(-1);
    m_bucketColumns[bucket].track = track.get();
    plotColumn->addChild(std::move(track));

    for (std::size_t series = 0; series < kMaxChartSeries; ++series) {
      auto hitArea = std::make_unique<InputArea>();
      hitArea->setParticipatesInLayout(false);
      hitArea->setVisible(false);

      auto segment = std::make_unique<Box>();
      segment->setRadius(0.0f);
      segment->setParticipatesInLayout(false);
      segment->setVisible(false);
      m_bucketColumns[bucket].segments[series] = static_cast<Box*>(hitArea->addChild(std::move(segment)));
      m_bucketColumns[bucket].segmentHits[series] = hitArea.get();
      plotColumn->addChild(std::move(hitArea));
    }

    chartPlotRow->addChild(std::move(plotColumn));

    auto labelCell = std::make_unique<Flex>();
    labelCell->setDirection(FlexDirection::Horizontal);
    labelCell->setAlign(FlexAlign::Center);
    labelCell->setJustify(FlexJustify::Center);
    labelCell->setFlexGrow(1.0f);
    labelCell->setVisible(false);
    m_bucketColumns[bucket].labelCell = labelCell.get();

    auto label = std::make_unique<Label>();
    label->setFontSize(Style::fontSizeMini * scale);
    label->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    label->setVisible(false);
    m_bucketColumns[bucket].label = label.get();
    labelCell->addChild(std::move(label));

    chartLabelRow->addChild(std::move(labelCell));
  }
  usageCard->addChild(std::move(chartPlotRow));
  usageCard->addChild(std::move(chartLabelRow));
  content->addChild(std::move(usageCard));

  auto mostUsedSection = std::make_unique<Flex>();
  mostUsedSection->setDirection(FlexDirection::Vertical);
  mostUsedSection->setAlign(FlexAlign::Stretch);
  mostUsedSection->setGap(Style::spaceSm * scale);
  m_mostUsedSection = mostUsedSection.get();

  makeSectionHeader(*mostUsedSection, i18n::tr("control-center.screen-time.most-used"), scale);

  auto appsGrid = std::make_unique<Flex>();
  appsGrid->setDirection(FlexDirection::Vertical);
  appsGrid->setAlign(FlexAlign::Stretch);
  appsGrid->setGap(Style::spaceSm * scale);
  appsGrid->setFillWidth(true);
  m_appsGrid = appsGrid.get();

  for (std::size_t gridRow = 0; gridRow < m_appGridRows.size(); ++gridRow) {
    auto gridRowFlex = std::make_unique<Flex>();
    gridRowFlex->setDirection(FlexDirection::Horizontal);
    gridRowFlex->setAlign(FlexAlign::Start);
    gridRowFlex->setGap(Style::spaceSm * scale);
    gridRowFlex->setFillWidth(true);
    m_appGridRows[gridRow] = gridRowFlex.get();

    for (std::size_t col = 0; col < kAppsPerRow; ++col) {
      const std::size_t i = gridRow * kAppsPerRow + col;
      if (i >= m_appRows.size()) {
        break;
      }

      auto cell = std::make_unique<Flex>();
      cell->setDirection(FlexDirection::Vertical);
      cell->setAlign(FlexAlign::Stretch);
      cell->setFlexGrow(1.0f);
      cell->setFillWidth(true);
      cell->setVisible(false);
      m_appRows[i].cell = cell.get();

      auto row = std::make_unique<Flex>();
      row->setDirection(FlexDirection::Horizontal);
      row->setAlign(FlexAlign::Start);
      row->setGap(Style::spaceSm * scale);
      row->setVisible(false);
      m_appRows[i].row = row.get();

      auto chartSwatch = std::make_unique<Box>();
      chartSwatch->setSize(kLegendSwatch * scale, kLegendSwatch * scale);
      chartSwatch->setRadius(kLegendSwatch * scale * 0.5f);
      chartSwatch->setVisible(false);
      m_appRows[i].chartSwatch = chartSwatch.get();
      row->addChild(std::move(chartSwatch));

      auto iconSlot = std::make_unique<Flex>();
      iconSlot->setDirection(FlexDirection::Horizontal);
      iconSlot->setAlign(FlexAlign::Center);
      iconSlot->setJustify(FlexJustify::Center);
      iconSlot->setSize(kAppIconSize * scale, kAppIconSize * scale);
      m_appRows[i].iconSlot = iconSlot.get();

      auto icon = std::make_unique<Image>();
      icon->setRadius(Style::scaledRadiusMd(scale));
      icon->setFit(ImageFit::Cover);
      icon->setSize(kAppIconSize * scale, kAppIconSize * scale);
      icon->setParticipatesInLayout(false);
      icon->setVisible(false);
      m_appRows[i].icon = icon.get();
      iconSlot->addChild(std::move(icon));

      auto iconFallback = std::make_unique<Glyph>();
      iconFallback->setGlyph("app-window");
      iconFallback->setGlyphSize(kAppIconSize * 0.55f * scale);
      iconFallback->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      iconFallback->setParticipatesInLayout(false);
      m_appRows[i].iconFallback = iconFallback.get();
      iconSlot->addChild(std::move(iconFallback));

      row->addChild(std::move(iconSlot));

      auto body = std::make_unique<Flex>();
      body->setDirection(FlexDirection::Vertical);
      body->setAlign(FlexAlign::Stretch);
      body->setGap(Style::spaceXs * scale);
      body->setFlexGrow(1.0f);

      auto headerRow = std::make_unique<Flex>();
      headerRow->setDirection(FlexDirection::Horizontal);
      headerRow->setAlign(FlexAlign::Center);
      headerRow->setGap(Style::spaceSm * scale);

      auto name = std::make_unique<Label>();
      name->setFontSize(Style::fontSizeBody * scale);
      name->setColor(colorSpecFromRole(ColorRole::OnSurface));
      name->setMaxLines(1);
      name->setFlexGrow(1.0f);
      m_appRows[i].name = name.get();
      headerRow->addChild(std::move(name));

      auto duration = std::make_unique<Label>();
      duration->setFontSize(usageDurationFontSize(scale));
      duration->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      m_appRows[i].duration = duration.get();
      headerRow->addChild(std::move(duration));

      body->addChild(std::move(headerRow));

      auto barHost = std::make_unique<Flex>();
      barHost->setDirection(FlexDirection::Horizontal);
      barHost->setAlign(FlexAlign::Center);
      barHost->setMinHeight(kUsageBarHeight * scale);
      m_appRows[i].barHost = barHost.get();

      auto trackBg = std::make_unique<Box>();
      trackBg->setFill(colorSpecFromRole(ColorRole::SurfaceVariant));
      trackBg->setRadius(Style::scaledRadiusSm(scale));
      trackBg->setParticipatesInLayout(false);
      trackBg->setZIndex(-1);
      m_appRows[i].barTrack = trackBg.get();
      barHost->addChild(std::move(trackBg));

      auto fill = std::make_unique<Box>();
      fill->setSize(0.0f, kUsageBarHeight * scale);
      fill->setRadius(Style::scaledRadiusSm(scale));
      m_appRows[i].barFill = fill.get();
      barHost->addChild(std::move(fill));

      body->addChild(std::move(barHost));
      row->addChild(std::move(body));
      cell->addChild(std::move(row));
      gridRowFlex->addChild(std::move(cell));
    }

    appsGrid->addChild(std::move(gridRowFlex));
  }

  auto empty = std::make_unique<Label>();
  empty->setFontSize(Style::fontSizeBody * scale);
  empty->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  empty->setText(i18n::tr("control-center.screen-time.empty"));
  m_emptyLabel = empty.get();
  appsGrid->addChild(std::move(empty));

  mostUsedSection->addChild(std::move(appsGrid));
  content->addChild(std::move(mostUsedSection));
  scroll->setFlexGrow(1.0f);
  tab->addChild(std::move(scroll));
  syncEnabledUi();
  m_paletteConn = paletteChanged().connect([this] {
    m_lastSnapshotKey.clear();
    PanelManager::instance().requestUpdateOnly();
  });
  return tab;
}

void ScreenTimeTab::onClose() {
  m_root = nullptr;
  m_usageCard = nullptr;
  m_enabledToggle = nullptr;
  m_disabledLabel = nullptr;
  m_rangePicker = nullptr;
  m_chartPlotRow = nullptr;
  m_chartLabelRow = nullptr;
  m_mostUsedSection = nullptr;
  m_appsGrid = nullptr;
  m_totalLabel = nullptr;
  m_emptyLabel = nullptr;
  m_bucketColumns = {};
  m_appRows = {};
  m_appGridRows = {};
  m_lastSnapshotKey.clear();
  m_rangeDays = 1;
  m_paletteConn = {};
}

void ScreenTimeTab::setActive(bool active) {
  m_active = active;
  if (m_active) {
    m_lastSnapshotKey.clear();
    if (m_enabledToggle != nullptr && m_screenTime != nullptr) {
      m_enabledToggle->setChecked(m_screenTime->enabled());
    }
    syncEnabledUi();
  }
}

void ScreenTimeTab::syncEnabledUi() {
  const bool enabled = m_screenTime != nullptr && m_screenTime->enabled();
  if (m_enabledToggle != nullptr) {
    m_enabledToggle->setChecked(enabled);
  }
  if (m_disabledLabel != nullptr) {
    m_disabledLabel->setVisible(!enabled);
  }
  const bool showUsage = enabled;
  if (m_rangePicker != nullptr) {
    m_rangePicker->setVisible(showUsage);
  }
  if (m_totalLabel != nullptr) {
    m_totalLabel->setVisible(showUsage);
  }
  if (m_chartPlotRow != nullptr) {
    m_chartPlotRow->setVisible(showUsage);
  }
  if (m_chartLabelRow != nullptr) {
    m_chartLabelRow->setVisible(showUsage);
  }
  if (m_mostUsedSection != nullptr) {
    m_mostUsedSection->setVisible(showUsage);
  }
}

void ScreenTimeTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_root == nullptr) {
    return;
  }
  m_root->setSize(contentWidth, bodyHeight);
  m_root->layout(renderer);
  syncContent(renderer);
  layoutChart(renderer);
  layoutAppRows(renderer);
}

void ScreenTimeTab::doUpdate(Renderer& renderer) {
  if (!m_active) {
    return;
  }
  syncContent(renderer);
  layoutChart(renderer);
  layoutAppRows(renderer);
}

void ScreenTimeTab::syncContent(Renderer& renderer) {
  if (m_screenTime == nullptr || m_totalLabel == nullptr || m_chartPlotRow == nullptr) {
    return;
  }

  syncEnabledUi();
  if (!m_screenTime->enabled()) {
    m_lastSnapshotKey.clear();
    return;
  }

  ScreenTimeSnapshot snapshot = m_screenTime->snapshot(m_rangeDays);
  assignSnapshotColors(snapshot);
  const std::string key = snapshotKey(m_rangeDays, snapshot);
  if (key == m_lastSnapshotKey) {
    return;
  }
  m_lastSnapshotKey = key;

  m_totalLabel->setText(formatDuration(snapshot.total));

  const std::size_t bucketCount = snapshot.buckets.size();
  // Bar scale uses chart series totals only, not full bucket usage.
  std::int64_t peakChartBucketSeconds = 0;
  for (std::size_t bucket = 0; bucket < bucketCount; ++bucket) {
    std::int64_t chartBucketTotal = 0;
    for (const auto& series : snapshot.chartSeries) {
      if (bucket < series.buckets.size()) {
        chartBucketTotal += series.buckets[bucket].count();
      }
    }
    peakChartBucketSeconds = std::max(peakChartBucketSeconds, chartBucketTotal);
  }

  const float scale = contentScale();
  const float chartHeight = kChartHeight * scale;
  const float durationFont = usageDurationFontSize(scale);

  for (std::size_t bucket = 0; bucket < m_bucketColumns.size(); ++bucket) {
    auto& columnWidgets = m_bucketColumns[bucket];
    const bool bucketActive = bucket < bucketCount;
    if (columnWidgets.plotColumn != nullptr) {
      columnWidgets.plotColumn->setVisible(bucketActive);
      if (bucketActive) {
        columnWidgets.plotColumn->setFlexGrow(1.0f);
      }
    }
    if (columnWidgets.labelCell != nullptr) {
      columnWidgets.labelCell->setVisible(bucketActive);
      if (bucketActive) {
        columnWidgets.labelCell->setFlexGrow(1.0f);
      }
    }

    if (columnWidgets.label != nullptr) {
      if (!bucketActive) {
        columnWidgets.label->setVisible(false);
      } else if (snapshot.hourlyBuckets) {
        const int hour = static_cast<int>(bucket);
        if (hour == 0) {
          columnWidgets.label->setText(i18n::tr("control-center.screen-time.hour-0"));
          columnWidgets.label->setVisible(true);
        } else if (hour == 6) {
          columnWidgets.label->setText(i18n::tr("control-center.screen-time.hour-6"));
          columnWidgets.label->setVisible(true);
        } else if (hour == 12) {
          columnWidgets.label->setText(i18n::tr("control-center.screen-time.hour-12"));
          columnWidgets.label->setVisible(true);
        } else if (hour == 18) {
          columnWidgets.label->setText(i18n::tr("control-center.screen-time.hour-18"));
          columnWidgets.label->setVisible(true);
        } else {
          columnWidgets.label->setVisible(false);
        }
      } else if (bucket < snapshot.bucketLabels.size()) {
        columnWidgets.label->setText(snapshot.bucketLabels[bucket]);
        columnWidgets.label->setVisible(true);
      } else {
        columnWidgets.label->setVisible(false);
      }
      columnWidgets.label->setFontSize(Style::fontSizeMini * scale);
    }

    if (!bucketActive || columnWidgets.plotColumn == nullptr) {
      for (std::size_t seriesIdx = 0; seriesIdx < kMaxChartSeries; ++seriesIdx) {
        if (columnWidgets.segmentHits[seriesIdx] != nullptr) {
          columnWidgets.segmentHits[seriesIdx]->setVisible(false);
          columnWidgets.segmentHits[seriesIdx]->clearTooltip();
        }
        if (columnWidgets.segments[seriesIdx] != nullptr) {
          columnWidgets.segments[seriesIdx]->setVisible(false);
        }
        columnWidgets.segmentHeights[seriesIdx] = 0.0f;
      }
      continue;
    }

    std::chrono::seconds bucketChartTotal{0};
    for (const auto& series : snapshot.chartSeries) {
      if (bucket < series.buckets.size()) {
        bucketChartTotal += series.buckets[bucket];
      }
    }
    const float columnHeight = peakChartBucketSeconds > 0 ? chartHeight * static_cast<float>(bucketChartTotal.count()) /
                                                                static_cast<float>(peakChartBucketSeconds)
                                                          : 0.0f;

    for (std::size_t seriesIdx = 0; seriesIdx < kMaxChartSeries; ++seriesIdx) {
      Box* segment = columnWidgets.segments[seriesIdx];
      InputArea* hitArea = columnWidgets.segmentHits[seriesIdx];
      if (segment == nullptr) {
        continue;
      }
      if (seriesIdx >= snapshot.chartSeries.size() || bucketChartTotal.count() <= 0) {
        if (hitArea != nullptr) {
          hitArea->setVisible(false);
          hitArea->clearTooltip();
        }
        segment->setVisible(false);
        columnWidgets.segmentHeights[seriesIdx] = 0.0f;
        continue;
      }

      const auto& series = snapshot.chartSeries[seriesIdx];
      const auto seriesSeconds = bucket < series.buckets.size() ? series.buckets[bucket] : std::chrono::seconds{0};
      if (seriesSeconds.count() <= 0) {
        if (hitArea != nullptr) {
          hitArea->setVisible(false);
          hitArea->clearTooltip();
        }
        segment->setVisible(false);
        columnWidgets.segmentHeights[seriesIdx] = 0.0f;
        continue;
      }

      const float segmentHeight =
          columnHeight * static_cast<float>(seriesSeconds.count()) / static_cast<float>(bucketChartTotal.count());
      segment->setFill(series.chartColor);
      segment->setVisible(true);
      columnWidgets.segmentHeights[seriesIdx] = std::max(2.0f, segmentHeight);
      if (hitArea != nullptr) {
        hitArea->setVisible(true);
        hitArea->setTooltip(appUsageTooltip(series.displayName, seriesSeconds));
      }
    }
  }

  const bool hasApps = !snapshot.apps.empty();
  if (m_emptyLabel != nullptr) {
    m_emptyLabel->setVisible(!hasApps);
  }

  const std::chrono::seconds topTotal = hasApps ? snapshot.apps.front().total : std::chrono::seconds{0};

  for (std::size_t i = 0; i < m_appRows.size(); ++i) {
    auto& widgets = m_appRows[i];
    if (widgets.row == nullptr) {
      continue;
    }
    if (i >= snapshot.apps.size()) {
      if (widgets.cell != nullptr) {
        widgets.cell->setVisible(false);
      }
      widgets.row->setVisible(false);
      if (widgets.duration != nullptr) {
        widgets.duration->clearTooltip();
      }
      continue;
    }

    const auto& app = snapshot.apps[i];
    if (widgets.cell != nullptr) {
      widgets.cell->setVisible(true);
    }
    widgets.row->setVisible(true);
    if (widgets.name != nullptr) {
      widgets.name->setText(app.displayName);
    }
    if (widgets.duration != nullptr) {
      widgets.duration->setFontSize(durationFont);
      widgets.duration->setText(formatDuration(app.total));
      widgets.duration->setTooltip(appUsageTooltip(app.displayName, app.total));
    }
    if (widgets.chartSwatch != nullptr) {
      widgets.chartSwatch->setVisible(true);
      widgets.chartSwatch->setFill(app.chartColor);
    }
    if (widgets.barFill != nullptr) {
      widgets.barFill->setFill(app.chartColor);
      widgets.barFillRatio =
          topTotal.count() > 0 ? static_cast<float>(app.total.count()) / static_cast<float>(topTotal.count()) : 0.0f;
    }

    updateIconForRow(renderer, widgets, app.appKey, scale);
  }

  for (std::size_t gridRow = 0; gridRow < m_appGridRows.size(); ++gridRow) {
    Flex* gridRowFlex = m_appGridRows[gridRow];
    if (gridRowFlex == nullptr) {
      continue;
    }
    bool rowVisible = false;
    for (std::size_t col = 0; col < kAppsPerRow; ++col) {
      const std::size_t i = gridRow * kAppsPerRow + col;
      if (i < m_appRows.size() && m_appRows[i].cell != nullptr && m_appRows[i].cell->visible()) {
        rowVisible = true;
        break;
      }
    }
    gridRowFlex->setVisible(rowVisible);
  }
}

void ScreenTimeTab::layoutChart(Renderer& renderer) {
  if (m_chartPlotRow == nullptr || !m_chartPlotRow->visible()) {
    return;
  }
  const float scale = contentScale();
  const float chartHeight = kChartHeight * scale;
  const float barGap = kBarGap * scale;

  std::size_t activeBuckets = 0;
  for (const auto& columnWidgets : m_bucketColumns) {
    if (columnWidgets.plotColumn != nullptr && columnWidgets.plotColumn->visible()) {
      activeBuckets++;
    }
  }

  float rowWidth = m_chartPlotRow->width();
  if (rowWidth <= 0.0f && m_usageCard != nullptr) {
    rowWidth = m_usageCard->width();
  }
  const float columnWidth =
      activeBuckets > 0 && rowWidth > 0.0f
          ? (rowWidth - barGap * static_cast<float>(activeBuckets - 1)) / static_cast<float>(activeBuckets)
          : 0.0f;

  if (columnWidth > 0.0f) {
    for (auto& columnWidgets : m_bucketColumns) {
      if (columnWidgets.plotColumn != nullptr && columnWidgets.plotColumn->visible()) {
        columnWidgets.plotColumn->setMinWidth(columnWidth);
        columnWidgets.plotColumn->setSize(columnWidth, chartHeight);
      }
      if (columnWidgets.labelCell != nullptr && columnWidgets.labelCell->visible()) {
        columnWidgets.labelCell->setMinWidth(columnWidth);
      }
    }
  }

  m_chartPlotRow->layout(renderer);
  if (m_chartLabelRow != nullptr) {
    m_chartLabelRow->layout(renderer);
  }
  for (auto& columnWidgets : m_bucketColumns) {
    if (columnWidgets.plotColumn == nullptr || !columnWidgets.plotColumn->visible()) {
      continue;
    }
    columnWidgets.plotColumn->layout(renderer);
    const float resolvedColumnWidth =
        columnWidth > 0.0f ? columnWidth : std::max(1.0f, columnWidgets.plotColumn->width());
    const float plotHeight = std::max(chartHeight, columnWidgets.plotColumn->height());

    if (columnWidgets.track != nullptr) {
      columnWidgets.track->setVisible(true);
      columnWidgets.track->setPosition(0.0f, plotHeight - chartHeight);
      columnWidgets.track->setSize(resolvedColumnWidth, chartHeight);
    }

    float stackTop = plotHeight;
    for (std::size_t seriesIdx = 0; seriesIdx < kMaxChartSeries; ++seriesIdx) {
      Box* segment = columnWidgets.segments[seriesIdx];
      InputArea* hitArea = columnWidgets.segmentHits[seriesIdx];
      const float segmentHeight = columnWidgets.segmentHeights[seriesIdx];
      if (segment == nullptr || !segment->visible() || segmentHeight <= 0.0f) {
        continue;
      }
      stackTop -= segmentHeight;
      if (hitArea != nullptr) {
        hitArea->setPosition(0.0f, stackTop);
        hitArea->setSize(resolvedColumnWidth, segmentHeight);
      }
      segment->setPosition(0.0f, 0.0f);
      segment->setSize(resolvedColumnWidth, segmentHeight);
    }
  }
}

void ScreenTimeTab::layoutAppRows(Renderer& renderer) {
  const float scale = contentScale();
  const float iconSize = kAppIconSize * scale;
  for (auto& widgets : m_appRows) {
    if (widgets.cell != nullptr) {
      widgets.cell->layout(renderer);
    }
    if (widgets.row == nullptr || !widgets.row->visible()) {
      continue;
    }
    if (widgets.iconSlot != nullptr) {
      widgets.iconSlot->setSize(iconSize, iconSize);
      if (widgets.icon != nullptr) {
        widgets.icon->setPosition(0.0f, 0.0f);
        widgets.icon->setSize(iconSize, iconSize);
      }
      if (widgets.iconFallback != nullptr) {
        widgets.iconFallback->measure(renderer);
        const float glyphSize = kAppIconSize * 0.55f * scale;
        widgets.iconFallback->setPosition((iconSize - glyphSize) * 0.5f, (iconSize - glyphSize) * 0.5f);
      }
    }
    if (widgets.row != nullptr) {
      widgets.row->layout(renderer);
    }
    if (widgets.barHost != nullptr) {
      widgets.barHost->layout(renderer);
      const float barHeight = kUsageBarHeight * scale;
      const float trackWidth = std::max(0.0f, widgets.barHost->width());
      if (widgets.barTrack != nullptr) {
        widgets.barTrack->setSize(trackWidth, barHeight);
      }
      if (widgets.barFill != nullptr && widgets.barFillRatio > 0.0f && trackWidth > 0.0f) {
        const float fillWidth = std::max(2.0f, trackWidth * widgets.barFillRatio);
        widgets.barFill->setSize(fillWidth, barHeight);
      } else if (widgets.barFill != nullptr) {
        widgets.barFill->setSize(0.0f, barHeight);
      }
    }
  }
}

void ScreenTimeTab::updateIconForRow(Renderer& renderer, AppRowWidgets& widgets, const std::string& appKey,
                                     float scale) {
  const std::string iconPath = resolveIconPath(appKey);
  if (iconPath == widgets.iconPath) {
    return;
  }
  widgets.iconPath = iconPath;
  const int targetPx = static_cast<int>(std::round(kAppIconSize * scale));
  const bool hasIcon =
      !iconPath.empty() && widgets.icon != nullptr && widgets.icon->setSourceFile(renderer, iconPath, targetPx, true);
  if (widgets.icon != nullptr) {
    widgets.icon->setVisible(hasIcon);
  }
  if (widgets.iconFallback != nullptr) {
    widgets.iconFallback->setVisible(!hasIcon);
  }
}

std::string ScreenTimeTab::resolveIconPath(const std::string& appKey) const {
  if (appKey.empty() || appKey.starts_with("title:")) {
    return {};
  }

  std::string baseKey = appKey;
  if (const auto sep = baseKey.find('\x1f'); sep != std::string::npos) {
    baseKey = baseKey.substr(0, sep);
  }

  if (const auto internal = internal_apps::metadataForAppId(baseKey); internal.has_value()) {
    return internal->iconPath;
  }

  const int targetPx = static_cast<int>(std::round(kAppIconSize * contentScale()));
  const auto lookupOptions =
      baseKey.starts_with("steam_app_")
          ? app_identity::DesktopEntryLookupOptions{.includeHidden = true, .includeNoDisplay = true}
          : app_identity::DesktopEntryLookupOptions{};
  std::string iconName;
  if (const auto entry = app_identity::findDesktopEntry(baseKey, desktopEntries(), lookupOptions);
      entry.has_value() && !entry->icon.empty()) {
    iconName = entry->icon;
  } else {
    iconName = app_identity::resolveRunningDesktopEntry(baseKey, desktopEntries()).icon;
  }
  if (!iconName.empty()) {
    const std::string& resolved = g_iconResolver.resolve(iconName, targetPx);
    if (!resolved.empty()) {
      return resolved;
    }
  }
  const std::string& resolved = g_iconResolver.resolve(baseKey, targetPx);
  return resolved.empty() ? std::string{} : std::string{resolved};
}
