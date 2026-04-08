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
  auto node = std::make_unique<SpinnerNode>();
  node->setColor(palette.primary);
  node->setThickness(kDefaultThickness);
  m_spinnerNode = static_cast<SpinnerNode*>(addChild(std::move(node)));
  m_spinnerSize = kDefaultSize;
  updateGeometry();
}

void Spinner::setColor(const Color& color) { m_spinnerNode->setColor(color); }

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

void Spinner::startLoop() {
  if (animationManager() == nullptr || !m_spinning) {
    return;
  }

  m_animId = animationManager()->animate(
      0.0f, kTwoPi, kRevolutionMs, Easing::Linear,
      [this](float angle) {
        m_spinnerNode->setRotation(angle);
        markDirty();
      },
      [this]() {
        m_animId = 0;
        if (m_spinning) {
          startLoop();
        }
      });
  markDirty();
}

void Spinner::updateGeometry() {
  const float boxHeight = std::max(m_spinnerSize, Style::controlHeight);
  setSize(m_spinnerSize, boxHeight);
  m_spinnerNode->setSize(m_spinnerSize, m_spinnerSize);
  m_spinnerNode->setPosition(0.0f, std::round((boxHeight - m_spinnerSize) * 0.5f));
}
