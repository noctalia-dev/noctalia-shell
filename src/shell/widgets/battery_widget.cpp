#include "shell/widgets/battery_widget.h"

#include "render/core/renderer.h"
#include "ui/controls/icon.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cmath>
#include <string>

namespace {

const char* batteryIconName(double percentage, BatteryState state) {
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

  auto icon = std::make_unique<Icon>();
  icon->setIcon("battery-full");
  icon->setIconSize(Style::fontSizeBody * m_contentScale);
  icon->setColor(palette.onSurface);
  m_icon = icon.get();
  container->addChild(std::move(icon));

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
  if (m_icon == nullptr || m_label == nullptr || rootNode == nullptr) {
    return;
  }

  m_icon->measure(renderer);
  m_label->measure(renderer);

  m_icon->setPosition(0.0f, 0.0f);
  m_label->setPosition(m_icon->width() + Style::spaceXs, 0.0f);

  rootNode->setSize(m_label->x() + m_label->width(), m_icon->height());
}

void BatteryWidget::update(Renderer& renderer) {
  syncState(renderer);
  Widget::update(renderer);
}

void BatteryWidget::syncState(Renderer& renderer) {
  if (m_upower == nullptr || m_icon == nullptr || m_label == nullptr) {
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
      rootNode->setSize(0.0f, 0.0f);
    }
    return;
  }

  m_icon->setIcon(batteryIconName(s.percentage, s.state));
  m_icon->setIconSize(Style::fontSizeBody * m_contentScale);
  m_icon->setColor(palette.onSurface);
  m_icon->measure(renderer);

  const int pct = static_cast<int>(std::round(s.percentage));
  m_label->setText(std::to_string(pct) + "%");
  m_label->measure(renderer);

  requestRedraw();
}
