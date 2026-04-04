#include "wayland/WaylandSeat.h"

#include "core/Log.h"

#include <wayland-client.h>

#include "cursor-shape-v1-client-protocol.h"

namespace {

const wl_seat_listener kSeatListener = {
    .capabilities = &WaylandSeat::handleSeatCapabilities,
    .name = &WaylandSeat::handleSeatName,
};

const wl_pointer_listener kPointerListener = {
    .enter = &WaylandSeat::handlePointerEnter,
    .leave = &WaylandSeat::handlePointerLeave,
    .motion = &WaylandSeat::handlePointerMotion,
    .button = &WaylandSeat::handlePointerButton,
    .axis = [](void*, wl_pointer*, std::uint32_t, std::uint32_t, std::int32_t) {},
    .frame = &WaylandSeat::handlePointerFrame,
    .axis_source = [](void*, wl_pointer*, std::uint32_t) {},
    .axis_stop = [](void*, wl_pointer*, std::uint32_t, std::uint32_t) {},
    .axis_discrete = [](void*, wl_pointer*, std::uint32_t, std::int32_t) {},
    .axis_value120 = [](void*, wl_pointer*, std::uint32_t, std::int32_t) {},
    .axis_relative_direction = [](void*, wl_pointer*, std::uint32_t, std::uint32_t) {},
};

} // namespace

void WaylandSeat::bind(wl_seat* seat) { wl_seat_add_listener(seat, &kSeatListener, this); }

void WaylandSeat::setCursorShapeManager(wp_cursor_shape_manager_v1* manager) { m_cursorShapeManager = manager; }

void WaylandSeat::setPointerEventCallback(PointerEventCallback callback) {
  m_pointerEventCallback = std::move(callback);
}

void WaylandSeat::setCursorShape(std::uint32_t serial, std::uint32_t shape) {
  if (m_cursorShapeDevice != nullptr) {
    wp_cursor_shape_device_v1_set_shape(m_cursorShapeDevice, serial, shape);
  }
}

void WaylandSeat::cleanup() {
  if (m_cursorShapeDevice != nullptr) {
    wp_cursor_shape_device_v1_destroy(m_cursorShapeDevice);
    m_cursorShapeDevice = nullptr;
  }
  if (m_pointer != nullptr) {
    wl_pointer_destroy(m_pointer);
    m_pointer = nullptr;
  }
  m_cursorShapeManager = nullptr;
}

void WaylandSeat::handleSeatCapabilities(void* data, wl_seat* seat, std::uint32_t caps) {
  auto* self = static_cast<WaylandSeat*>(data);

  const bool hasPointer = (caps & WL_SEAT_CAPABILITY_POINTER) != 0;

  if (hasPointer && self->m_pointer == nullptr) {
    self->m_pointer = wl_seat_get_pointer(seat);
    wl_pointer_add_listener(self->m_pointer, &kPointerListener, self);
    logInfo("pointer: bound");

    if (self->m_cursorShapeManager != nullptr) {
      self->m_cursorShapeDevice = wp_cursor_shape_manager_v1_get_pointer(self->m_cursorShapeManager, self->m_pointer);
      logInfo("pointer: cursor-shape-v1 available");
    }
  } else if (!hasPointer && self->m_pointer != nullptr) {
    if (self->m_cursorShapeDevice != nullptr) {
      wp_cursor_shape_device_v1_destroy(self->m_cursorShapeDevice);
      self->m_cursorShapeDevice = nullptr;
    }
    wl_pointer_destroy(self->m_pointer);
    self->m_pointer = nullptr;
    logInfo("pointer: released");
  }
}

void WaylandSeat::handleSeatName(void* /*data*/, wl_seat* /*seat*/, const char* /*name*/) {}

void WaylandSeat::handlePointerEnter(void* data, wl_pointer* /*pointer*/, std::uint32_t serial, wl_surface* surface,
                                     std::int32_t sx, std::int32_t sy) {
  auto* self = static_cast<WaylandSeat*>(data);
  self->m_lastPointerSurface = surface;
  self->m_lastPointerX = wl_fixed_to_double(sx);
  self->m_lastPointerY = wl_fixed_to_double(sy);
  self->m_hasPointerPosition = true;
  self->m_pendingPointerEvents.push_back(PointerEvent{
      .type = PointerEvent::Type::Enter,
      .serial = serial,
      .surface = surface,
      .sx = self->m_lastPointerX,
      .sy = self->m_lastPointerY,
  });
}

void WaylandSeat::handlePointerLeave(void* data, wl_pointer* /*pointer*/, std::uint32_t serial, wl_surface* surface) {
  auto* self = static_cast<WaylandSeat*>(data);
  self->m_lastPointerSurface = surface;
  self->m_hasPointerPosition = false;
  self->m_pendingPointerEvents.push_back(PointerEvent{
      .type = PointerEvent::Type::Leave,
      .serial = serial,
      .surface = surface,
  });
}

void WaylandSeat::handlePointerMotion(void* data, wl_pointer* /*pointer*/, std::uint32_t time, std::int32_t sx,
                                      std::int32_t sy) {
  auto* self = static_cast<WaylandSeat*>(data);
  self->m_lastPointerX = wl_fixed_to_double(sx);
  self->m_lastPointerY = wl_fixed_to_double(sy);
  self->m_hasPointerPosition = true;
  self->m_pendingPointerEvents.push_back(PointerEvent{
      .type = PointerEvent::Type::Motion,
      .sx = self->m_lastPointerX,
      .sy = self->m_lastPointerY,
      .time = time,
  });
}

void WaylandSeat::handlePointerButton(void* data, wl_pointer* /*pointer*/, std::uint32_t serial, std::uint32_t time,
                                      std::uint32_t button, std::uint32_t state) {
  auto* self = static_cast<WaylandSeat*>(data);
  self->m_pendingPointerEvents.push_back(PointerEvent{
      .type = PointerEvent::Type::Button,
      .serial = serial,
      .surface = self->m_lastPointerSurface,
      .sx = self->m_hasPointerPosition ? self->m_lastPointerX : 0.0,
      .sy = self->m_hasPointerPosition ? self->m_lastPointerY : 0.0,
      .time = time,
      .button = button,
      .state = state,
  });
}

void WaylandSeat::handlePointerFrame(void* data, wl_pointer* /*pointer*/) {
  auto* self = static_cast<WaylandSeat*>(data);
  if (self->m_pointerEventCallback) {
    for (const auto& event : self->m_pendingPointerEvents) {
      self->m_pointerEventCallback(event);
    }
  }
  self->m_pendingPointerEvents.clear();
}
