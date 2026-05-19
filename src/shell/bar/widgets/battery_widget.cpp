#include "shell/bar/widgets/battery_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "ui/controls/box.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <chrono>
#include <cmath>
#include <string>
#include <utility>

namespace {

  const char* batteryGlyphName(double percentage, BatteryState state) {
    if (state == BatteryState::Charging) {
      return "battery-charging";
    }
    if (state == BatteryState::FullyCharged || state == BatteryState::PendingCharge) {
      return "battery-plugged";
    }
    if (state == BatteryState::Unknown) {
      return "battery-exclamation";
    }
    if (percentage >= 85.0) {
      return "battery-4";
    }
    if (percentage >= 55.0) {
      return "battery-3";
    }
    if (percentage >= 30.0) {
      return "battery-2";
    }
    if (percentage >= 10.0) {
      return "battery-1";
    }
    return "battery-0";
  }

  const char* batteryStateGlyph(BatteryState state) {
    if (state == BatteryState::Charging) {
      return "bolt-filled";
    }
    if (state == BatteryState::FullyCharged || state == BatteryState::PendingCharge) {
      return "plug-filled";
    }
    return nullptr;
  }

} // namespace

BatteryWidget::BatteryWidget(UPowerService* upower, std::string deviceSelector, int warningThreshold,
                             ColorSpec warningColor, BatteryDisplayMode displayMode, bool showLabel)
    : m_upower(upower), m_deviceSelector(std::move(deviceSelector)), m_warningThreshold(warningThreshold),
      m_warningColor(std::move(warningColor)), m_displayMode(displayMode), m_showLabel(showLabel) {}

void BatteryWidget::create() {
  auto container = std::make_unique<InputArea>();
  setRoot(std::move(container));

  if (m_displayMode == BatteryDisplayMode::Graphic) {
    createGraphicMode();
  } else {
    createIconMode();
  }
}

void BatteryWidget::createGraphicMode() {
  auto* container = static_cast<InputArea*>(root());

  auto bodyBg = std::make_unique<Box>();
  bodyBg->setFill(colorSpecFromRole(ColorRole::OnSurface, 0.25f));
  m_bodyBg = bodyBg.get();
  container->addChild(std::move(bodyBg));

  auto fillRect = std::make_unique<Box>();
  m_fillRect = fillRect.get();
  container->addChild(std::move(fillRect));

  auto terminalNub = std::make_unique<Box>();
  terminalNub->setFill(colorSpecFromRole(ColorRole::OnSurface, 0.25f));
  m_terminalNub = terminalNub.get();
  container->addChild(std::move(terminalNub));

  if (m_showLabel) {
    auto overlayLabel = std::make_unique<Label>();
    overlayLabel->setBold(true);
    overlayLabel->setColor(colorSpecFromRole(ColorRole::Surface, 0.75f));
    m_overlayLabel = overlayLabel.get();
    container->addChild(std::move(overlayLabel));
  }

  auto overlayGlyph = std::make_unique<Glyph>();
  overlayGlyph->setColor(colorSpecFromRole(ColorRole::Surface, 0.75f));
  overlayGlyph->setVisible(false);
  m_overlayGlyph = overlayGlyph.get();
  container->addChild(std::move(overlayGlyph));
}

void BatteryWidget::createIconMode() {
  auto* container = static_cast<InputArea*>(root());

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("battery-4");
  glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
  glyph->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
  m_glyph = glyph.get();
  container->addChild(std::move(glyph));

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  label->setVisible(m_showLabel);
  m_label = label.get();
  container->addChild(std::move(label));
}

void BatteryWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  auto* rootNode = root();
  if (rootNode == nullptr) {
    return;
  }
  m_isVertical = containerHeight > containerWidth;
  syncState(renderer);

  if (m_displayMode == BatteryDisplayMode::Graphic) {
    layoutGraphicMode(renderer);
  } else {
    layoutIconMode(renderer, containerWidth, containerHeight);
  }
}

void BatteryWidget::layoutGraphicMode(Renderer& renderer) {
  auto* rootNode = root();
  if (m_bodyBg == nullptr || m_fillRect == nullptr || m_terminalNub == nullptr || rootNode == nullptr) {
    return;
  }

  const float scale = (Style::fontSizeBody / 14.0f) * m_contentScale;
  const int pct = static_cast<int>(std::round(m_animatedPct));
  const float bodyW = std::round((pct > 99 ? 30.0f : 22.0f) * scale);
  const float bodyH = std::round(14.0f * scale);
  const float termW = std::round(2.5f * scale);
  const float termH = std::round(7.0f * scale);
  const float cornerR = std::round(3.0f * scale);

  if (m_isVertical) {
    m_bodyBg->setRadius(cornerR);
    m_bodyBg->setPosition(0.0f, termW);
    m_bodyBg->setSize(bodyH, bodyW);

    m_terminalNub->setRadius(cornerR * 0.5f);
    m_terminalNub->setPosition(std::round((bodyH - termH) * 0.5f), 0.0f);
    m_terminalNub->setSize(termH, termW);

    m_fillRect->setRadius(cornerR);
    updateFillGeometry();

    if (m_overlayLabel != nullptr && m_showLabel) {
      m_overlayLabel->setFontSize(std::round(Style::fontSizeBody * scale * 0.65f));
      m_overlayLabel->measure(renderer);
      m_overlayLabel->setPosition(std::round((bodyH - m_overlayLabel->width()) * 0.5f),
                                  termW + std::round((bodyW - m_overlayLabel->height()) * 0.5f));
    }

    if (m_overlayGlyph != nullptr) {
      const float glyphSize = std::round(Style::fontSizeBody * scale);
      m_overlayGlyph->setGlyphSize(glyphSize);
      m_overlayGlyph->measure(renderer);
      m_overlayGlyph->setPosition(std::round((bodyH - m_overlayGlyph->width()) * 0.5f),
                                  termW + std::round((bodyW - m_overlayGlyph->height()) * 0.5f));
    }

    rootNode->setSize(bodyH, bodyW + termW);
  } else {
    m_bodyBg->setRadius(cornerR);
    m_bodyBg->setPosition(0.0f, 0.0f);
    m_bodyBg->setSize(bodyW, bodyH);

    m_terminalNub->setRadius(cornerR * 0.5f);
    m_terminalNub->setPosition(bodyW, std::round((bodyH - termH) * 0.5f));
    m_terminalNub->setSize(termW, termH);

    m_fillRect->setRadius(cornerR);
    updateFillGeometry();

    if (m_overlayLabel != nullptr && m_showLabel) {
      m_overlayLabel->setFontSize(std::round(Style::fontSizeBody * scale * 0.65f));
      m_overlayLabel->measure(renderer);
      m_overlayLabel->setPosition(std::round((bodyW - m_overlayLabel->width()) * 0.5f),
                                  std::round((bodyH - m_overlayLabel->height()) * 0.5f));
    }

    if (m_overlayGlyph != nullptr) {
      const float glyphSize = std::round(Style::fontSizeBody * scale);
      m_overlayGlyph->setGlyphSize(glyphSize);
      m_overlayGlyph->measure(renderer);
      m_overlayGlyph->setPosition(std::round((bodyW - m_overlayGlyph->width()) * 0.5f),
                                  std::round((bodyH - m_overlayGlyph->height()) * 0.5f));
    }

    rootNode->setSize(bodyW + termW, bodyH);
  }
}

void BatteryWidget::layoutIconMode(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (m_glyph == nullptr || rootNode == nullptr) {
    return;
  }

  m_glyph->measure(renderer);

  if (m_label != nullptr && m_showLabel) {
    m_label->measure(renderer);

    if (m_isVertical) {
      const float w = std::max(m_glyph->width(), m_label->width());
      m_glyph->setPosition(std::round((w - m_glyph->width()) * 0.5f), 0.0f);
      m_label->setPosition(std::round((w - m_label->width()) * 0.5f), m_glyph->height());
      rootNode->setSize(w, m_glyph->height() + m_label->height());
    } else {
      const float h = std::max(m_glyph->height(), m_label->height());
      m_glyph->setPosition(0.0f, std::round((h - m_glyph->height()) * 0.5f));
      m_label->setPosition(m_glyph->width() + Style::spaceXs, std::round((h - m_label->height()) * 0.5f));
      rootNode->setSize(m_label->x() + m_label->width(), h);
    }
  } else {
    rootNode->setSize(m_glyph->width(), m_glyph->height());
  }
}

void BatteryWidget::updateFillGeometry() {
  if (m_fillRect == nullptr || m_bodyBg == nullptr) {
    return;
  }

  const float fraction = std::clamp(m_animatedPct / 100.0f, 0.0f, 1.0f);

  if (m_isVertical) {
    const float bodyW = m_bodyBg->width();
    const float bodyH = m_bodyBg->height();
    const float termW = m_terminalNub != nullptr ? m_terminalNub->height() : 0.0f;
    const float fillH = bodyH * fraction;
    m_fillRect->setPosition(0.0f, termW + bodyH - fillH);
    m_fillRect->setSize(bodyW, fillH);
  } else {
    const float bodyW = m_bodyBg->width();
    const float bodyH = m_bodyBg->height();
    const float fillW = bodyW * fraction;
    m_fillRect->setPosition(0.0f, 0.0f);
    m_fillRect->setSize(fillW, bodyH);
  }
}

void BatteryWidget::doUpdate(Renderer& renderer) { syncState(renderer); }

void BatteryWidget::onFrameTick(float /*deltaMs*/) { requestRedraw(); }

bool BatteryWidget::needsFrameTick() const { return m_displayMode == BatteryDisplayMode::Graphic && m_fillAnim != 0; }

void BatteryWidget::syncState(Renderer& renderer) {
  if (m_upower == nullptr) {
    return;
  }

  const auto s = m_upower->stateForDevice(m_deviceSelector);

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
    m_alternateTimer.stop();
    return;
  }

  if (rootNode != nullptr) {
    rootNode->setVisible(true);
  }

  const int pct = static_cast<int>(std::round(s.percentage));
  const bool isCharging = s.state == BatteryState::Charging || s.state == BatteryState::FullyCharged ||
                          s.state == BatteryState::PendingCharge;
  const bool isWarning = m_warningThreshold > 0 && pct <= m_warningThreshold && !isCharging;
  const ColorSpec fgColor = isWarning ? m_warningColor : widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface));

  if (m_displayMode == BatteryDisplayMode::Graphic) {
    // Fill color
    ColorSpec fillColor = colorSpecFromRole(ColorRole::OnSurface);
    if (s.state == BatteryState::Charging) {
      fillColor = colorSpecFromRole(ColorRole::Primary);
    } else if (isWarning) {
      fillColor = m_warningColor;
    }
    if (m_fillRect != nullptr) {
      m_fillRect->setFill(fillColor);
    }

    // Terminal nub color
    if (m_terminalNub != nullptr) {
      m_terminalNub->setFill(isWarning ? m_warningColor : colorSpecFromRole(ColorRole::OnSurface, 0.25f));
    }

    // Animate fill percentage
    const auto newPct = static_cast<float>(s.percentage);
    if (m_animations != nullptr && std::abs(m_animatedPct - newPct) > 0.5f) {
      m_animations->cancel(m_fillAnim);
      m_fillAnim = m_animations->animate(
          m_animatedPct, newPct, static_cast<float>(Style::animNormal), Easing::EaseOutCubic,
          [this](float v) {
            m_animatedPct = v;
            updateFillGeometry();
            requestRedraw();
          },
          [this]() { m_fillAnim = 0; }, this);
      requestFrameTick();
    } else {
      m_animatedPct = newPct;
      updateFillGeometry();
    }

    // Overlay label
    if (m_overlayLabel != nullptr && m_showLabel) {
      m_overlayLabel->setText(m_isVertical ? std::to_string(pct) : std::to_string(pct) + "%");
      m_overlayLabel->measure(renderer);
    }

    // Overlay glyph — state icon
    const char* stateGlyph = batteryStateGlyph(s.state);
    if (m_overlayGlyph != nullptr) {
      if (stateGlyph != nullptr) {
        m_overlayGlyph->setGlyph(stateGlyph);
      }
    }

    // Charging alternation timer
    if (s.state == BatteryState::Charging && m_showLabel) {
      if (!m_alternateTimer.active()) {
        m_showStateIcon = false;
        m_alternateTimer.startRepeating(std::chrono::milliseconds(4000), [this]() {
          m_showStateIcon = !m_showStateIcon;
          if (m_overlayLabel != nullptr) {
            m_overlayLabel->setVisible(!m_showStateIcon);
          }
          if (m_overlayGlyph != nullptr) {
            m_overlayGlyph->setVisible(m_showStateIcon);
          }
          requestRedraw();
        });
      }
    } else {
      m_alternateTimer.stop();
      m_showStateIcon = false;

      const bool plugged = s.state == BatteryState::FullyCharged || s.state == BatteryState::PendingCharge;
      if (m_overlayLabel != nullptr) {
        m_overlayLabel->setVisible(m_showLabel && !plugged);
      }
      if (m_overlayGlyph != nullptr) {
        m_overlayGlyph->setVisible(plugged || (stateGlyph != nullptr && !m_showLabel));
      }
    }
  } else {
    // Icon mode — existing behavior
    if (m_glyph != nullptr) {
      m_glyph->setGlyph(batteryGlyphName(s.percentage, s.state));
      m_glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
      m_glyph->setColor(fgColor);
      m_glyph->measure(renderer);
    }

    if (m_label != nullptr && m_showLabel) {
      m_label->setFontSize((m_isVertical ? Style::fontSizeCaption : Style::fontSizeBody) * m_contentScale);
      m_label->setText(m_isVertical ? std::to_string(pct) : std::to_string(pct) + "%");
      m_label->setColor(fgColor);
      m_label->measure(renderer);
    }
  }

  // Tooltip (both modes)
  if (rootNode != nullptr) {
    std::vector<TooltipRow> rows;
    for (const auto& dev : m_upower->batteryDevices()) {
      std::string name = !dev.model.empty() ? dev.model : (!dev.nativePath.empty() ? dev.nativePath : "Battery");
      int dp = static_cast<int>(std::round(dev.state.percentage));
      rows.push_back({std::move(name), std::to_string(dp) + "%"});
    }
    if (!rows.empty()) {
      static_cast<InputArea*>(rootNode)->setTooltip(std::move(rows));
    } else {
      static_cast<InputArea*>(rootNode)->clearTooltip();
    }
  }

  requestRedraw();
}
