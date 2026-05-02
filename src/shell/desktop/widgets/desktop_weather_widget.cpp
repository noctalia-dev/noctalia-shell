#include "shell/desktop/widgets/desktop_weather_widget.h"

#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "system/weather_service.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <format>
#include <memory>

namespace {

  float temperatureFontSize(float contentScale) { return Style::fontSizeBody * 2.25f * contentScale; }
  float conditionFontSize(float contentScale) { return Style::fontSizeBody * contentScale; }
  float glyphFontSize(float contentScale) { return Style::fontSizeBody * 3.0f * contentScale; }
  float columnSpacing(float contentScale) { return Style::spaceSm * contentScale; }
  float stackedLineGap(float contentScale) { return -Style::fontSizeBody * 0.5f * contentScale; }

} // namespace

namespace {

  constexpr float kShadowAlpha = 0.6f;
  constexpr float kShadowOffset = 1.5f;

} // namespace

DesktopWeatherWidget::DesktopWeatherWidget(const WeatherService* weather, ColorSpec color, bool shadow)
    : m_weather(weather), m_color(std::move(color)), m_shadow(shadow) {}

void DesktopWeatherWidget::create() {
  auto rootNode = std::make_unique<Node>();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("weather-cloud");
  glyph->setGlyphSize(glyphFontSize(contentScale()));
  glyph->setColor(m_color);
  m_glyph = glyph.get();
  rootNode->addChild(std::move(glyph));

  auto temperature = std::make_unique<Label>();
  temperature->setBold(true);
  temperature->setTextAlign(TextAlign::Start);
  temperature->setStableBaseline(true);
  temperature->setFontSize(temperatureFontSize(contentScale()));
  temperature->setColor(m_color);
  m_temperature = temperature.get();
  rootNode->addChild(std::move(temperature));

  auto condition = std::make_unique<Label>();
  condition->setTextAlign(TextAlign::Start);
  condition->setStableBaseline(true);
  condition->setFontSize(conditionFontSize(contentScale()));
  condition->setColor(m_color);
  m_condition = condition.get();
  rootNode->addChild(std::move(condition));

  setRoot(std::move(rootNode));
  applyShadow();
}

void DesktopWeatherWidget::doLayout(Renderer& renderer) {
  if (root() == nullptr || m_glyph == nullptr || m_temperature == nullptr || m_condition == nullptr) {
    return;
  }

  m_temperature->setFontSize(temperatureFontSize(contentScale()));
  m_condition->setFontSize(conditionFontSize(contentScale()));
  m_glyph->setGlyphSize(glyphFontSize(contentScale()));
  applyShadow();

  sync(renderer);

  m_temperature->measure(renderer);
  m_condition->measure(renderer);
  m_glyph->measure(renderer);

  const bool hasCondition = !m_condition->text().empty();
  const float lineGap = hasCondition ? stackedLineGap(contentScale()) : 0.0f;

  float textWidth = m_temperature->width();
  float textHeight = m_temperature->height();
  if (hasCondition) {
    textWidth = std::max(textWidth, m_condition->width());
    textHeight += lineGap + m_condition->height();
  }

  const float hSpacing = std::round(columnSpacing(contentScale()));
  const float totalHeight = std::round(std::max(m_glyph->height(), textHeight));
  const float totalWidth = std::round(m_glyph->width() + hSpacing + textWidth);

  m_glyph->setPosition(0.0f, std::round((totalHeight - m_glyph->height()) * 0.5f));

  const float textColX = m_glyph->width() + hSpacing;
  float y = std::round((totalHeight - textHeight) * 0.5f);
  m_temperature->setPosition(textColX, y);
  y += std::round(m_temperature->height() + lineGap);

  if (hasCondition) {
    m_condition->setPosition(textColX, y);
  }

  root()->setSize(totalWidth, totalHeight);
}

void DesktopWeatherWidget::doUpdate(Renderer& renderer) { sync(renderer); }

void DesktopWeatherWidget::applyShadow() {
  if (m_glyph == nullptr || m_temperature == nullptr || m_condition == nullptr) {
    return;
  }
  if (m_shadow) {
    const float offset = kShadowOffset * contentScale();
    const Color shadow(0.0f, 0.0f, 0.0f, kShadowAlpha);
    m_glyph->setShadow(shadow, offset, offset);
    m_temperature->setShadow(shadow, offset, offset);
    m_condition->setShadow(shadow, offset, offset);
  } else {
    m_glyph->clearShadow();
    m_temperature->clearShadow();
    m_condition->clearShadow();
  }
}

void DesktopWeatherWidget::sync(Renderer& renderer) {
  if (m_glyph == nullptr || m_temperature == nullptr || m_condition == nullptr) {
    return;
  }

  std::string glyphName = "weather-cloud";
  std::string temperatureText = "--";
  std::string conditionText;

  if (m_weather == nullptr || !m_weather->enabled()) {
    temperatureText = i18n::tr("desktop-widgets.weather.off");
  } else if (!m_weather->locationConfigured()) {
    temperatureText = i18n::tr("desktop-widgets.weather.no-location");
  } else if (m_weather->hasData()) {
    const auto& snapshot = m_weather->snapshot();
    glyphName = WeatherService::glyphForCode(snapshot.current.weatherCode, snapshot.current.isDay);
    const int temp = static_cast<int>(std::lround(m_weather->displayTemperature(snapshot.current.temperatureC)));
    temperatureText = std::format("{}{}", temp, m_weather->displayTemperatureUnit());
    conditionText = WeatherService::shortDescriptionForCode(snapshot.current.weatherCode);
  } else if (m_weather->loading()) {
    temperatureText = i18n::tr("desktop-widgets.weather.loading");
  } else if (!m_weather->error().empty()) {
    temperatureText = i18n::tr("desktop-widgets.weather.error");
  }

  bool changed = false;

  if (glyphName != m_lastGlyph) {
    m_lastGlyph = glyphName;
    m_glyph->setGlyph(glyphName);
    m_glyph->measure(renderer);
    changed = true;
  }

  if (temperatureText != m_lastTemperature) {
    m_lastTemperature = temperatureText;
    m_temperature->setText(temperatureText);
    m_temperature->measure(renderer);
    changed = true;
  }

  if (conditionText != m_lastCondition) {
    m_lastCondition = conditionText;
    m_condition->setText(conditionText);
    m_condition->measure(renderer);
    changed = true;
  }

  if (changed) {
    requestRedraw();
  }
}
