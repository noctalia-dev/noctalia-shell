#include "shell/widgets/battery_widget.h"

#include "render/core/renderer.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cmath>
#include <string>

namespace {

const char* batteryGlyphName(double percentage, BatteryState state) {
  if (state == BatteryState::Charging || state == BatteryState::PendingCharge) {
    return "battery-charging";
  }
  if (state == BatteryState::FullyCharged) {
    return "battery-plugged";
  }
  if (state == BatteryState::Unknown) {
    return "battery-exclamation";
  }
  if (percentage >= 80.0) {
    return "battery-4";
  }
  if (percentage >= 60.0) {
    return "battery-3";
  }
  if (percentage >= 40.0) {
    return "battery-2";
  }
  if (percentage >= 20.0) {
    return "battery-1";
  }
  return "battery-0";
}

} // namespace

BatteryWidget::BatteryWidget(UPowerService* upower) : m_upower(upower) {}

void BatteryWidget::create(Renderer& renderer) {
  auto container = std::make_unique<Node>();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("battery-4");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(palette.onSurface);
  m_glyph = glyph.get();
  container->addChild(std::move(glyph));

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  m_label = label.get();
  container->addChild(std::move(label));

  m_root = std::move(container);
  syncState(renderer);
}

void BatteryWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (m_glyph == nullptr || m_label == nullptr || rootNode == nullptr) {
    return;
  }

  m_glyph->measure(renderer);
  m_label->measure(renderer);

  m_glyph->setPosition(0.0f, 0.0f);
  m_label->setPosition(m_glyph->width() + Style::spaceXs, 0.0f);

  rootNode->setSize(m_label->x() + m_label->width(), m_glyph->height());
}

void BatteryWidget::update(Renderer& renderer) {
  syncState(renderer);
  Widget::update(renderer);
}

void BatteryWidget::syncState(Renderer& renderer) {
  if (m_upower == nullptr || m_glyph == nullptr || m_label == nullptr) {
    return;
  }

  const auto& s = m_upower->state();

  if (s.percentage == m_lastPct && s.state == m_lastState && s.isPresent == m_lastPresent) {
    return;
  }

  m_lastPct = s.percentage;
  m_lastState = s.state;
  m_lastPresent = s.isPresent;

  auto* rootNode = root();
  if (!s.isPresent) {
    if (rootNode != nullptr) {
      rootNode->setVisible(false);
      rootNode->setSize(0.0f, 0.0f);
    }
    return;
  }

  if (rootNode != nullptr) {
    rootNode->setVisible(true);
  }

  m_glyph->setGlyph(batteryGlyphName(s.percentage, s.state));
  m_glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  m_glyph->setColor(palette.onSurface);
  m_glyph->measure(renderer);

  const int pct = static_cast<int>(std::round(s.percentage));
  m_label->setText(std::to_string(pct) + "%");
  m_label->measure(renderer);

  requestRedraw();
}
