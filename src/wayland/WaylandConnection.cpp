#include "wayland/WaylandConnection.h"

#include "core/Log.h"

#include <algorithm>
#include <stdexcept>

#include <wayland-client.h>

#include "cursor-shape-v1-client-protocol.h"
#include "ext-workspace-v1-client-protocol.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-output-unstable-v1-client-protocol.h"

namespace {

constexpr std::uint32_t kCompositorVersion = 4;
constexpr std::uint32_t kSeatVersion = 5;
constexpr std::uint32_t kShmVersion = 1;
constexpr std::uint32_t kLayerShellVersion = 4;
constexpr std::uint32_t kXdgOutputManagerVersion = 3;
constexpr std::uint32_t kExtWorkspaceManagerVersion = 1;
constexpr std::uint32_t kCursorShapeManagerVersion = 1;
constexpr std::uint32_t kOutputVersion = 4;

const wl_registry_listener kRegistryListener = {
    .global = &WaylandConnection::handleGlobal,
    .global_remove = &WaylandConnection::handleGlobalRemove,
};

void outputGeometry(void* /*data*/, wl_output* /*output*/, int32_t /*x*/, int32_t /*y*/, int32_t /*physW*/,
                    int32_t /*physH*/, int32_t /*subpixel*/, const char* /*make*/, const char* /*model*/,
                    int32_t /*transform*/) {}

void outputMode(void* data, wl_output* wlOut, uint32_t flags, int32_t w, int32_t h, int32_t /*refresh*/) {
  if ((flags & WL_OUTPUT_MODE_CURRENT) == 0) {
    return;
  }
  auto* out = static_cast<WaylandConnection*>(data)->findOutputByWl(wlOut);
  if (out != nullptr) {
    out->width = w;
    out->height = h;
  }
}

void outputDone(void* data, wl_output* wlOut) {
  auto* out = static_cast<WaylandConnection*>(data)->findOutputByWl(wlOut);
  if (out != nullptr) {
    out->done = true;
  }
}

void outputScale(void* data, wl_output* wlOut, int32_t factor) {
  auto* out = static_cast<WaylandConnection*>(data)->findOutputByWl(wlOut);
  if (out != nullptr) {
    out->scale = factor;
  }
}

void outputName(void* data, wl_output* wlOut, const char* name) {
  auto* out = static_cast<WaylandConnection*>(data)->findOutputByWl(wlOut);
  if (out != nullptr && name != nullptr) {
    out->connectorName = name;
  }
}

void outputDescription(void* data, wl_output* wlOut, const char* desc) {
  auto* out = static_cast<WaylandConnection*>(data)->findOutputByWl(wlOut);
  if (out != nullptr) {
    out->description = desc;
  }
}

const wl_output_listener kOutputListener = {
    .geometry = outputGeometry,
    .mode = outputMode,
    .done = outputDone,
    .scale = outputScale,
    .name = outputName,
    .description = outputDescription,
};

} // namespace

WaylandConnection::WaylandConnection() = default;

WaylandConnection::~WaylandConnection() { cleanup(); }

bool WaylandConnection::connect() {
  if (m_display != nullptr) {
    return true;
  }

  m_display = wl_display_connect(nullptr);
  if (m_display == nullptr) {
    throw std::runtime_error("failed to connect to Wayland display");
  }

  m_registry = wl_display_get_registry(m_display);
  if (m_registry == nullptr) {
    cleanup();
    throw std::runtime_error("failed to acquire Wayland registry");
  }

  if (wl_registry_add_listener(m_registry, &kRegistryListener, this) != 0) {
    cleanup();
    throw std::runtime_error("failed to add Wayland registry listener");
  }

  if (wl_display_roundtrip(m_display) < 0) {
    cleanup();
    throw std::runtime_error("failed during Wayland registry roundtrip");
  }

  if (wl_display_roundtrip(m_display) < 0) {
    cleanup();
    throw std::runtime_error("failed during Wayland output discovery roundtrip");
  }

  logStartupSummary();
  return true;
}

void WaylandConnection::setOutputChangeCallback(ChangeCallback callback) {
  m_outputChangeCallback = std::move(callback);
}

void WaylandConnection::setWorkspaceChangeCallback(ChangeCallback callback) {
  m_workspaces_handler.setChangeCallback(std::move(callback));
}

void WaylandConnection::setPointerEventCallback(WaylandSeat::PointerEventCallback callback) {
  m_seat_handler.setPointerEventCallback(std::move(callback));
}

void WaylandConnection::setCursorShape(std::uint32_t serial, std::uint32_t shape) {
  m_seat_handler.setCursorShape(serial, shape);
}

void WaylandConnection::activateWorkspace(const std::string& id) { m_workspaces_handler.activate(id); }

std::vector<Workspace> WaylandConnection::workspaces() const { return m_workspaces_handler.all(); }

std::vector<Workspace> WaylandConnection::workspaces(wl_output* output) const {
  return m_workspaces_handler.forOutput(output);
}

bool WaylandConnection::isConnected() const noexcept { return m_display != nullptr; }

bool WaylandConnection::hasRequiredGlobals() const noexcept {
  return m_compositor != nullptr && m_shm != nullptr && m_layerShell != nullptr;
}

bool WaylandConnection::hasLayerShell() const noexcept { return m_hasLayerShellGlobal; }

bool WaylandConnection::hasXdgOutputManager() const noexcept { return m_xdgOutputManager != nullptr; }

bool WaylandConnection::hasExtWorkspaceManager() const noexcept { return m_hasExtWorkspaceGlobal; }

wl_display* WaylandConnection::display() const noexcept { return m_display; }

wl_compositor* WaylandConnection::compositor() const noexcept { return m_compositor; }

wl_shm* WaylandConnection::shm() const noexcept { return m_shm; }

zwlr_layer_shell_v1* WaylandConnection::layerShell() const noexcept { return m_layerShell; }

const std::vector<WaylandOutput>& WaylandConnection::outputs() const noexcept { return m_outputs; }

WaylandOutput* WaylandConnection::findOutputByWl(wl_output* wlOutput) {
  for (auto& out : m_outputs) {
    if (out.output == wlOutput) {
      return &out;
    }
  }
  return nullptr;
}

void WaylandConnection::handleGlobal(void* data, wl_registry* registry, std::uint32_t name, const char* interface,
                                     std::uint32_t version) {
  auto* self = static_cast<WaylandConnection*>(data);
  self->bindGlobal(registry, name, interface, version);
}

void WaylandConnection::handleGlobalRemove(void* data, wl_registry* /*registry*/, std::uint32_t name) {
  auto* self = static_cast<WaylandConnection*>(data);
  const auto sizeBefore = self->m_outputs.size();
  std::erase_if(self->m_outputs, [name](const WaylandOutput& output) { return output.name == name; });
  if (self->m_outputs.size() != sizeBefore && self->m_outputChangeCallback) {
    self->m_outputChangeCallback();
  }
}

void WaylandConnection::bindGlobal(wl_registry* registry, std::uint32_t name, const char* interface,
                                   std::uint32_t version) {
  const std::string interfaceName = interface;

  if (interfaceName == wl_compositor_interface.name) {
    const auto bindVersion = std::min(version, kCompositorVersion);
    m_compositor = static_cast<wl_compositor*>(wl_registry_bind(registry, name, &wl_compositor_interface, bindVersion));
    return;
  }

  if (interfaceName == wl_seat_interface.name) {
    const auto bindVersion = std::min(version, kSeatVersion);
    m_seat = static_cast<wl_seat*>(wl_registry_bind(registry, name, &wl_seat_interface, bindVersion));
    m_seat_handler.bind(m_seat);
    return;
  }

  if (interfaceName == wl_shm_interface.name) {
    const auto bindVersion = std::min(version, kShmVersion);
    m_shm = static_cast<wl_shm*>(wl_registry_bind(registry, name, &wl_shm_interface, bindVersion));
    return;
  }

  if (interfaceName == "zwlr_layer_shell_v1") {
    m_hasLayerShellGlobal = true;
    const auto bindVersion = std::min(version, kLayerShellVersion);
    m_layerShell = static_cast<zwlr_layer_shell_v1*>(
        wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, bindVersion));
    return;
  }

  if (interfaceName == zxdg_output_manager_v1_interface.name) {
    const auto bindVersion = std::min(version, kXdgOutputManagerVersion);
    m_xdgOutputManager = static_cast<zxdg_output_manager_v1*>(
        wl_registry_bind(registry, name, &zxdg_output_manager_v1_interface, bindVersion));
    return;
  }

  if (interfaceName == ext_workspace_manager_v1_interface.name) {
    m_hasExtWorkspaceGlobal = true;
    const auto bindVersion = std::min(version, kExtWorkspaceManagerVersion);
    auto* manager = static_cast<ext_workspace_manager_v1*>(
        wl_registry_bind(registry, name, &ext_workspace_manager_v1_interface, bindVersion));
    m_workspaces_handler.bind(manager);
    return;
  }

  if (interfaceName == wp_cursor_shape_manager_v1_interface.name) {
    const auto bindVersion = std::min(version, kCursorShapeManagerVersion);
    m_cursorShapeManager = static_cast<wp_cursor_shape_manager_v1*>(
        wl_registry_bind(registry, name, &wp_cursor_shape_manager_v1_interface, bindVersion));
    m_seat_handler.setCursorShapeManager(m_cursorShapeManager);
    return;
  }

  if (interfaceName == wl_output_interface.name) {
    const auto bindVersion = std::min(version, kOutputVersion);
    auto* output = static_cast<wl_output*>(wl_registry_bind(registry, name, &wl_output_interface, bindVersion));
    m_outputs.push_back(WaylandOutput{
        .name = name,
        .interfaceName = interfaceName,
        .connectorName = {},
        .description = {},
        .version = version,
        .output = output,
    });
    wl_output_add_listener(output, &kOutputListener, this);
    if (m_outputChangeCallback) {
      m_outputChangeCallback();
    }
  }
}

void WaylandConnection::cleanup() {
  m_workspaces_handler.cleanup();

  if (m_xdgOutputManager != nullptr) {
    zxdg_output_manager_v1_destroy(m_xdgOutputManager);
    m_xdgOutputManager = nullptr;
  }

  if (m_layerShell != nullptr) {
    zwlr_layer_shell_v1_destroy(m_layerShell);
    m_layerShell = nullptr;
  }

  m_seat_handler.cleanup();

  if (m_cursorShapeManager != nullptr) {
    wp_cursor_shape_manager_v1_destroy(m_cursorShapeManager);
    m_cursorShapeManager = nullptr;
  }

  if (m_seat != nullptr) {
    wl_seat_destroy(m_seat);
    m_seat = nullptr;
  }

  if (m_shm != nullptr) {
    wl_shm_destroy(m_shm);
    m_shm = nullptr;
  }

  if (m_compositor != nullptr) {
    wl_compositor_destroy(m_compositor);
    m_compositor = nullptr;
  }

  for (auto& output : m_outputs) {
    if (output.output != nullptr) {
      wl_output_destroy(output.output);
      output.output = nullptr;
    }
  }

  if (m_registry != nullptr) {
    wl_registry_destroy(m_registry);
    m_registry = nullptr;
  }

  if (m_display != nullptr) {
    wl_display_disconnect(m_display);
    m_display = nullptr;
  }

  m_outputs.clear();
  m_hasLayerShellGlobal = false;
  m_hasExtWorkspaceGlobal = false;
}

void WaylandConnection::logStartupSummary() const {
  logInfo("wayland connected compositor={} shm={} layer-shell={} xdg-output={} ext-workspace={} outputs={}",
          m_compositor != nullptr ? "yes" : "no", m_shm != nullptr ? "yes" : "no", hasLayerShell() ? "yes" : "no",
          hasXdgOutputManager() ? "yes" : "no", hasExtWorkspaceManager() ? "yes" : "no", m_outputs.size());

  for (const auto& output : m_outputs) {
    logInfo("output {} global={} scale={} mode={}x{} desc=\"{}\"", output.connectorName, output.name, output.scale,
            output.width, output.height, output.description);
  }
}
