#include "shell/widgets/weather_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "system/weather_service.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <format>
#include <memory>

WeatherWidget::WeatherWidget(WeatherService* weather, wl_output* output, std::int32_t scale, float maxWidth,
                             bool showCondition)
    : m_weather(weather), m_output(output), m_scale(scale), m_maxWidth(maxWidth), m_showCondition(showCondition) {}

void WeatherWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    PanelManager::instance().togglePanel("control-center", m_output, m_scale, 0.0f, 0.0f, "weather");
  });
  m_area = area.get();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("weather-cloud");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(palette.primary);
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  label->setMaxWidth(m_maxWidth * m_contentScale);
  m_label = label.get();
  area->addChild(std::move(label));

  m_root = std::move(area);
}

void WeatherWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  if (m_glyph == nullptr || m_label == nullptr || root() == nullptr) {
    return;
  }
  sync(renderer);

  m_glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  m_glyph->measure(renderer);
  m_label->setMaxWidth(m_maxWidth * m_contentScale);
  m_label->measure(renderer);

  const float spacing = m_label->text().empty() ? 0.0f : Style::spaceXs;
  const float contentHeight = std::max(m_glyph->height(), m_label->height());
  const float glyphY = std::round((contentHeight - m_glyph->height()) * 0.5f);
  const float labelY = std::round((contentHeight - m_label->height()) * 0.5f);
  m_glyph->setPosition(0.0f, glyphY);
  m_label->setPosition(m_glyph->width() + spacing, labelY);
  root()->setSize(m_label->x() + m_label->width(), contentHeight);
}

void WeatherWidget::update(Renderer& renderer) {
  sync(renderer);
  Widget::update(renderer);
}

void WeatherWidget::sync(Renderer& renderer) {
  if (m_glyph == nullptr || m_label == nullptr) {
    return;
  }

  std::string glyph = "weather-cloud";
  std::string text = "Weather";

  if (m_weather == nullptr || !m_weather->enabled()) {
    text = "Weather off";
  } else if (!m_weather->locationConfigured()) {
    text = "No location";
  } else if (m_weather->hasData()) {
    const auto& snapshot = m_weather->snapshot();
    glyph = WeatherService::glyphForCode(snapshot.current.weatherCode, snapshot.current.isDay);
    text = std::format("{}{}",
                       static_cast<int>(std::lround(m_weather->displayTemperature(snapshot.current.temperatureC))),
                       m_weather->displayTemperatureUnit());
    if (m_showCondition) {
      text += " ";
      text += WeatherService::shortDescriptionForCode(snapshot.current.weatherCode);
    }
  } else if (m_weather->loading()) {
    text = "Weather...";
  } else if (!m_weather->error().empty()) {
    text = "Weather err";
  }

  bool changed = false;

  if (glyph != m_lastGlyph) {
    m_lastGlyph = glyph;
    m_glyph->setGlyph(glyph);
    m_glyph->measure(renderer);
    changed = true;
  }

  if (text != m_lastText) {
    m_lastText = text;
    m_label->setText(text);
    m_label->measure(renderer);
    changed = true;
  }

  if (changed) {
    requestRedraw();
  }
}
