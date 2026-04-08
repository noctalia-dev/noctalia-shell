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

constexpr float kCurrentGlyphSize = Style::controlHeightLg * 2.0f;
constexpr float kForecastCardMinWidth = 104.0f;

} // namespace

WeatherTab::WeatherTab(WeatherService* weather) : m_weather(weather) {
  m_dayCards.fill(nullptr);
  m_dayGlyphs.fill(nullptr);
  m_dayNames.fill(nullptr);
  m_dayDescs.fill(nullptr);
  m_dayTemps.fill(nullptr);
}

std::unique_ptr<Flex> WeatherTab::build(Renderer& /*renderer*/) {
  const float scale = contentScale();
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Start);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  auto currentCard = std::make_unique<Flex>();
  applyCard(*currentCard, scale);
  currentCard->setDirection(FlexDirection::Horizontal);
  currentCard->setAlign(FlexAlign::Center);
  currentCard->setGap(Style::spaceLg * scale);

  auto currentGlyph = std::make_unique<Glyph>();
  currentGlyph->setGlyph("weather-cloud");
  currentGlyph->setGlyphSize(kCurrentGlyphSize * scale);
  currentGlyph->setColor(palette.primary);
  m_currentGlyph = currentGlyph.get();
  currentCard->addChild(std::move(currentGlyph));

  auto currentText = std::make_unique<Flex>();
  currentText->setDirection(FlexDirection::Vertical);
  currentText->setAlign(FlexAlign::Start);
  currentText->setGap(Style::spaceXs * scale);

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
  tab->addChild(std::move(currentCard));

  auto status = std::make_unique<Label>();
  status->setText(" ");
  status->setFontSize(Style::fontSizeBody * scale);
  status->setColor(palette.onSurfaceVariant);
  m_statusLabel = status.get();
  tab->addChild(std::move(status));

  auto forecastRow = std::make_unique<Flex>();
  forecastRow->setDirection(FlexDirection::Horizontal);
  forecastRow->setAlign(FlexAlign::Start);
  forecastRow->setGap(Style::spaceSm * scale);
  m_forecastRow = forecastRow.get();

  for (std::size_t i = 0; i < kDayCount; ++i) {
    auto card = std::make_unique<Flex>();
    applyCard(*card, scale);
    card->setAlign(FlexAlign::Center);
    card->setGap(Style::spaceXs * scale);
    card->setMinWidth(kForecastCardMinWidth * scale);
    m_dayCards[i] = card.get();

    auto name = std::make_unique<Label>();
    name->setText("Day");
    name->setBold(true);
    name->setFontSize(Style::fontSizeBody * scale);
    m_dayNames[i] = name.get();
    card->addChild(std::move(name));

    auto glyph = std::make_unique<Glyph>();
    glyph->setGlyph("weather-cloud");
    glyph->setGlyphSize(Style::fontSizeTitle * 2.25f * scale);
    glyph->setColor(palette.primary);
    m_dayGlyphs[i] = glyph.get();
    card->addChild(std::move(glyph));

    auto desc = std::make_unique<Label>();
    desc->setText("Weather");
    desc->setFontSize(Style::fontSizeBody * scale);
    desc->setColor(palette.onSurfaceVariant);
    desc->setMaxWidth((kForecastCardMinWidth - Style::spaceMd * 2) * scale);
    m_dayDescs[i] = desc.get();
    card->addChild(std::move(desc));

    auto temps = std::make_unique<Label>();
    temps->setText("-- / --");
    temps->setBold(true);
    temps->setFontSize(Style::fontSizeBody * scale);
    m_dayTemps[i] = temps.get();
    card->addChild(std::move(temps));

    forecastRow->addChild(std::move(card));
  }

  tab->addChild(std::move(forecastRow));
  return tab;
}

void WeatherTab::layout(Renderer& renderer, float contentWidth, float /*bodyHeight*/) {
  if (m_forecastRow == nullptr) {
    return;
  }

  const float scale = contentScale();
  const float gap = Style::spaceSm * scale;
  const float totalGap = gap * static_cast<float>(kDayCount - 1);
  const float cardWidth =
      std::max(kForecastCardMinWidth * scale, (contentWidth - totalGap) / static_cast<float>(kDayCount));
  for (auto* card : m_dayCards) {
    if (card != nullptr) {
      card->setMinWidth(cardWidth);
      card->layout(renderer);
    }
  }
  m_forecastRow->layout(renderer);
}

void WeatherTab::update(Renderer& renderer) { sync(renderer); }

void WeatherTab::onClose() {
  m_rootLayout = nullptr;
  m_forecastRow = nullptr;
  m_statusLabel = nullptr;
  m_currentGlyph = nullptr;
  m_locationLabel = nullptr;
  m_currentTempLabel = nullptr;
  m_currentDescLabel = nullptr;
  m_updatedLabel = nullptr;
  m_dayCards.fill(nullptr);
  m_dayGlyphs.fill(nullptr);
  m_dayNames.fill(nullptr);
  m_dayDescs.fill(nullptr);
  m_dayTemps.fill(nullptr);
}

void WeatherTab::sync(Renderer& renderer) {
  if (m_statusLabel == nullptr || m_currentGlyph == nullptr || m_locationLabel == nullptr || m_currentTempLabel == nullptr ||
      m_currentDescLabel == nullptr || m_updatedLabel == nullptr) {
    return;
  }

  if (m_weather == nullptr || !m_weather->enabled()) {
    m_locationLabel->setText("Weather disabled");
    m_currentTempLabel->setText("--°C");
    m_currentDescLabel->setText("Enable [weather] in config.toml");
    m_updatedLabel->setText(" ");
    m_statusLabel->setText(" ");
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
    m_updatedLabel->setText(" ");
    m_statusLabel->setText(" ");
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
    m_updatedLabel->setText(" ");
    m_statusLabel->setText(m_weather->error());
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
  m_statusLabel->setText(m_weather->loading() ? "Refreshing weather..." : m_weather->error());

  for (std::size_t i = 0; i < kDayCount; ++i) {
    const bool visible = i < snapshot.forecastDays.size();
    if (m_dayCards[i] != nullptr) {
      m_dayCards[i]->setVisible(visible);
    }
    if (!visible) {
      continue;
    }

    const auto& day = snapshot.forecastDays[i];
    m_dayNames[i]->setText(weekdayLabel(day.dateIso));
    m_dayGlyphs[i]->setGlyph(WeatherService::glyphForCode(day.weatherCode, true));
    m_dayDescs[i]->setText(WeatherService::shortDescriptionForCode(day.weatherCode));
    m_dayTemps[i]->setText(
        std::format("{} / {}{}",
                    static_cast<int>(std::lround(m_weather->displayTemperature(day.temperatureMaxC))),
                    static_cast<int>(std::lround(m_weather->displayTemperature(day.temperatureMinC))),
                    m_weather->displayTemperatureUnit()));
    m_dayNames[i]->measure(renderer);
    m_dayGlyphs[i]->measure(renderer);
    m_dayDescs[i]->measure(renderer);
    m_dayTemps[i]->measure(renderer);
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
