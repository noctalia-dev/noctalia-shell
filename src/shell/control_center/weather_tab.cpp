#include "shell/control_center/weather_tab.h"

#include "config/config_service.h"
#include "i18n/i18n.h"
#include "render/scene/effect_node.h"
#include "system/weather_service.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/controls/separator.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <ctime>
#include <format>
#include <memory>

using namespace control_center;

namespace {

  // Set to a specific effect to bypass weather-code detection. Reset to None when done testing.
  constexpr EffectType kTestEffect = EffectType::None;

  constexpr float kCurrentGlyphSize = Style::controlHeightLg * 2.2f;

  std::string formatIsoClock(std::string_view isoTime) {
    const auto pos = isoTime.find('T');
    const std::size_t start = pos == std::string_view::npos ? 0 : pos + 1;
    if (isoTime.size() >= start + 5) {
      return std::string(isoTime.substr(start, 5));
    }
    return std::string(isoTime);
  }

  std::string windDirectionLabel(int degrees) {
    static constexpr std::array<const char*, 8> kDirs = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"};
    const int normalized = ((degrees % 360) + 360) % 360;
    const int index = static_cast<int>(std::lround(normalized / 45.0)) % 8;
    return kDirs[static_cast<std::size_t>(index)];
  }

} // namespace

WeatherTab::WeatherTab(WeatherService* weather, ConfigService* config) : m_weather(weather), m_config(config) {
  m_detailRows.fill(nullptr);
  m_dayRows.fill(nullptr);
  m_daySeparators.fill(nullptr);
  m_dayIconSlots.fill(nullptr);
  m_dayGlyphs.fill(nullptr);
  m_dayMetas.fill(nullptr);
  m_dayDescs.fill(nullptr);
  m_dayTemps.fill(nullptr);
}

std::unique_ptr<Flex> WeatherTab::create() {
  const float scale = contentScale();
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Horizontal);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  auto leftColumn = std::make_unique<Flex>();
  leftColumn->setDirection(FlexDirection::Vertical);
  leftColumn->setAlign(FlexAlign::Stretch);
  leftColumn->setGap(Style::spaceSm * scale);
  leftColumn->setFlexGrow(3.0f);
  m_leftColumn = leftColumn.get();

  auto currentCard = std::make_unique<Flex>();
  applySectionCardStyle(*currentCard, scale);
  m_currentCard = currentCard.get();
  currentCard->setDirection(FlexDirection::Horizontal);
  currentCard->setAlign(FlexAlign::Center);
  currentCard->setJustify(FlexJustify::Center);
  currentCard->setGap((Style::spaceMd + Style::spaceXs) * scale);
  currentCard->setFlexGrow(1.0f);
  currentCard->setClipChildren(true);

  auto effectNode = std::make_unique<EffectNode>();
  effectNode->setParticipatesInLayout(false);
  effectNode->setZIndex(-1);
  effectNode->setVisible(false);
  effectNode->setRadius(Style::radiusXl * scale);
  m_effectNode = static_cast<EffectNode*>(currentCard->addChild(std::move(effectNode)));

  auto currentGlyph = std::make_unique<Glyph>();
  currentGlyph->setGlyph("weather-cloud");
  currentGlyph->setGlyphSize(kCurrentGlyphSize * scale);
  currentGlyph->setColor(colorSpecFromRole(ColorRole::Primary));
  m_currentGlyph = currentGlyph.get();
  currentCard->addChild(std::move(currentGlyph));

  auto currentText = std::make_unique<Flex>();
  currentText->setDirection(FlexDirection::Vertical);
  currentText->setAlign(FlexAlign::Stretch);
  currentText->setJustify(FlexJustify::SpaceBetween);
  currentText->setGap(Style::spaceXs * scale);
  currentText->setFlexGrow(1.0f);
  currentText->setFillWidth(true);
  m_currentText = currentText.get();

  auto currentTop = std::make_unique<Flex>();
  currentTop->setDirection(FlexDirection::Vertical);
  currentTop->setAlign(FlexAlign::Stretch);
  currentTop->setGap(Style::spaceXs * scale);

  auto temp = std::make_unique<Label>();
  temp->setText("--°C");
  temp->setBold(true);
  temp->setFontSize(Style::fontSizeTitle * 2.35f * scale);
  temp->setColor(colorSpecFromRole(ColorRole::OnSurface));
  m_currentTempLabel = temp.get();
  currentTop->addChild(std::move(temp));

  auto hilo = std::make_unique<Label>();
  hilo->setText("--↑ --↓");
  hilo->setFontSize(Style::fontSizeBody * scale);
  hilo->setColor(colorSpecFromRole(ColorRole::Primary));
  m_currentHiLoLabel = hilo.get();
  currentTop->addChild(std::move(hilo));

  auto currentBottom = std::make_unique<Flex>();
  currentBottom->setDirection(FlexDirection::Vertical);
  currentBottom->setAlign(FlexAlign::Stretch);
  currentBottom->setGap(Style::spaceXs * 0.5f * scale);

  auto currentDesc = std::make_unique<Label>();
  currentDesc->setText(i18n::tr("control-center.weather.waiting"));
  currentDesc->setFontSize(Style::fontSizeBody * scale);
  currentDesc->setColor(colorSpecFromRole(ColorRole::OnSurface));
  m_currentDescLabel = currentDesc.get();
  currentBottom->addChild(std::move(currentDesc));

  auto updated = std::make_unique<Label>();
  updated->setText(" ");
  updated->setCaptionStyle();
  updated->setFontSize(Style::fontSizeCaption * scale);
  updated->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_updatedLabel = updated.get();
  currentBottom->addChild(std::move(updated));

  auto status = std::make_unique<Label>();
  status->setText(" ");
  status->setCaptionStyle();
  status->setFontSize(Style::fontSizeCaption * scale);
  status->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  status->setVisible(false);
  m_statusLabel = status.get();
  currentBottom->addChild(std::move(status));

  currentText->addChild(std::move(currentTop));
  currentText->addChild(std::move(currentBottom));

  currentCard->addChild(std::move(currentText));
  leftColumn->addChild(std::move(currentCard));

  auto detailsCard = std::make_unique<Flex>();
  applySectionCardStyle(*detailsCard, scale);
  m_detailsCard = detailsCard.get();
  detailsCard->setPadding(Style::spaceMd * scale, Style::spaceMd * scale, Style::spaceLg * scale,
                          Style::spaceMd * scale);
  detailsCard->setAlign(FlexAlign::Stretch);
  detailsCard->setGap(0);
  const float detailKeyWidth = Style::controlHeightLg * 2.0f * scale;

  std::size_t detailRowIndex = 0;
  auto addDetailRow = [&](std::string_view iconName, std::string_view key, Label*& valueOut) {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setMinHeight(Style::controlHeightSm * scale);
    row->setGap((Style::spaceSm + Style::spaceXs) * scale);
    row->setFlexGrow(0.0f);
    if (detailRowIndex < kDetailRowCount) {
      m_detailRows[detailRowIndex] = row.get();
    }
    ++detailRowIndex;

    auto icon = std::make_unique<Glyph>();
    icon->setGlyph(iconName);
    icon->setGlyphSize((Style::fontSizeBody + Style::spaceXs) * scale);
    icon->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    row->addChild(std::move(icon));

    auto keyLabel = std::make_unique<Label>();
    keyLabel->setText(key);
    keyLabel->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    keyLabel->setFontSize(Style::fontSizeBody * scale);
    keyLabel->setMinWidth(detailKeyWidth - (Style::fontSizeBody + Style::spaceXs) * scale - Style::spaceSm * scale);
    row->addChild(std::move(keyLabel));

    auto value = std::make_unique<Label>();
    value->setText("--");
    value->setBold(true);
    value->setFontSize(Style::fontSizeBody * scale);
    value->setColor(colorSpecFromRole(ColorRole::OnSurface));
    value->setTextAlign(TextAlign::End);
    value->setFlexGrow(1.0f);
    valueOut = value.get();

    row->addChild(std::move(value));
    detailsCard->addChild(std::move(row));
  };

  addDetailRow("temperature-sun", i18n::tr("control-center.weather.details.tempMax"), m_tempMaxLabel);
  addDetailRow("temperature", i18n::tr("control-center.weather.details.tempMin"), m_tempMinLabel);
  addDetailRow("wind", i18n::tr("control-center.weather.details.wind"), m_windLabel);
  addDetailRow("weather-sunrise", i18n::tr("control-center.weather.details.sunrise"), m_sunriseLabel);
  addDetailRow("weather-sunset", i18n::tr("control-center.weather.details.sunset"), m_sunsetLabel);
  addDetailRow("mountain", i18n::tr("control-center.weather.details.elevation"), m_elevationLabel);
  addDetailRow("clock", i18n::tr("control-center.weather.details.timezone"), m_timeZoneLabel);

  leftColumn->addChild(std::move(detailsCard));

  tab->addChild(std::move(leftColumn));

  auto forecastColumn = std::make_unique<Flex>();
  applySectionCardStyle(*forecastColumn, scale);
  forecastColumn->setGap(0.0f);
  forecastColumn->setPadding(0.0f, Style::spaceMd * scale);
  forecastColumn->setFlexGrow(2.0f);
  forecastColumn->setFillHeight(true);
  m_forecastColumn = forecastColumn.get();

  for (std::size_t i = 0; i < kDayCount; ++i) {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Vertical);
    row->setAlign(FlexAlign::Stretch);
    row->setJustify(FlexJustify::Center);
    row->setGap(Style::spaceXs * 0.5f * scale);
    row->setPadding(Style::spaceXs * scale, 0.0f);
    row->setFlexGrow(1.0f);
    m_dayRows[i] = row.get();

    auto topRow = std::make_unique<Flex>();
    topRow->setDirection(FlexDirection::Horizontal);
    topRow->setAlign(FlexAlign::Center);
    topRow->setJustify(FlexJustify::SpaceBetween);
    topRow->setGap(Style::spaceSm * scale);

    auto daySlot = std::make_unique<Flex>();
    daySlot->setDirection(FlexDirection::Horizontal);
    daySlot->setAlign(FlexAlign::Center);
    daySlot->setGap(Style::spaceXs * scale);
    daySlot->setFlexGrow(1.0f);
    m_dayIconSlots[i] = daySlot.get();

    auto glyph = std::make_unique<Glyph>();
    glyph->setGlyph("weather-cloud");
    glyph->setGlyphSize(Style::fontSizeBody * 1.2f * scale);
    glyph->setColor(colorSpecFromRole(ColorRole::OnSurface));
    m_dayGlyphs[i] = glyph.get();
    daySlot->addChild(std::move(glyph));

    auto meta = std::make_unique<Label>();
    meta->setText(i18n::tr("control-center.weather.forecast-placeholder.day"));
    meta->setBold(true);
    meta->setFontSize(Style::fontSizeBody * scale);
    meta->setColor(colorSpecFromRole(ColorRole::OnSurface));
    meta->setStableBaseline(true);
    m_dayMetas[i] = meta.get();
    daySlot->addChild(std::move(meta));
    topRow->addChild(std::move(daySlot));

    auto temps = std::make_unique<Label>();
    temps->setText(i18n::tr("control-center.weather.forecast-placeholder.temperature"));
    temps->setFontSize(Style::fontSizeBody * scale);
    temps->setColor(colorSpecFromRole(ColorRole::OnSurface));
    temps->setTextAlign(TextAlign::End);
    temps->setStableBaseline(true);
    m_dayTemps[i] = temps.get();
    topRow->addChild(std::move(temps));

    auto desc = std::make_unique<Label>();
    desc->setText(i18n::tr("control-center.weather.forecast-placeholder.description"));
    desc->setFontSize(Style::fontSizeCaption * scale);
    desc->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    m_dayDescs[i] = desc.get();

    row->addChild(std::move(topRow));
    row->addChild(std::move(desc));
    forecastColumn->addChild(std::move(row));

    if (i + 1 < kDayCount) {
      auto separator = std::make_unique<Separator>();
      separator->setThickness(std::max(1.0f, scale));
      m_daySeparators[i] = separator.get();
      forecastColumn->addChild(std::move(separator));
    }
  }

  tab->addChild(std::move(forecastColumn));
  return tab;
}

void WeatherTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr || m_currentText == nullptr || m_forecastColumn == nullptr) {
    return;
  }

  for (auto* label : m_dayTemps) {
    if (label != nullptr) {
      label->setMaxWidth(0.0f);
      label->setMinWidth(0.0f);
    }
  }

  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);

  const float leftColumnWidth =
      m_leftColumn != nullptr
          ? std::max(0.0f, m_leftColumn->width() - (m_leftColumn->paddingLeft() + m_leftColumn->paddingRight()))
          : contentWidth;
  float currentTextWidth = m_currentText->width();
  if (m_currentCard != nullptr && m_currentGlyph != nullptr) {
    const float currentCardWidth = leftColumnWidth > 0.0f ? leftColumnWidth : m_currentCard->width();
    const float cardInnerWidth =
        std::max(0.0f, currentCardWidth - (m_currentCard->paddingLeft() + m_currentCard->paddingRight()));
    const float availableTextWidth = std::max(1.0f, cardInnerWidth - m_currentGlyph->width() - m_currentCard->gap());
    const float balancedTextWidth = std::max(Style::controlHeightLg * 4.4f * contentScale(), cardInnerWidth * 0.58f);
    currentTextWidth = std::min(availableTextWidth, balancedTextWidth);
    m_currentText->setMaxWidth(currentTextWidth);
  }
  if (m_currentTempLabel != nullptr) {
    m_currentTempLabel->setMaxWidth(currentTextWidth);
  }
  if (m_currentDescLabel != nullptr) {
    m_currentDescLabel->setMaxWidth(currentTextWidth);
  }
  if (m_currentHiLoLabel != nullptr) {
    m_currentHiLoLabel->setMaxWidth(currentTextWidth);
  }
  if (m_updatedLabel != nullptr) {
    m_updatedLabel->setMaxWidth(currentTextWidth);
  }
  if (m_currentCard != nullptr) {
    m_currentCard->setMinWidth(leftColumnWidth);
  }
  if (m_detailsCard != nullptr) {
    m_detailsCard->setMinWidth(leftColumnWidth);
  }
  if (m_statusLabel != nullptr) {
    m_statusLabel->setMaxWidth(leftColumnWidth);
  }
  for (auto* label : {m_windLabel, m_sunriseLabel, m_sunsetLabel, m_tempMaxLabel, m_tempMinLabel, m_elevationLabel,
                      m_timeZoneLabel}) {
    if (label != nullptr) {
      label->setMaxWidth(leftColumnWidth);
    }
  }

  const float scale = contentScale();

  if (m_currentCard != nullptr) {
    m_currentCard->setMinHeight(Style::controlHeightLg * 3.1f * scale);
  }
  if (m_detailsCard != nullptr) {
    m_detailsCard->setMinHeight(0.0f);
    m_detailsCard->setFlexGrow(0.0f);
  }

  if (m_currentGlyph != nullptr && m_currentText != nullptr && m_currentCard != nullptr) {
    const float cardInnerHeight =
        std::max(0.0f, m_currentCard->height() - (m_currentCard->paddingTop() + m_currentCard->paddingBottom()));
    const float desiredGlyph =
        std::max(Style::controlHeightLg * 1.8f * scale, std::min(m_currentText->height(), cardInnerHeight));
    m_currentGlyph->setGlyphSize(desiredGlyph);
  }

  if (m_detailsCard != nullptr) {
    const float rowMinHeight = Style::controlHeightSm * scale;
    for (auto* row : m_detailRows) {
      if (row != nullptr) {
        row->setMinHeight(row->visible() ? rowMinHeight : 0.0f);
        row->setFlexGrow(0.0f);
      }
    }
  }

  std::size_t visibleForecastDays = 0;
  for (std::size_t i = 0; i < kDayCount; ++i) {
    if (m_dayRows[i] != nullptr && m_dayRows[i]->visible()) {
      ++visibleForecastDays;
    }
  }

  if (m_forecastColumn != nullptr && visibleForecastDays > 0) {
    const float separatorThickness = std::max(1.0f, scale);
    std::size_t visibleSeparators = 0;
    for (auto* separator : m_daySeparators) {
      if (separator != nullptr) {
        separator->setThickness(separatorThickness);
        if (separator->visible()) {
          ++visibleSeparators;
        }
      }
    }
    const float forecastInnerHeight = std::max(
        0.0f, m_forecastColumn->height() - (m_forecastColumn->paddingTop() + m_forecastColumn->paddingBottom()));
    const float separatorsTotal = separatorThickness * static_cast<float>(visibleSeparators);
    const float rowHeight = std::max(Style::controlHeightLg * scale,
                                     (forecastInnerHeight - separatorsTotal) / static_cast<float>(visibleForecastDays));

    for (std::size_t i = 0; i < kDayCount; ++i) {
      if (m_dayRows[i] == nullptr) {
        continue;
      }
      m_dayRows[i]->setMinHeight(m_dayRows[i]->visible() ? rowHeight : 0.0f);
    }
  }

  float forecastTempColumnWidth = 0.0f;
  for (std::size_t i = 0; i < kDayCount; ++i) {
    if (m_dayRows[i] != nullptr && m_dayRows[i]->visible() && m_dayTemps[i] != nullptr) {
      m_dayTemps[i]->measure(renderer);
      forecastTempColumnWidth = std::max(forecastTempColumnWidth, m_dayTemps[i]->width());
    }
  }

  const float forecastInnerWidth = m_forecastColumn != nullptr
                                       ? std::max(0.0f, m_forecastColumn->width() - m_forecastColumn->paddingLeft() -
                                                            m_forecastColumn->paddingRight())
                                       : 0.0f;
  for (std::size_t i = 0; i < kDayCount; ++i) {
    if (m_dayRows[i] == nullptr || !m_dayRows[i]->visible()) {
      continue;
    }
    if (m_dayTemps[i] != nullptr) {
      m_dayTemps[i]->setMinWidth(forecastTempColumnWidth);
    }
    if (m_dayMetas[i] != nullptr) {
      const float glyphWidth = m_dayGlyphs[i] != nullptr ? m_dayGlyphs[i]->width() : 0.0f;
      const float daySlotGap = m_dayIconSlots[i] != nullptr ? m_dayIconSlots[i]->gap() : 0.0f;
      const float topRowGap = Style::spaceSm * scale;
      const float metaMaxWidth = forecastInnerWidth - forecastTempColumnWidth - topRowGap - glyphWidth - daySlotGap;
      m_dayMetas[i]->setMaxWidth(std::max(1.0f, metaMaxWidth));
    }
  }

  if (m_effectNode != nullptr && m_currentCard != nullptr) {
    m_effectNode->setPosition(0.0f, 0.0f);
    m_effectNode->setFrameSize(m_currentCard->width(), m_currentCard->height());
  }

  // The weather tab derives several width constraints from the first measurement
  // pass. Run layout again so the final geometry reflects those constraints
  // instead of keeping the placeholder/pre-constraint positions.
  m_rootLayout->layout(renderer);

  if (m_effectNode != nullptr && m_currentCard != nullptr) {
    m_effectNode->setFrameSize(m_currentCard->width(), m_currentCard->height());
  }
}

void WeatherTab::doUpdate(Renderer& renderer) { sync(renderer); }

void WeatherTab::setForecastVisibleDayCount(std::size_t count) {
  const std::size_t visibleCount = std::min(count, kDayCount);
  for (std::size_t i = 0; i < kDayCount; ++i) {
    if (m_dayRows[i] != nullptr) {
      m_dayRows[i]->setVisible(i < visibleCount);
    }
    if (i + 1 < kDayCount && m_daySeparators[i] != nullptr) {
      m_daySeparators[i]->setVisible(i + 1 < visibleCount);
    }
  }
}

void WeatherTab::onClose() {
  m_rootLayout = nullptr;
  m_leftColumn = nullptr;
  m_currentCard = nullptr;
  m_detailsCard = nullptr;
  m_currentText = nullptr;
  m_forecastColumn = nullptr;
  m_statusLabel = nullptr;
  m_currentGlyph = nullptr;
  m_currentTempLabel = nullptr;
  m_currentHiLoLabel = nullptr;
  m_currentDescLabel = nullptr;
  m_updatedLabel = nullptr;
  m_windLabel = nullptr;
  m_sunriseLabel = nullptr;
  m_sunsetLabel = nullptr;
  m_tempMaxLabel = nullptr;
  m_tempMinLabel = nullptr;
  m_elevationLabel = nullptr;
  m_timeZoneLabel = nullptr;
  m_detailRows.fill(nullptr);
  m_dayRows.fill(nullptr);
  m_daySeparators.fill(nullptr);
  m_dayIconSlots.fill(nullptr);
  m_dayGlyphs.fill(nullptr);
  m_dayMetas.fill(nullptr);
  m_dayDescs.fill(nullptr);
  m_dayTemps.fill(nullptr);
  m_effectNode = nullptr;
  m_activeEffect = EffectType::None;
  m_shaderTime = 0.0f;
}

void WeatherTab::sync(Renderer& renderer) {
  if (m_statusLabel == nullptr || m_currentGlyph == nullptr || m_currentTempLabel == nullptr ||
      m_currentDescLabel == nullptr || m_updatedLabel == nullptr) {
    return;
  }

  const bool showLocation = m_config == nullptr || m_config->config().shell.showLocation;
  if (m_updatedLabel != nullptr) {
    m_updatedLabel->setVisible(showLocation);
  }

  if (m_weather == nullptr || !m_weather->enabled()) {
    m_currentGlyph->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    m_currentTempLabel->setText("--°C");
    if (m_currentHiLoLabel != nullptr) {
      m_currentHiLoLabel->setText("-- / --");
    }
    m_currentDescLabel->setText(i18n::tr("control-center.weather.disabled"));
    m_updatedLabel->setText(i18n::tr("control-center.weather.location-unavailable"));
    m_updatedLabel->setVisible(false);
    m_statusLabel->setText("");
    m_statusLabel->setVisible(false);
    if (m_windLabel != nullptr) {
      m_windLabel->setText("--");
    }
    if (m_sunriseLabel != nullptr) {
      m_sunriseLabel->setText("--");
    }
    if (m_sunsetLabel != nullptr) {
      m_sunsetLabel->setText("--");
    }
    if (m_tempMaxLabel != nullptr) {
      m_tempMaxLabel->setText("--");
    }
    if (m_tempMinLabel != nullptr) {
      m_tempMinLabel->setText("--");
    }
    if (m_elevationLabel != nullptr) {
      m_elevationLabel->setText("--");
    }
    if (m_timeZoneLabel != nullptr) {
      m_timeZoneLabel->setText("--");
    }
    setForecastVisibleDayCount(0);
    hideEffect();
    return;
  }

  if (!m_weather->locationConfigured()) {
    m_currentGlyph->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    m_currentTempLabel->setText(std::format("--{}", m_weather->displayTemperatureUnit()));
    if (m_currentHiLoLabel != nullptr) {
      m_currentHiLoLabel->setText("-- / --");
    }
    m_currentDescLabel->setText(i18n::tr("control-center.weather.configure-location"));
    m_updatedLabel->setText(i18n::tr("control-center.weather.location-unavailable"));
    m_updatedLabel->setVisible(false);
    m_statusLabel->setText("");
    m_statusLabel->setVisible(false);
    if (m_windLabel != nullptr) {
      m_windLabel->setText("--");
    }
    if (m_sunriseLabel != nullptr) {
      m_sunriseLabel->setText("--");
    }
    if (m_sunsetLabel != nullptr) {
      m_sunsetLabel->setText("--");
    }
    if (m_tempMaxLabel != nullptr) {
      m_tempMaxLabel->setText("--");
    }
    if (m_tempMinLabel != nullptr) {
      m_tempMinLabel->setText("--");
    }
    if (m_elevationLabel != nullptr) {
      m_elevationLabel->setText("--");
    }
    if (m_timeZoneLabel != nullptr) {
      m_timeZoneLabel->setText("--");
    }
    setForecastVisibleDayCount(0);
    hideEffect();
    return;
  }

  const auto& snapshot = m_weather->snapshot();
  if (!snapshot.valid) {
    m_currentGlyph->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    m_currentTempLabel->setText(std::format("--{}", m_weather->displayTemperatureUnit()));
    if (m_currentHiLoLabel != nullptr) {
      m_currentHiLoLabel->setText("-- / --");
    }
    m_currentDescLabel->setText(m_weather->loading() ? i18n::tr("control-center.weather.fetching")
                                                     : i18n::tr("control-center.weather.data-unavailable"));
    m_updatedLabel->setText(snapshot.locationName.empty() ? i18n::tr("weather.locations.current")
                                                          : snapshot.locationName);
    m_updatedLabel->setVisible(false);
    m_statusLabel->setText(m_weather->error());
    m_statusLabel->setVisible(!m_weather->error().empty());
    if (m_windLabel != nullptr) {
      m_windLabel->setText("--");
    }
    if (m_sunriseLabel != nullptr) {
      m_sunriseLabel->setText("--");
    }
    if (m_sunsetLabel != nullptr) {
      m_sunsetLabel->setText("--");
    }
    if (m_tempMaxLabel != nullptr) {
      m_tempMaxLabel->setText("--");
    }
    if (m_tempMinLabel != nullptr) {
      m_tempMinLabel->setText("--");
    }
    if (m_elevationLabel != nullptr) {
      m_elevationLabel->setText("--");
    }
    if (m_timeZoneLabel != nullptr) {
      m_timeZoneLabel->setText("--");
    }
    setForecastVisibleDayCount(0);
    hideEffect();
    return;
  }

  m_currentGlyph->setGlyph(WeatherService::glyphForCode(snapshot.current.weatherCode, snapshot.current.isDay));
  m_currentGlyph->setColor(colorSpecFromRole(snapshot.current.isDay ? ColorRole::Primary : ColorRole::Secondary));
  m_currentTempLabel->setText(
      std::format("{}{}", static_cast<int>(std::lround(m_weather->displayTemperature(snapshot.current.temperatureC))),
                  m_weather->displayTemperatureUnit()));
  if (m_currentHiLoLabel != nullptr) {
    if (!snapshot.forecastDays.empty()) {
      m_currentHiLoLabel->setText(std::format(
          "{} / {}{}",
          static_cast<int>(std::lround(m_weather->displayTemperature(snapshot.forecastDays.front().temperatureMaxC))),
          static_cast<int>(std::lround(m_weather->displayTemperature(snapshot.forecastDays.front().temperatureMinC))),
          m_weather->displayTemperatureUnit()));
    } else {
      m_currentHiLoLabel->setText("-- / --");
    }
  }
  m_currentDescLabel->setText(WeatherService::descriptionForCode(snapshot.current.weatherCode));
  m_updatedLabel->setText(snapshot.locationName.empty() ? i18n::tr("weather.locations.current")
                                                        : snapshot.locationName);
  m_updatedLabel->setVisible(showLocation);
  const std::string status = m_weather->loading() ? i18n::tr("control-center.weather.refreshing")
                                                  : (snapshot.valid ? std::string{} : m_weather->error());
  m_statusLabel->setText(status);
  m_statusLabel->setColor(
      colorSpecFromRole(m_weather->error().empty() ? ColorRole::OnSurfaceVariant : ColorRole::Error));
  m_statusLabel->setVisible(!status.empty());
  if (m_windLabel != nullptr) {
    const bool imperial = m_weather->useImperial();
    const double windSpeed = imperial ? snapshot.current.windSpeedKmh * 0.621371 : snapshot.current.windSpeedKmh;
    const char* windUnit =
        imperial ? "mph" : (snapshot.currentUnits.windSpeed.empty() ? "km/h" : snapshot.currentUnits.windSpeed.c_str());
    m_windLabel->setText(std::format("{} {} {}", static_cast<int>(std::lround(windSpeed)), windUnit,
                                     windDirectionLabel(snapshot.current.windDirectionDeg)));
  }
  if (m_sunriseLabel != nullptr) {
    m_sunriseLabel->setText(!snapshot.forecastDays.empty() ? formatIsoClock(snapshot.forecastDays.front().sunriseIso)
                                                           : std::string("--"));
  }
  if (m_sunsetLabel != nullptr) {
    m_sunsetLabel->setText(!snapshot.forecastDays.empty() ? formatIsoClock(snapshot.forecastDays.front().sunsetIso)
                                                          : std::string("--"));
  }
  auto unit = m_weather->displayTemperatureUnit();
  if (m_tempMaxLabel != nullptr) {
    auto temp =
        static_cast<int>(std::lround(m_weather->displayTemperature(snapshot.forecastDays.front().temperatureMaxC)));
    m_tempMaxLabel->setText(!snapshot.forecastDays.empty() ? std::format("{}{}", temp, unit) : std::string("--"));
  }
  if (m_tempMinLabel != nullptr) {
    auto temp =
        static_cast<int>(std::lround(m_weather->displayTemperature(snapshot.forecastDays.front().temperatureMinC)));
    m_tempMinLabel->setText(!snapshot.forecastDays.empty() ? std::format("{}{}", temp, unit) : std::string("--"));
  }
  if (m_elevationLabel != nullptr) {
    m_elevationLabel->setText(std::format("{}m", static_cast<int>(snapshot.elevationM)));
  }
  if (m_timeZoneLabel != nullptr) {
    m_timeZoneLabel->setText(snapshot.timezoneAbbreviation.empty()
                                 ? (snapshot.timezone.empty() ? std::string("--") : snapshot.timezone)
                                 : std::format("{} ({})", snapshot.timezoneAbbreviation, snapshot.timezone));
  }

  const bool firstForecastIsToday =
      !snapshot.forecastDays.empty() && snapshot.forecastDays.front().dateIso == todayIso(snapshot.utcOffsetSeconds);
  const std::size_t forecastStart = firstForecastIsToday ? 1 : 0;
  const std::size_t visibleForecastCount = forecastStart < snapshot.forecastDays.size()
                                               ? std::min(kDayCount, snapshot.forecastDays.size() - forecastStart)
                                               : 0;

  setForecastVisibleDayCount(visibleForecastCount);
  for (std::size_t i = 0; i < kDayCount; ++i) {
    const bool visible = i < visibleForecastCount;
    if (!visible) {
      continue;
    }

    const auto& day = snapshot.forecastDays[i + forecastStart];
    if (m_dayGlyphs[i] != nullptr) {
      m_dayGlyphs[i]->setGlyph(WeatherService::glyphForCode(day.weatherCode, true));
      m_dayGlyphs[i]->setColor(colorSpecFromRole(ColorRole::OnSurface));
      m_dayGlyphs[i]->measure(renderer);
    }
    if (m_dayMetas[i] != nullptr) {
      m_dayMetas[i]->setText(weekdayLabel(day.dateIso));
      m_dayMetas[i]->measure(renderer);
    }
    if (m_dayTemps[i] != nullptr) {
      m_dayTemps[i]->setText(
          std::format("{} / {}{}", static_cast<int>(std::lround(m_weather->displayTemperature(day.temperatureMaxC))),
                      static_cast<int>(std::lround(m_weather->displayTemperature(day.temperatureMinC))),
                      m_weather->displayTemperatureUnit()));
      m_dayTemps[i]->measure(renderer);
    }
    if (m_dayDescs[i] != nullptr) {
      m_dayDescs[i]->setText(WeatherService::shortDescriptionForCode(day.weatherCode));
      m_dayDescs[i]->measure(renderer);
    }
  }

  if (m_effectNode != nullptr) {
    const EffectType newEffect =
        kTestEffect != EffectType::None
            ? kTestEffect
            : (m_weather->effectsEnabled() ? effectForWeatherCode(snapshot.current.weatherCode, snapshot.current.isDay)
                                           : EffectType::None);
    if (newEffect != m_activeEffect) {
      m_activeEffect = newEffect;
      m_shaderTime = 0.0f;
    }
    m_effectNode->setEffectType(m_activeEffect);
    m_effectNode->setBgColor(colorForRole(ColorRole::Surface));
    m_effectNode->setRadius(Style::radiusXl * contentScale());
    m_effectNode->setVisible(m_activeEffect != EffectType::None);
  }
}

std::string WeatherTab::todayIso(std::int32_t utcOffsetSeconds) {
  const auto now = std::chrono::system_clock::now() + std::chrono::seconds{utcOffsetSeconds};
  const std::time_t time = std::chrono::system_clock::to_time_t(now);
  std::tm tm{};
  gmtime_r(&time, &tm);

  char buf[11]{};
  if (std::strftime(buf, sizeof(buf), "%Y-%m-%d", &tm) == 0) {
    return {};
  }
  return buf;
}

std::string WeatherTab::weekdayLabel(const std::string& isoDate) {
  if (isoDate.size() != 10) {
    return isoDate;
  }

  std::tm tm{};
  tm.tm_year = std::stoi(isoDate.substr(0, 4)) - 1900;
  tm.tm_mon = std::stoi(isoDate.substr(5, 2)) - 1;
  tm.tm_mday = std::stoi(isoDate.substr(8, 2));
  if (std::mktime(&tm) == -1) {
    return isoDate;
  }

  char buf[16];
  if (std::strftime(buf, sizeof(buf), "%A", &tm) == 0) {
    return isoDate;
  }
  return buf;
}

void WeatherTab::hideEffect() {
  m_activeEffect = EffectType::None;
  m_shaderTime = 0.0f;
  if (m_effectNode != nullptr) {
    m_effectNode->setEffectType(EffectType::None);
    m_effectNode->setVisible(false);
  }
}

void WeatherTab::onFrameTick(float deltaMs) {
  if (m_effectNode == nullptr || !m_effectNode->visible() || m_activeEffect == EffectType::None) {
    return;
  }
  m_shaderTime += deltaMs * 0.001f;
  m_effectNode->setTime(m_shaderTime);
}

EffectType WeatherTab::effectForWeatherCode(std::int32_t code, bool isDay) {
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
    return EffectType::Rain;
  }
  if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) {
    return EffectType::Snow;
  }
  if (code == 3) {
    return EffectType::Cloud;
  }
  if (code >= 40 && code <= 49) {
    return EffectType::Fog;
  }
  if (code == 0 && isDay) {
    return EffectType::Sun;
  }
  if (code == 0 && !isDay) {
    return EffectType::Stars;
  }
  return EffectType::None;
}
