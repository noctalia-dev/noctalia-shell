#pragma once

#include "render/scene/node.h"

#include <cstdint>
#include <functional>

class InputArea : public Node {
public:
  struct PointerData {
    float localX = 0.0f;
    float localY = 0.0f;
    std::uint32_t button = 0;
    bool pressed = false;
  };

  using PointerCallback = std::function<void(const PointerData&)>;
  using VoidCallback = std::function<void()>;
  using DestroyCallback = std::function<void(InputArea*)>;

  InputArea();
  ~InputArea() override;

  // Callback setters
  void setOnEnter(PointerCallback callback);
  void setOnLeave(VoidCallback callback);
  void setOnMotion(PointerCallback callback);
  void setOnPress(PointerCallback callback);
  void setOnClick(PointerCallback callback);

  // Configuration
  void setCursorShape(std::uint32_t shape);
  [[nodiscard]] std::uint32_t cursorShape() const noexcept { return m_cursorShape; }

  void setAcceptedButtons(std::uint32_t mask);
  [[nodiscard]] std::uint32_t acceptedButtons() const noexcept { return m_acceptedButtons; }

  void setPropagateEvents(bool propagate);
  [[nodiscard]] bool propagateEvents() const noexcept { return m_propagateEvents; }

  void setEnabled(bool enabled);
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }

  // Auto-tracked state (read-only)
  [[nodiscard]] bool hovered() const noexcept { return m_hovered; }
  [[nodiscard]] bool pressed() const noexcept { return m_pressed; }

  // Called by InputDispatcher to get notified when this area is destroyed
  void setDestroyCallback(DestroyCallback callback);

  // Dispatch methods (called by InputDispatcher)
  void dispatchEnter(float localX, float localY);
  void dispatchLeave();
  void dispatchMotion(float localX, float localY);
  void dispatchPress(float localX, float localY, std::uint32_t button, bool isPressed);

private:
  DestroyCallback m_destroyCallback;
  PointerCallback m_onEnter;
  VoidCallback m_onLeave;
  PointerCallback m_onMotion;
  PointerCallback m_onPress;
  PointerCallback m_onClick;

  std::uint32_t m_cursorShape = 0;
  std::uint32_t m_acceptedButtons = 0x110; // BTN_LEFT | BTN_RIGHT
  bool m_propagateEvents = false;
  bool m_enabled = true;
  bool m_hovered = false;
  bool m_pressed = false;
  std::uint32_t m_pressedButton = 0;
};
