#include "render/scene/InputDispatcher.h"

#include "render/scene/InputArea.h"
#include "render/scene/Node.h"

void InputDispatcher::setSceneRoot(Node* root) { m_sceneRoot = root; }

void InputDispatcher::setCursorShapeCallback(CursorShapeCallback callback) {
  m_cursorShapeCallback = std::move(callback);
}

void InputDispatcher::pointerEnter(float x, float y, std::uint32_t serial) {
  m_lastSerial = serial;
  updateHover(x, y, serial);
}

void InputDispatcher::pointerLeave() {
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

void InputDispatcher::pointerButton(float x, float y, std::uint32_t button, bool pressed) {
  if (m_hoveredArea != nullptr) {
    float absX = 0.0f, absY = 0.0f;
    Node::absolutePosition(m_hoveredArea, absX, absY);
    m_hoveredArea->dispatchPress(x - absX, y - absY, button, pressed);
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
  auto* area = findInputAreaAt(x, y);

  if (area != m_hoveredArea) {
    if (m_hoveredArea != nullptr) {
      m_hoveredArea->dispatchLeave();
    }
    m_hoveredArea = area;
    if (m_hoveredArea != nullptr) {
      m_hoveredArea->setDestroyCallback([this](InputArea* a) {
        if (m_hoveredArea == a) {
          m_hoveredArea = nullptr;
        }
      });
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
