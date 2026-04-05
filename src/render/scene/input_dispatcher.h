#pragma once

#include <cstdint>
#include <functional>

class InputArea;
class Node;

class InputDispatcher {
public:
  using CursorShapeCallback = std::function<void(std::uint32_t serial, std::uint32_t shape)>;

  InputDispatcher() = default;

  void setSceneRoot(Node* root);
  void setCursorShapeCallback(CursorShapeCallback callback);

  // Dispatch Wayland pointer events into the scene graph
  void pointerEnter(float x, float y, std::uint32_t serial);
  void pointerLeave();
  void pointerMotion(float x, float y, std::uint32_t serial);
  void pointerButton(float x, float y, std::uint32_t button, bool pressed);

  // Dispatch keyboard events to the focused area
  void keyEvent(std::uint32_t sym, std::uint32_t utf32, std::uint32_t modifiers, bool pressed);

  // Focus management
  void setFocus(InputArea* area);
  [[nodiscard]] InputArea* focusedArea() const noexcept { return m_focusedArea; }

private:
  InputArea* findInputAreaAt(float x, float y);
  void updateHover(float x, float y, std::uint32_t serial);
  void updateCursor(std::uint32_t serial);
  void trackArea(InputArea* area);

  Node* m_sceneRoot = nullptr;
  CursorShapeCallback m_cursorShapeCallback;
  InputArea* m_hoveredArea = nullptr;
  InputArea* m_focusedArea = nullptr;
  std::uint32_t m_lastSerial = 0;
};
