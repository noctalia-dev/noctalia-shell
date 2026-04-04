#include "render/scene/InputArea.h"

#include "cursor-shape-v1-client-protocol.h"

InputArea::InputArea() : Node(NodeType::Base) {}

InputArea::~InputArea() {
  if (m_destroyCallback) {
    m_destroyCallback(this);
  }
}

void InputArea::setDestroyCallback(DestroyCallback callback) { m_destroyCallback = std::move(callback); }

void InputArea::setOnEnter(PointerCallback callback) { m_onEnter = std::move(callback); }
void InputArea::setOnLeave(VoidCallback callback) { m_onLeave = std::move(callback); }
void InputArea::setOnMotion(PointerCallback callback) { m_onMotion = std::move(callback); }
void InputArea::setOnPress(PointerCallback callback) { m_onPress = std::move(callback); }
void InputArea::setOnClick(PointerCallback callback) {
  m_onClick = std::move(callback);
  if (m_onClick && m_cursorShape == 0) {
    m_cursorShape = WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER;
  }
}

void InputArea::setCursorShape(std::uint32_t shape) { m_cursorShape = shape; }
void InputArea::setAcceptedButtons(std::uint32_t mask) { m_acceptedButtons = mask; }
void InputArea::setPropagateEvents(bool propagate) { m_propagateEvents = propagate; }
void InputArea::setEnabled(bool enabled) { m_enabled = enabled; }

void InputArea::dispatchEnter(float localX, float localY) {
  m_hovered = true;
  if (m_onEnter) {
    m_onEnter({.localX = localX, .localY = localY});
  }
}

void InputArea::dispatchLeave() {
  m_hovered = false;
  m_pressed = false;
  m_pressedButton = 0;
  if (m_onLeave) {
    m_onLeave();
  }
}

void InputArea::dispatchMotion(float localX, float localY) {
  if (m_onMotion) {
    m_onMotion({.localX = localX, .localY = localY});
  }
}

void InputArea::dispatchPress(float localX, float localY, std::uint32_t button, bool isPressed) {
  if (isPressed) {
    m_pressed = true;
    m_pressedButton = button;
    if (m_onPress) {
      m_onPress({.localX = localX, .localY = localY, .button = button, .pressed = true});
    }
  } else {
    const bool shouldClick = m_pressed && m_pressedButton == button && m_onClick;
    m_pressed = false;
    m_pressedButton = 0;

    if (m_onPress) {
      m_onPress({.localX = localX, .localY = localY, .button = button, .pressed = false});
    }

    // Click: release at the same InputArea that received the press
    if (shouldClick) {
      m_onClick({.localX = localX, .localY = localY, .button = button, .pressed = false});
    }
  }
}
