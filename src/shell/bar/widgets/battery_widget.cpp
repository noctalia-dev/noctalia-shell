#include "shell/bar/widgets/battery_widget.h"

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

void BatteryWidget::create() {
  auto container = std::make_unique<Node>();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("battery-4");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_glyph = glyph.get();
  container->addChild(std::move(glyph));

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  m_label = label.get();
  container->addChild(std::move(label));

  setRoot(std::move(container));
}

void BatteryWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  auto* rootNode = root();
  if (m_glyph == nullptr || m_label == nullptr || rootNode == nullptr) {
    return;
  }
  m_isVertical = containerHeight > containerWidth;
  syncState(renderer);

  m_glyph->measure(renderer);
  m_label->measure(renderer);

  if (m_isVertical) {
    const float w = std::max(m_glyph->width(), m_label->width());
    m_glyph->setPosition(std::round((w - m_glyph->width()) * 0.5f), 0.0f);
    m_label->setPosition(std::round((w - m_label->width()) * 0.5f), m_glyph->height());
    rootNode->setSize(w, m_glyph->height() + m_label->height());
  } else {
    m_glyph->setPosition(0.0f, 0.0f);
    m_label->setPosition(m_glyph->width() + Style::spaceXs, 0.0f);
    rootNode->setSize(m_label->x() + m_label->width(), m_glyph->height());
  }
}

void BatteryWidget::doUpdate(Renderer& renderer) { syncState(renderer); }

void BatteryWidget::syncState(Renderer& renderer) {
  if (m_upower == nullptr || m_glyph == nullptr || m_label == nullptr) {
    return;
  }

  const auto& s = m_upower->state();

  if (s.percentage == m_lastPct && s.state == m_lastState && s.isPresent == m_lastPresent &&
      m_isVertical == m_lastVertical) {
    return;
  }

  m_lastPct = s.percentage;
  m_lastState = s.state;
  m_lastPresent = s.isPresent;
  m_lastVertical = m_isVertical;

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
  m_glyph->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_glyph->measure(renderer);

  const int pct = static_cast<int>(std::round(s.percentage));
  m_label->setFontSize((m_isVertical ? Style::fontSizeCaption : Style::fontSizeBody) * m_contentScale);
  m_label->setText(m_isVertical ? std::to_string(pct) : std::to_string(pct) + "%");
  m_label->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_label->measure(renderer);

  requestRedraw();
}
