#include "ui/controls/Spinner.h"

#include "render/scene/SpinnerNode.h"
#include "ui/style/Palette.h"
#include "ui/style/Style.h"

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
  setSize(kDefaultSize, Style::controlHeight);
  m_spinnerNode->setSize(kDefaultSize, kDefaultSize);
  m_spinnerNode->setPosition(0.0f, (Style::controlHeight - kDefaultSize) * 0.5f);
}

void Spinner::setColor(const Color& color) { m_spinnerNode->setColor(color); }

void Spinner::setSpinnerSize(float size) {
  setSize(size, size);
  m_spinnerNode->setSize(size, size);
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
  if (m_animations != nullptr && m_animId != 0) {
    m_animations->cancel(m_animId);
    m_animId = 0;
  }
}

void Spinner::startLoop() {
  if (m_animations == nullptr || !m_spinning) {
    return;
  }

  m_animId = m_animations->animate(
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
