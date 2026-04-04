#pragma once

#include <cstdint>
#include <functional>
#include <vector>

struct wl_pointer;
struct wl_seat;
struct wl_surface;
struct wp_cursor_shape_manager_v1;
struct wp_cursor_shape_device_v1;

struct PointerEvent {
  enum class Type : std::uint8_t { Enter, Leave, Motion, Button };
  Type type;
  std::uint32_t serial = 0;
  wl_surface* surface = nullptr;
  double sx = 0.0;
  double sy = 0.0;
  std::uint32_t time = 0;
  std::uint32_t button = 0;
  std::uint32_t state = 0;
};

class WaylandSeat {
public:
  using PointerEventCallback = std::function<void(const PointerEvent&)>;

  void bind(wl_seat* seat);
  void setCursorShapeManager(wp_cursor_shape_manager_v1* manager);
  void setPointerEventCallback(PointerEventCallback callback);
  void setCursorShape(std::uint32_t serial, std::uint32_t shape);
  void cleanup();

  // Static listener entrypoints
  static void handleSeatCapabilities(void* data, wl_seat* seat, std::uint32_t caps);
  static void handleSeatName(void* data, wl_seat* seat, const char* name);
  static void handlePointerEnter(void* data, wl_pointer* pointer, std::uint32_t serial, wl_surface* surface,
                                 std::int32_t sx, std::int32_t sy);
  static void handlePointerLeave(void* data, wl_pointer* pointer, std::uint32_t serial, wl_surface* surface);
  static void handlePointerMotion(void* data, wl_pointer* pointer, std::uint32_t time, std::int32_t sx,
                                  std::int32_t sy);
  static void handlePointerButton(void* data, wl_pointer* pointer, std::uint32_t serial, std::uint32_t time,
                                  std::uint32_t button, std::uint32_t state);
  static void handlePointerFrame(void* data, wl_pointer* pointer);

private:
  wl_pointer* m_pointer = nullptr;
  wp_cursor_shape_manager_v1* m_cursorShapeManager = nullptr;
  wp_cursor_shape_device_v1* m_cursorShapeDevice = nullptr;
  PointerEventCallback m_pointerEventCallback;
  std::vector<PointerEvent> m_pendingPointerEvents;
  wl_surface* m_lastPointerSurface = nullptr;
  double m_lastPointerX = 0.0;
  double m_lastPointerY = 0.0;
  bool m_hasPointerPosition = false;
};
