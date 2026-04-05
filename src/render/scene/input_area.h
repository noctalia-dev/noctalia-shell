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

  struct KeyData {
    std::uint32_t sym = 0;       // XKB keysym
    std::uint32_t utf32 = 0;     // Unicode codepoint (0 for non-printable keys)
    std::uint32_t modifiers = 0; // KeyMod bitmask
    bool pressed = false;
    bool preedit = false;        // dead key preview (composing in progress)
  };

  using PointerCallback = std::function<void(const PointerData&)>;
  using KeyCallback = std::function<void(const KeyData&)>;
  using VoidCallback = std::function<void()>;
  using DestroyCallback = std::function<void(InputArea*)>;

  InputArea();
  ~InputArea() override;

  // Pointer callback setters
  void setOnEnter(PointerCallback callback);
  void setOnLeave(VoidCallback callback);
  void setOnMotion(PointerCallback callback);
  void setOnPress(PointerCallback callback);
  void setOnClick(PointerCallback callback);

  // Keyboard / focus
  void setFocusable(bool focusable);
  [[nodiscard]] bool focusable() const noexcept { return m_focusable; }
  [[nodiscard]] bool focused() const noexcept { return m_focused; }
  void setOnKeyDown(KeyCallback callback);
  void setOnKeyUp(KeyCallback callback);
  void setOnFocusGain(VoidCallback callback);
  void setOnFocusLoss(VoidCallback callback);

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
  void dispatchKey(std::uint32_t sym, std::uint32_t utf32, std::uint32_t modifiers, bool pressed,
                   bool preedit = false);
  void dispatchFocusGain();
  void dispatchFocusLoss();

private:
  DestroyCallback m_destroyCallback;
  PointerCallback m_onEnter;
  VoidCallback m_onLeave;
  PointerCallback m_onMotion;
  PointerCallback m_onPress;
  PointerCallback m_onClick;
  KeyCallback m_onKeyDown;
  KeyCallback m_onKeyUp;
  VoidCallback m_onFocusGain;
  VoidCallback m_onFocusLoss;

  std::uint32_t m_cursorShape = 0;
  std::uint32_t m_acceptedButtons = 0x110; // BTN_LEFT | BTN_RIGHT
  bool m_propagateEvents = false;
  bool m_enabled = true;
  bool m_hovered = false;
  bool m_pressed = false;
  std::uint32_t m_pressedButton = 0;
  bool m_focusable = false;
  bool m_focused = false;
};
