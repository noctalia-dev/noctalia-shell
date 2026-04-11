#include "shell/control_center/weather_tab.h"

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

  constexpr float kCurrentGlyphSize = Style::controlHeightLg * 1.9f;

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
  tab->setGap(Style::spaceSm * scale);
  m_rootLayout = tab.get();

  auto leftColumn = std::make_unique<Flex>();
  leftColumn->setDirection(FlexDirection::Vertical);
  leftColumn->setAlign(FlexAlign::Stretch);
  leftColumn->setGap(Style::spaceSm * scale);
  leftColumn->setFlexGrow(3.0f);
  m_leftColumn = leftColumn.get();

  auto currentCard = std::make_unique<Flex>();
  applyCard(*currentCard, scale);
  currentCard->setDirection(FlexDirection::Horizontal);
  currentCard->setAlign(FlexAlign::Center);
  currentCard->setGap(Style::spaceMd * scale);
  currentCard->setPadding(Style::spaceXs * scale, Style::spaceMd * scale);

  auto currentGlyph = std::make_unique<Glyph>();
  currentGlyph->setGlyph("weather-cloud");
  currentGlyph->setGlyphSize(kCurrentGlyphSize * scale);
  currentGlyph->setColor(palette.primary);
  m_currentGlyph = currentGlyph.get();
  currentCard->addChild(std::move(currentGlyph));

  auto currentText = std::make_unique<Flex>();
  currentText->setDirection(FlexDirection::Vertical);
  currentText->setAlign(FlexAlign::Stretch);
  currentText->setGap(Style::spaceXs * scale);
  currentText->setFlexGrow(1.0f);
  m_currentText = currentText.get();

  auto location = std::make_unique<Label>();
  location->setText("Weather");
  location->setBold(true);
  location->setFontSize(Style::fontSizeTitle * scale);
  m_locationLabel = location.get();
  currentText->addChild(std::move(location));

  auto temp = std::make_unique<Label>();
  temp->setText("--°C");
  temp->setBold(true);
  temp->setFontSize(Style::fontSizeTitle * 2.0f * scale);
  m_currentTempLabel = temp.get();
  currentText->addChild(std::move(temp));

  auto currentDesc = std::make_unique<Label>();
  currentDesc->setText("Waiting for weather data");
  currentDesc->setFontSize(Style::fontSizeBody * scale);
  currentDesc->setColor(palette.onSurfaceVariant);
  m_currentDescLabel = currentDesc.get();
  currentText->addChild(std::move(currentDesc));

  auto updated = std::make_unique<Label>();
  updated->setText(" ");
  updated->setCaptionStyle();
  updated->setFontSize(Style::fontSizeCaption * scale);
  updated->setColor(palette.onSurfaceVariant);
  m_updatedLabel = updated.get();
  currentText->addChild(std::move(updated));

  currentCard->addChild(std::move(currentText));
  leftColumn->addChild(std::move(currentCard));

  auto status = std::make_unique<Label>();
  status->setText(" ");
  status->setFontSize(Style::fontSizeBody * scale);
  status->setColor(palette.onSurfaceVariant);
  m_statusLabel = status.get();
  leftColumn->addChild(std::move(status));

  auto detailsCard = std::make_unique<Flex>();
  applyCard(*detailsCard, scale);
  detailsCard->setPadding(Style::spaceXs * scale, Style::spaceMd * scale);
  detailsCard->setAlign(FlexAlign::Stretch);
  detailsCard->setGap(Style::spaceXs * scale);
  const float detailKeyWidth = Style::controlHeightLg * 2.0f * scale;

  auto addDetailRow = [&](std::string_view iconName, std::string_view key, Label*& valueOut) {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setGap((Style::spaceSm + Style::spaceXs) * scale);

    auto icon = std::make_unique<Glyph>();
    icon->setGlyph(iconName);
    icon->setGlyphSize((Style::fontSizeBody + Style::spaceXs) * scale);
    icon->setColor(palette.primary);
    row->addChild(std::move(icon));

    auto keyLabel = std::make_unique<Label>();
    keyLabel->setText(key);
    keyLabel->setBold(true);
    keyLabel->setFontSize(Style::fontSizeBody * scale);
    keyLabel->setMinWidth(detailKeyWidth - (Style::fontSizeBody + Style::spaceXs) * scale - Style::spaceSm * scale);
    row->addChild(std::move(keyLabel));

    auto valueWrap = std::make_unique<Flex>();
    valueWrap->setDirection(FlexDirection::Horizontal);
    valueWrap->setAlign(FlexAlign::Center);
    valueWrap->setJustify(FlexJustify::End);
    valueWrap->setFlexGrow(1.0f);

    auto value = std::make_unique<Label>();
    value->setText("--");
    value->setFontSize(Style::fontSizeBody * scale);
    value->setColor(palette.onSurfaceVariant);
    valueOut = value.get();
    valueWrap->addChild(std::move(value));

    row->addChild(std::move(valueWrap));
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
  forecastColumn->setGap(Style::spaceXs * scale);
  forecastColumn->setFlexGrow(2.0f);
  m_forecastColumn = forecastColumn.get();

  for (std::size_t i = 0; i < kDayCount; ++i) {
    auto card = std::make_unique<Flex>();
    applyCard(*card, scale);
    card->setDirection(FlexDirection::Horizontal);
    card->setAlign(FlexAlign::Center);
    card->setGap(Style::spaceSm * scale);
    card->setPadding(Style::spaceXs * scale, Style::spaceXs * scale);
    m_dayCards[i] = card.get();

    auto iconSlot = std::make_unique<Flex>();
    iconSlot->setDirection(FlexDirection::Horizontal);
    iconSlot->setAlign(FlexAlign::Center);
    m_dayIconSlots[i] = iconSlot.get();

    auto glyph = std::make_unique<Glyph>();
    glyph->setGlyph("weather-cloud");
    glyph->setGlyphSize(Style::fontSizeTitle * 1.9f * scale);
    glyph->setColor(palette.primary);
    m_dayGlyphs[i] = glyph.get();
    iconSlot->addChild(std::move(glyph));
    card->addChild(std::move(iconSlot));

    auto meta = std::make_unique<Label>();
    meta->setText("Sun");
    meta->setBold(true);
    meta->setFontSize(Style::fontSizeBody * scale);
    meta->setColor(palette.onSurfaceVariant);
    meta->setFlexGrow(1.0f);
    m_dayMetas[i] = meta.get();
    card->addChild(std::move(meta));

    auto temps = std::make_unique<Label>();
    temps->setText("10 / 4C");
    temps->setBold(true);
    temps->setFontSize(Style::fontSizeBody * scale);
    temps->setColor(palette.onSurface);
    temps->setFlexGrow(2.0f);
    m_dayTemps[i] = temps.get();
    card->addChild(std::move(temps));

    auto desc = std::make_unique<Label>();
    desc->setText("Weather");
    desc->setFontSize(Style::fontSizeBody * scale);
    desc->setColor(palette.onSurfaceVariant);
    desc->setFlexGrow(2.75f);
    m_dayDescs[i] = desc.get();
    card->addChild(std::move(desc));
    forecastColumn->addChild(std::move(card));
  }

  tab->addChild(std::move(forecastColumn));
  return tab;
}

void WeatherTab::layout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr || m_currentText == nullptr || m_forecastColumn == nullptr) {
    return;
  }

  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);

  const float currentTextWidth = m_currentText->width();
  if (m_locationLabel != nullptr) {
    m_locationLabel->setMaxWidth(currentTextWidth);
  }
  if (m_currentDescLabel != nullptr) {
    m_currentDescLabel->setMaxWidth(currentTextWidth);
  }
  if (m_updatedLabel != nullptr) {
    m_updatedLabel->setMaxWidth(currentTextWidth);
  }
  const float leftColumnWidth =
      m_leftColumn != nullptr
          ? std::max(0.0f, m_leftColumn->width() - (m_leftColumn->paddingLeft() + m_leftColumn->paddingRight()))
          : contentWidth;
  if (m_statusLabel != nullptr) {
    m_statusLabel->setMaxWidth(leftColumnWidth);
  }
  for (auto* label : {m_windLabel, m_sunriseLabel, m_sunsetLabel, m_timezoneLabel, m_longitudeLabel, m_elevationLabel}) {
    if (label != nullptr) {
      label->setMaxWidth(leftColumnWidth);
    }
  }

  const float scale = contentScale();
  const float iconSlotWidth = Style::fontSizeTitle * 2.6f * scale;

  for (std::size_t i = 0; i < kDayCount; ++i) {
    if (m_dayCards[i] == nullptr) {
      continue;
    }
    if (m_dayIconSlots[i] != nullptr) {
      m_dayIconSlots[i]->setMinWidth(iconSlotWidth);
    }
    if (m_dayMetas[i] != nullptr) {
      m_dayMetas[i]->setMaxWidth(m_dayMetas[i]->width());
    }
    if (m_dayTemps[i] != nullptr) {
      m_dayTemps[i]->setMaxWidth(m_dayTemps[i]->width());
    }
    if (m_dayDescs[i] != nullptr) {
      m_dayDescs[i]->setMaxWidth(m_dayDescs[i]->width());
    }
  }

  // The weather tab derives several width constraints from the first measurement
  // pass. Run layout again so the final geometry reflects those constraints
  // instead of keeping the placeholder/pre-constraint positions.
  m_rootLayout->layout(renderer);
}

void WeatherTab::update(Renderer& renderer) { sync(renderer); }

void WeatherTab::onClose() {
  m_rootLayout = nullptr;
  m_leftColumn = nullptr;
  m_currentText = nullptr;
  m_forecastColumn = nullptr;
  m_statusLabel = nullptr;
  m_currentGlyph = nullptr;
  m_locationLabel = nullptr;
  m_currentTempLabel = nullptr;
  m_currentDescLabel = nullptr;
  m_updatedLabel = nullptr;
  m_windLabel = nullptr;
  m_sunriseLabel = nullptr;
  m_sunsetLabel = nullptr;
  m_timezoneLabel = nullptr;
  m_longitudeLabel = nullptr;
  m_elevationLabel = nullptr;
  m_dayCards.fill(nullptr);
  m_dayIconSlots.fill(nullptr);
  m_dayGlyphs.fill(nullptr);
  m_dayMetas.fill(nullptr);
  m_dayDescs.fill(nullptr);
  m_dayTemps.fill(nullptr);
}

void WeatherTab::sync(Renderer& renderer) {
  if (m_statusLabel == nullptr || m_currentGlyph == nullptr || m_locationLabel == nullptr ||
      m_currentTempLabel == nullptr || m_currentDescLabel == nullptr || m_updatedLabel == nullptr) {
    return;
  }

  if (m_weather == nullptr || !m_weather->enabled()) {
    m_locationLabel->setText("Weather disabled");
    m_currentTempLabel->setText("--°C");
    m_currentDescLabel->setText("Enable [weather] in config.toml");
    m_updatedLabel->setText("");
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
    return;
  }

  if (!m_weather->locationConfigured()) {
    m_locationLabel->setText("Weather not configured");
    m_currentTempLabel->setText(std::format("--{}", m_weather->displayTemperatureUnit()));
    m_currentDescLabel->setText("Set [weather].address or enable auto_locate");
    m_updatedLabel->setText("");
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
    return;
  }

  const auto& snapshot = m_weather->snapshot();
  if (!snapshot.valid) {
    m_locationLabel->setText("Weather");
    m_currentTempLabel->setText(std::format("--{}", m_weather->displayTemperatureUnit()));
    m_currentDescLabel->setText(m_weather->loading() ? "Fetching forecast..." : "Weather data unavailable");
    m_updatedLabel->setText("");
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
    return;
  }

  m_currentGlyph->setGlyph(WeatherService::glyphForCode(snapshot.current.weatherCode, snapshot.current.isDay));
  m_locationLabel->setText(snapshot.locationName.empty() ? "Weather" : snapshot.locationName);
  m_currentTempLabel->setText(
      std::format("{}{}", static_cast<int>(std::lround(m_weather->displayTemperature(snapshot.current.temperatureC))),
                  m_weather->displayTemperatureUnit()));
  m_currentDescLabel->setText(WeatherService::descriptionForCode(snapshot.current.weatherCode));
  m_updatedLabel->setText(std::format("Updated {}", formatTimeAgo(snapshot.fetchedAt)));
  m_updatedLabel->setVisible(true);
  const std::string status = m_weather->loading() ? "Refreshing weather..." : m_weather->error();
  m_statusLabel->setText(status);
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
  if (std::strftime(buf, sizeof(buf), "%a", &tm) == 0) {
    return isoDate;
  }
  return buf;
}
