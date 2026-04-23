#include "shell/control_center/weather_tab.h"

#include "render/scene/effect_node.h"
#include "system/weather_service.h"
#include "time/time_service.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"

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

WeatherTab::WeatherTab(WeatherService* weather) : m_weather(weather) {
  m_detailRows.fill(nullptr);
  m_dayCards.fill(nullptr);
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
  applyOutlinedCard(*currentCard, scale);
  m_currentCard = currentCard.get();
  currentCard->setDirection(FlexDirection::Horizontal);
  currentCard->setAlign(FlexAlign::Center);
  currentCard->setJustify(FlexJustify::Center);
  currentCard->setGap((Style::spaceMd + Style::spaceXs) * scale);
  currentCard->setFlexGrow(0.9f);
  currentCard->setClipChildren(true);

  auto effectNode = std::make_unique<EffectNode>();
  effectNode->setParticipatesInLayout(false);
  effectNode->setZIndex(-1);
  effectNode->setVisible(false);
  effectNode->setCornerRadius(Style::radiusXl * scale);
  m_effectNode = static_cast<EffectNode*>(currentCard->addChild(std::move(effectNode)));

  auto currentGlyph = std::make_unique<Glyph>();
  currentGlyph->setGlyph("weather-cloud");
  currentGlyph->setGlyphSize(kCurrentGlyphSize * scale);
  currentGlyph->setColor(roleColor(ColorRole::Primary));
  m_currentGlyph = currentGlyph.get();
  currentCard->addChild(std::move(currentGlyph));

  auto currentText = std::make_unique<Flex>();
  currentText->setDirection(FlexDirection::Vertical);
  currentText->setAlign(FlexAlign::Start);
  currentText->setJustify(FlexJustify::SpaceBetween);
  currentText->setGap(Style::spaceXs * scale);
  m_currentText = currentText.get();

  auto currentTop = std::make_unique<Flex>();
  currentTop->setDirection(FlexDirection::Vertical);
  currentTop->setAlign(FlexAlign::Stretch);
  currentTop->setGap(Style::spaceXs * scale);

  auto temp = std::make_unique<Label>();
  temp->setText("--°C");
  temp->setBold(true);
  temp->setFontSize(Style::fontSizeTitle * 2.35f * scale);
  temp->setColor(roleColor(ColorRole::OnSurface));
  m_currentTempLabel = temp.get();
  currentTop->addChild(std::move(temp));

  auto hilo = std::make_unique<Label>();
  hilo->setText("--↑ --↓");
  hilo->setFontSize(Style::fontSizeBody * scale);
  hilo->setColor(roleColor(ColorRole::Primary));
  m_currentHiLoLabel = hilo.get();
  currentTop->addChild(std::move(hilo));

  auto currentBottom = std::make_unique<Flex>();
  currentBottom->setDirection(FlexDirection::Vertical);
  currentBottom->setAlign(FlexAlign::Stretch);
  currentBottom->setGap(Style::spaceXs * 0.5f * scale);

  auto currentDesc = std::make_unique<Label>();
  currentDesc->setText("Waiting for weather data");
  currentDesc->setFontSize(Style::fontSizeBody * scale);
  currentDesc->setColor(roleColor(ColorRole::OnSurface));
  m_currentDescLabel = currentDesc.get();
  currentBottom->addChild(std::move(currentDesc));

  auto updated = std::make_unique<Label>();
  updated->setText(" ");
  updated->setCaptionStyle();
  updated->setFontSize(Style::fontSizeCaption * scale);
  updated->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_updatedLabel = updated.get();
  currentBottom->addChild(std::move(updated));

  auto status = std::make_unique<Label>();
  status->setText(" ");
  status->setCaptionStyle();
  status->setFontSize(Style::fontSizeCaption * scale);
  status->setColor(roleColor(ColorRole::OnSurfaceVariant));
  status->setVisible(false);
  m_statusLabel = status.get();
  currentBottom->addChild(std::move(status));

  currentText->addChild(std::move(currentTop));
  currentText->addChild(std::move(currentBottom));

  currentCard->addChild(std::move(currentText));
  leftColumn->addChild(std::move(currentCard));

  auto detailsCard = std::make_unique<Flex>();
  applyOutlinedCard(*detailsCard, scale);
  m_detailsCard = detailsCard.get();
  detailsCard->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
  detailsCard->setAlign(FlexAlign::Stretch);
  detailsCard->setGap(Style::spaceSm * scale);
  detailsCard->setFlexGrow(1.1f);
  const float detailKeyWidth = Style::controlHeightLg * 2.0f * scale;

  std::size_t detailRowIndex = 0;
  auto addDetailRow = [&](std::string_view iconName, std::string_view key, Label*& valueOut) {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setMinHeight(Style::controlHeightSm * scale);
    row->setGap((Style::spaceSm + Style::spaceXs) * scale);
    if (detailRowIndex < kDetailRowCount) {
      m_detailRows[detailRowIndex] = row.get();
    }
    ++detailRowIndex;

    auto icon = std::make_unique<Glyph>();
    icon->setGlyph(iconName);
    icon->setGlyphSize((Style::fontSizeBody + Style::spaceXs) * scale);
    icon->setColor(roleColor(ColorRole::OnSurfaceVariant));
    row->addChild(std::move(icon));

    auto keyLabel = std::make_unique<Label>();
    keyLabel->setText(key);
    keyLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
    keyLabel->setFontSize(Style::fontSizeBody * scale);
    keyLabel->setMinWidth(detailKeyWidth - (Style::fontSizeBody + Style::spaceXs) * scale - Style::spaceSm * scale);
    row->addChild(std::move(keyLabel));

    auto value = std::make_unique<Label>();
    value->setText("--");
    value->setBold(true);
    value->setFontSize(Style::fontSizeBody * scale);
    value->setColor(roleColor(ColorRole::OnSurface));
    value->setTextAlign(TextAlign::End);
    value->setFlexGrow(1.0f);
    valueOut = value.get();

    row->addChild(std::move(value));
    detailsCard->addChild(std::move(row));
  };

  addDetailRow("wind", "Wind", m_windLabel);
  addDetailRow("weather-sunrise", "Sunrise", m_sunriseLabel);
  addDetailRow("weather-sunset", "Sunset", m_sunsetLabel);
  addDetailRow("world-pin", "Latitude", m_timezoneLabel);
  addDetailRow("map-pin", "Longitude", m_longitudeLabel);
  addDetailRow("clock", "Timezone", m_elevationLabel);

  leftColumn->addChild(std::move(detailsCard));

  tab->addChild(std::move(leftColumn));

  auto forecastColumn = std::make_unique<Flex>();
  forecastColumn->setDirection(FlexDirection::Vertical);
  forecastColumn->setAlign(FlexAlign::Stretch);
  forecastColumn->setGap(Style::spaceSm * scale);
  forecastColumn->setFlexGrow(2.0f);
  m_forecastColumn = forecastColumn.get();

  for (std::size_t i = 0; i < kDayCount; ++i) {
    auto card = std::make_unique<Flex>();
    applyOutlinedCard(*card, scale);
    card->setDirection(FlexDirection::Horizontal);
    card->setAlign(FlexAlign::Center);
    card->setGap(Style::spaceSm * scale);
    card->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    card->setFlexGrow(1.0f);
    m_dayCards[i] = card.get();

    auto iconSlot = std::make_unique<Flex>();
    iconSlot->setDirection(FlexDirection::Horizontal);
    iconSlot->setAlign(FlexAlign::Center);
    iconSlot->setJustify(FlexJustify::Center);
    m_dayIconSlots[i] = iconSlot.get();

    auto glyph = std::make_unique<Glyph>();
    glyph->setGlyph("weather-cloud");
    glyph->setGlyphSize(Style::fontSizeTitle * 1.7f * scale);
    glyph->setColor(roleColor(ColorRole::OnSurface));
    m_dayGlyphs[i] = glyph.get();
    iconSlot->addChild(std::move(glyph));
    card->addChild(std::move(iconSlot));

    auto infoStack = std::make_unique<Flex>();
    infoStack->setDirection(FlexDirection::Vertical);
    infoStack->setAlign(FlexAlign::Stretch);
    infoStack->setGap(Style::spaceXs * 0.5f * scale);
    infoStack->setFlexGrow(1.0f);

    auto topRow = std::make_unique<Flex>();
    topRow->setDirection(FlexDirection::Horizontal);
    topRow->setAlign(FlexAlign::Center);
    topRow->setJustify(FlexJustify::SpaceBetween);
    topRow->setGap(Style::spaceSm * scale);

    auto meta = std::make_unique<Label>();
    meta->setText("Sunday");
    meta->setBold(true);
    meta->setFontSize(Style::fontSizeBody * scale);
    meta->setColor(roleColor(ColorRole::OnSurface));
    meta->setFlexGrow(1.0f);
    m_dayMetas[i] = meta.get();
    topRow->addChild(std::move(meta));

    auto temps = std::make_unique<Label>();
    temps->setText("10 / 4C");
    temps->setBold(true);
    temps->setFontSize(Style::fontSizeBody * scale);
    temps->setColor(roleColor(ColorRole::OnSurface));
    m_dayTemps[i] = temps.get();
    topRow->addChild(std::move(temps));

    auto desc = std::make_unique<Label>();
    desc->setText("Weather");
    desc->setFontSize(Style::fontSizeCaption * scale);
    desc->setColor(roleColor(ColorRole::OnSurfaceVariant));
    m_dayDescs[i] = desc.get();

    infoStack->addChild(std::move(topRow));
    infoStack->addChild(std::move(desc));
    card->addChild(std::move(infoStack));
    forecastColumn->addChild(std::move(card));
  }

  tab->addChild(std::move(forecastColumn));
  return tab;
}

void WeatherTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr || m_currentText == nullptr || m_forecastColumn == nullptr) {
    return;
  }

  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);

  float currentTextWidth = m_currentText->width();
  if (m_currentCard != nullptr && m_currentGlyph != nullptr) {
    const float cardInnerWidth =
        std::max(0.0f, m_currentCard->width() - (m_currentCard->paddingLeft() + m_currentCard->paddingRight()));
    currentTextWidth = std::max(1.0f, cardInnerWidth - m_currentGlyph->width() - m_currentCard->gap());
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
  const float leftColumnWidth =
      m_leftColumn != nullptr
          ? std::max(0.0f, m_leftColumn->width() - (m_leftColumn->paddingLeft() + m_leftColumn->paddingRight()))
          : contentWidth;
  if (m_currentCard != nullptr) {
    m_currentCard->setMinWidth(leftColumnWidth);
  }
  if (m_detailsCard != nullptr) {
    m_detailsCard->setMinWidth(leftColumnWidth);
  }
  if (m_statusLabel != nullptr) {
    m_statusLabel->setMaxWidth(leftColumnWidth);
  }
  for (auto* label :
       {m_windLabel, m_sunriseLabel, m_sunsetLabel, m_timezoneLabel, m_longitudeLabel, m_elevationLabel}) {
    if (label != nullptr) {
      label->setMaxWidth(leftColumnWidth);
    }
  }

  const float scale = contentScale();

  float detailsTargetHeight = 0.0f;
  if (m_leftColumn != nullptr && m_currentCard != nullptr && m_detailsCard != nullptr) {
    const float leftInnerHeight =
        std::max(0.0f, m_leftColumn->height() - (m_leftColumn->paddingTop() + m_leftColumn->paddingBottom()));
    const float leftGap = m_leftColumn->gap();
    const float available = std::max(0.0f, leftInnerHeight - leftGap);
    const float currentShare = 0.43f;
    const float currentMin = Style::controlHeightLg * 3.1f * scale;
    const float detailsMin = Style::controlHeightSm * 6.0f * scale;
    const float currentH = std::max(currentMin, available * currentShare);
    detailsTargetHeight = std::max(detailsMin, available - currentH);
    m_currentCard->setMinHeight(currentH);
    m_detailsCard->setMinHeight(detailsTargetHeight);
  }

  if (m_currentGlyph != nullptr && m_currentText != nullptr && m_currentCard != nullptr) {
    const float cardInnerHeight =
        std::max(0.0f, m_currentCard->height() - (m_currentCard->paddingTop() + m_currentCard->paddingBottom()));
    const float desiredGlyph =
        std::max(Style::controlHeightLg * 1.8f * scale, std::min(m_currentText->height(), cardInnerHeight));
    m_currentGlyph->setGlyphSize(desiredGlyph);
  }

  if (m_detailsCard != nullptr && detailsTargetHeight > 0.0f) {
    std::size_t visibleRows = 0;
    for (auto* row : m_detailRows) {
      if (row != nullptr && row->visible()) {
        ++visibleRows;
      }
    }
    if (visibleRows > 0) {
      const float detailsInnerHeight =
          std::max(0.0f, detailsTargetHeight - (m_detailsCard->paddingTop() + m_detailsCard->paddingBottom()));
      const float gapsTotal = m_detailsCard->gap() * static_cast<float>(visibleRows - 1);
      const float rowHeight =
          std::max(Style::controlHeightSm * scale, (detailsInnerHeight - gapsTotal) / static_cast<float>(visibleRows));
      for (auto* row : m_detailRows) {
        if (row != nullptr) {
          row->setMinHeight(row->visible() ? rowHeight : 0.0f);
        }
      }
    }
  }

  const float iconSlotWidth = Style::fontSizeTitle * 2.6f * scale;
  std::size_t visibleForecastDays = 0;
  for (std::size_t i = 0; i < kDayCount; ++i) {
    if (m_dayCards[i] != nullptr && m_dayCards[i]->visible()) {
      ++visibleForecastDays;
    }
  }

  if (m_forecastColumn != nullptr && visibleForecastDays > 0) {
    const float forecastInnerHeight = std::max(
        0.0f, m_forecastColumn->height() - (m_forecastColumn->paddingTop() + m_forecastColumn->paddingBottom()));
    const float gapsTotal = m_forecastColumn->gap() * static_cast<float>(visibleForecastDays - 1);
    const float rowHeight = std::max(Style::controlHeightLg * scale,
                                     (forecastInnerHeight - gapsTotal) / static_cast<float>(visibleForecastDays));

    for (std::size_t i = 0; i < kDayCount; ++i) {
      if (m_dayCards[i] == nullptr) {
        continue;
      }
      m_dayCards[i]->setMinHeight(m_dayCards[i]->visible() ? rowHeight : 0.0f);
    }
  }

  for (std::size_t i = 0; i < kDayCount; ++i) {
    if (m_dayCards[i] == nullptr) {
      continue;
    }
    if (m_dayIconSlots[i] != nullptr) {
      m_dayIconSlots[i]->setMinWidth(iconSlotWidth);
    }
    if (m_dayMetas[i] != nullptr) {
      m_dayMetas[i]->setMaxWidth(std::max(1.0f, m_dayMetas[i]->width()));
    }
    if (m_dayTemps[i] != nullptr) {
      m_dayTemps[i]->setMaxWidth(std::max(1.0f, m_dayTemps[i]->width()));
    }
    if (m_dayDescs[i] != nullptr) {
      m_dayDescs[i]->setMaxWidth(std::max(1.0f, m_dayDescs[i]->width()));
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
  m_timezoneLabel = nullptr;
  m_longitudeLabel = nullptr;
  m_elevationLabel = nullptr;
  m_detailRows.fill(nullptr);
  m_dayCards.fill(nullptr);
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

  if (m_weather == nullptr || !m_weather->enabled()) {
    m_currentGlyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
    m_currentTempLabel->setText("--°C");
    if (m_currentHiLoLabel != nullptr) {
      m_currentHiLoLabel->setText("-- / --");
    }
    m_currentDescLabel->setText("Enable [weather] in config.toml");
    m_updatedLabel->setText("Location unavailable");
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
    if (m_timezoneLabel != nullptr) {
      m_timezoneLabel->setText("--");
    }
    if (m_elevationLabel != nullptr) {
      m_elevationLabel->setText("--");
    }
    if (m_longitudeLabel != nullptr) {
      m_longitudeLabel->setText("--");
    }
    for (auto* card : m_dayCards) {
      if (card != nullptr) {
        card->setVisible(false);
      }
    }
    if (m_effectNode != nullptr) {
      m_effectNode->setVisible(false);
    }
    return;
  }

  if (!m_weather->locationConfigured()) {
    m_currentGlyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
    m_currentTempLabel->setText(std::format("--{}", m_weather->displayTemperatureUnit()));
    if (m_currentHiLoLabel != nullptr) {
      m_currentHiLoLabel->setText("-- / --");
    }
    m_currentDescLabel->setText("Set [weather].address or enable auto_locate");
    m_updatedLabel->setText("Location unavailable");
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
    if (m_timezoneLabel != nullptr) {
      m_timezoneLabel->setText("--");
    }
    if (m_elevationLabel != nullptr) {
      m_elevationLabel->setText("--");
    }
    if (m_longitudeLabel != nullptr) {
      m_longitudeLabel->setText("--");
    }
    for (auto* card : m_dayCards) {
      if (card != nullptr) {
        card->setVisible(false);
      }
    }
    if (m_effectNode != nullptr) {
      m_effectNode->setVisible(false);
    }
    return;
  }

  const auto& snapshot = m_weather->snapshot();
  if (!snapshot.valid) {
    m_currentGlyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
    m_currentTempLabel->setText(std::format("--{}", m_weather->displayTemperatureUnit()));
    if (m_currentHiLoLabel != nullptr) {
      m_currentHiLoLabel->setText("-- / --");
    }
    m_currentDescLabel->setText(m_weather->loading() ? "Fetching forecast..." : "Weather data unavailable");
    m_updatedLabel->setText(snapshot.locationName.empty() ? "Current location" : snapshot.locationName);
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
    if (m_timezoneLabel != nullptr) {
      m_timezoneLabel->setText("--");
    }
    if (m_elevationLabel != nullptr) {
      m_elevationLabel->setText("--");
    }
    if (m_longitudeLabel != nullptr) {
      m_longitudeLabel->setText("--");
    }
    for (auto* card : m_dayCards) {
      if (card != nullptr) {
        card->setVisible(false);
      }
    }
    if (m_effectNode != nullptr) {
      m_effectNode->setVisible(false);
    }
    return;
  }

  m_currentGlyph->setGlyph(WeatherService::glyphForCode(snapshot.current.weatherCode, snapshot.current.isDay));
  m_currentGlyph->setColor(roleColor(snapshot.current.isDay ? ColorRole::Primary : ColorRole::Secondary));
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
  m_updatedLabel->setText(snapshot.locationName.empty() ? "Current location" : snapshot.locationName);
  m_updatedLabel->setVisible(true);
  const std::string status = m_weather->loading() ? "Refreshing weather..." : m_weather->error();
  m_statusLabel->setText(status);
  m_statusLabel->setColor(roleColor(m_weather->error().empty() ? ColorRole::OnSurfaceVariant : ColorRole::Error));
  m_statusLabel->setVisible(!status.empty());
  if (m_windLabel != nullptr) {
    m_windLabel->setText(std::format("{} {} {}", static_cast<int>(std::lround(snapshot.current.windSpeedKmh)),
                                     snapshot.currentUnits.windSpeed.empty() ? "km/h" : snapshot.currentUnits.windSpeed,
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
  if (m_timezoneLabel != nullptr) {
    m_timezoneLabel->setText(std::format("{:.4f}", snapshot.latitude));
  }
  if (m_longitudeLabel != nullptr) {
    m_longitudeLabel->setText(std::format("{:.4f}", snapshot.longitude));
  }
  if (m_elevationLabel != nullptr) {
    m_elevationLabel->setText(snapshot.timezoneAbbreviation.empty()
                                  ? (snapshot.timezone.empty() ? std::string("--") : snapshot.timezone)
                                  : std::format("{} ({})", snapshot.timezoneAbbreviation, snapshot.timezone));
  }

  for (std::size_t i = 0; i < kDayCount; ++i) {
    const bool visible = i < snapshot.forecastDays.size();
    if (m_dayCards[i] != nullptr) {
      m_dayCards[i]->setVisible(visible);
    }
    if (!visible) {
      continue;
    }

    const auto& day = snapshot.forecastDays[i];
    if (m_dayGlyphs[i] != nullptr) {
      m_dayGlyphs[i]->setGlyph(WeatherService::glyphForCode(day.weatherCode, true));
      m_dayGlyphs[i]->setColor(roleColor(ColorRole::OnSurface));
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
    m_effectNode->setBgColor(resolveColorRole(ColorRole::Surface));
    m_effectNode->setCornerRadius(Style::radiusXl * contentScale());
    m_effectNode->setVisible(m_activeEffect != EffectType::None);
  }
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

void WeatherTab::onFrameTick(float deltaMs) {
  if (m_effectNode == nullptr || m_activeEffect == EffectType::None) {
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
