#include "ui/controls/spinner.h"

#include "render/animation/animation_manager.h"
#include "render/scene/spinner_node.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cmath>
#include <memory>

namespace {

constexpr float kDefaultSize = 20.0f;
constexpr float kDefaultThickness = 2.0f;
constexpr float kRevolutionMs = 800.0f;
constexpr float kTwoPi = 2.0f * 3.14159265358979f;

} // namespace

Spinner::Spinner() {
  m_paletteConn = paletteChanged().connect([this] { applyPalette(); });
  auto node = std::make_unique<SpinnerNode>();
  node->setThickness(kDefaultThickness);
  m_spinnerNode = static_cast<SpinnerNode*>(addChild(std::move(node)));
  m_spinnerSize = kDefaultSize;
  applyPalette();
  updateGeometry();
}

void Spinner::setColor(const ThemeColor& color) {
  m_color = color;
  applyPalette();
}

void Spinner::setColor(const Color& color) { setColor(fixedColor(color)); }

void Spinner::setSpinnerSize(float size) {
  m_spinnerSize = size;
  updateGeometry();
}

void Spinner::setThickness(float thickness) { m_spinnerNode->setThickness(thickness); }

void Spinner::start() {
  if (m_spinning) {
    return;
  }
  m_spinning = true;
  startLoop();
}

void Spinner::stop() {
  m_spinning = false;
  if (animationManager() != nullptr && m_animId != 0) {
    animationManager()->cancel(m_animId);
    m_animId = 0;
  }
}

void Spinner::applyPalette() {
  if (m_spinnerNode != nullptr) {
    m_spinnerNode->setColor(resolveThemeColor(m_color));
  }
}

void Spinner::startLoop() {
  if (animationManager() == nullptr || !m_spinning) {
    return;
  }

  m_animId = animationManager()->animate(
      0.0f, kTwoPi, kRevolutionMs, Easing::Linear,
      [this](float angle) {
        m_spinnerNode->setRotation(angle);
        markPaintDirty();
      },
      [this]() {
        m_animId = 0;
        if (m_spinning) {
          startLoop();
        }
      });
  markPaintDirty();
}

void Spinner::updateGeometry() {
  const float boxHeight = std::max(m_spinnerSize, Style::controlHeight);
  setSize(m_spinnerSize, boxHeight);
  m_spinnerNode->setFrameSize(m_spinnerSize, m_spinnerSize);
  m_spinnerNode->setPosition(0.0f, std::round((boxHeight - m_spinnerSize) * 0.5f));
}
