#include "render/scene/input_dispatcher.h"

#include "render/scene/input_area.h"
#include "render/scene/node.h"

void InputDispatcher::setSceneRoot(Node* root) {
  if (root == nullptr) {
    if (m_focusedArea != nullptr) {
      m_focusedArea->dispatchFocusLoss();
      m_focusedArea = nullptr;
    }
  }
  m_sceneRoot = root;
}

void InputDispatcher::setCursorShapeCallback(CursorShapeCallback callback) {
  m_cursorShapeCallback = std::move(callback);
}

void InputDispatcher::pointerEnter(float x, float y, std::uint32_t serial) {
  m_lastSerial = serial;
  updateHover(x, y, serial);
}

void InputDispatcher::pointerLeave() {
  m_capturedArea = nullptr;
  if (m_hoveredArea != nullptr) {
    m_hoveredArea->dispatchLeave();
    m_hoveredArea = nullptr;
  }
}

void InputDispatcher::pointerMotion(float x, float y, std::uint32_t serial) {
  if (serial != 0) {
    m_lastSerial = serial;
  }
  updateHover(x, y, m_lastSerial);
}

bool InputDispatcher::pointerButton(float x, float y, std::uint32_t button, bool pressed) {
  InputArea* target = m_capturedArea != nullptr ? m_capturedArea : m_hoveredArea;
  if (target != nullptr) {
    float absX = 0.0f, absY = 0.0f;
    Node::absolutePosition(target, absX, absY);
    target->dispatchPress(x - absX, y - absY, button, pressed);
    if (pressed) {
      m_capturedArea = target;
      if (target->focusable()) {
        setFocus(target);
      }
    } else {
      m_capturedArea = nullptr;
      updateHover(x, y, m_lastSerial);
    }
    return true;
  }
  if (pressed) {
    setFocus(nullptr);
  }
  return false;
}

bool InputDispatcher::pointerAxis(float x, float y, std::uint32_t axis, double value, std::int32_t discrete) {
  InputArea* target = m_capturedArea != nullptr ? m_capturedArea : m_hoveredArea;
  if (target == nullptr) {
    return false;
  }

  float absX = 0.0f;
  float absY = 0.0f;
  Node::absolutePosition(target, absX, absY);
  target->dispatchAxis(x - absX, y - absY, axis, value, discrete);
  return true;
}

void InputDispatcher::keyEvent(std::uint32_t sym, std::uint32_t utf32, std::uint32_t modifiers, bool pressed,
                               bool preedit) {
  if (m_focusedArea != nullptr) {
    m_focusedArea->dispatchKey(sym, utf32, modifiers, pressed, preedit);
  }
}

void InputDispatcher::setFocus(InputArea* area) {
  if (area == m_focusedArea) {
    return;
  }
  if (m_focusedArea != nullptr) {
    m_focusedArea->dispatchFocusLoss();
  }
  m_focusedArea = area;
  if (m_focusedArea != nullptr) {
    trackArea(m_focusedArea);
    m_focusedArea->dispatchFocusGain();
  }
}

InputArea* InputDispatcher::findInputAreaAt(float x, float y) {
  if (m_sceneRoot == nullptr) {
    return nullptr;
  }

  auto* hitNode = Node::hitTest(m_sceneRoot, x, y);
  if (hitNode == nullptr) {
    return nullptr;
  }

  for (auto* node = hitNode; node != nullptr; node = node->parent()) {
    auto* area = dynamic_cast<InputArea*>(node);
    if (area != nullptr && area->enabled()) {
      return area;
    }
  }

  return nullptr;
}

void InputDispatcher::updateHover(float x, float y, std::uint32_t serial) {
  // While a button is held, all motion goes to the captured area; hover stays frozen.
  if (m_capturedArea != nullptr) {
    float absX = 0.0f, absY = 0.0f;
    Node::absolutePosition(m_capturedArea, absX, absY);
    m_capturedArea->dispatchMotion(x - absX, y - absY);
    updateCursor(serial);
    return;
  }

  auto* area = findInputAreaAt(x, y);

  if (area != m_hoveredArea) {
    if (m_hoveredArea != nullptr) {
      m_hoveredArea->dispatchLeave();
    }
    m_hoveredArea = area;
    if (m_hoveredArea != nullptr) {
      trackArea(m_hoveredArea);
      float absX = 0.0f, absY = 0.0f;
      Node::absolutePosition(m_hoveredArea, absX, absY);
      m_hoveredArea->dispatchEnter(x - absX, y - absY);
    }
  } else if (m_hoveredArea != nullptr) {
    float absX = 0.0f, absY = 0.0f;
    Node::absolutePosition(m_hoveredArea, absX, absY);
    m_hoveredArea->dispatchMotion(x - absX, y - absY);
  }

  updateCursor(serial);
}

void InputDispatcher::trackArea(InputArea* area) {
  area->setDestroyCallback([this](InputArea* a) {
    if (m_hoveredArea == a) {
      m_hoveredArea = nullptr;
    }
    if (m_focusedArea == a) {
      m_focusedArea = nullptr;
    }
    if (m_capturedArea == a) {
      m_capturedArea = nullptr;
    }
  });
}

void InputDispatcher::updateCursor(std::uint32_t serial) {
  if (!m_cursorShapeCallback) {
    return;
  }

  std::uint32_t shape = 1; // Default arrow

  if (m_hoveredArea != nullptr) {
    auto areaShape = m_hoveredArea->cursorShape();
    if (areaShape != 0) {
      shape = areaShape;
    }
  }

  m_cursorShapeCallback(serial, shape);
}
