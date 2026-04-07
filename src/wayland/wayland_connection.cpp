#include "wayland/wayland_connection.h"

#include "core/log.h"

#include <algorithm>
#include <stdexcept>

#include <wayland-client.h>

#include "cursor-shape-v1-client-protocol.h"
#include "ext-session-lock-v1-client-protocol.h"
#include "ext-workspace-v1-client-protocol.h"
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-activation-v1-client-protocol.h"
#include "xdg-output-unstable-v1-client-protocol.h"

namespace {

constexpr std::uint32_t kCompositorVersion = 4;
constexpr std::uint32_t kSeatVersion = 5;
constexpr std::uint32_t kShmVersion = 1;
constexpr std::uint32_t kLayerShellVersion = 4;
constexpr std::uint32_t kXdgOutputManagerVersion = 3;
constexpr std::uint32_t kExtWorkspaceManagerVersion = 1;
constexpr std::uint32_t kWlrForeignToplevelManagerVersion = 3;
constexpr std::uint32_t kCursorShapeManagerVersion = 1;
constexpr std::uint32_t kXdgActivationVersion = 1;
constexpr std::uint32_t kExtSessionLockManagerVersion = 1;
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

void xdgOutputLogicalPosition(void* /*data*/, zxdg_output_v1* /*xdgOutput*/, int32_t /*x*/, int32_t /*y*/) {}

void xdgOutputLogicalSize(void* data, zxdg_output_v1* xdgOutput, int32_t w, int32_t h) {
  auto* out = static_cast<WaylandConnection*>(data)->findOutputByXdg(xdgOutput);
  if (out != nullptr) {
    out->logicalWidth = w;
    out->logicalHeight = h;
  }
}

void xdgOutputDone(void* /*data*/, zxdg_output_v1* /*xdgOutput*/) {}

void xdgOutputName(void* /*data*/, zxdg_output_v1* /*xdgOutput*/, const char* /*name*/) {}

void xdgOutputDescription(void* /*data*/, zxdg_output_v1* /*xdgOutput*/, const char* /*desc*/) {}

const zxdg_output_v1_listener kXdgOutputListener = {
    .logical_position = xdgOutputLogicalPosition,
    .logical_size = xdgOutputLogicalSize,
    .done = xdgOutputDone,
    .name = xdgOutputName,
    .description = xdgOutputDescription,
};

constexpr Logger kLog("wayland");

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
  m_workspacesHandler.setChangeCallback(std::move(callback));
}

void WaylandConnection::setToplevelChangeCallback(ChangeCallback callback) {
  m_toplevelsHandler.setChangeCallback(std::move(callback));
}

void WaylandConnection::setPointerEventCallback(WaylandSeat::PointerEventCallback callback) {
  m_pointerEventCallback = std::move(callback);
  m_seatHandler.setPointerEventCallback([this](const PointerEvent& event) {
    if (event.type == PointerEvent::Type::Enter) {
      const auto it = m_surfaceOutputMap.find(event.surface);
      if (it != m_surfaceOutputMap.end()) {
        m_lastPointerOutput = it->second;
      }
    }
    if (m_pointerEventCallback) {
      m_pointerEventCallback(event);
    }
  });
}

void WaylandConnection::registerSurfaceOutput(wl_surface* surface, wl_output* output) {
  if (surface != nullptr) {
    m_surfaceOutputMap[surface] = output;
  }
}

void WaylandConnection::unregisterSurface(wl_surface* surface) {
  if (surface != nullptr) {
    m_surfaceOutputMap.erase(surface);
    if (m_lastPointerOutput != nullptr) {
      // Clear last pointer output only if it was from this surface
      // (we don't track which surface set it, so just leave it — it's a hint anyway)
    }
  }
}

wl_output* WaylandConnection::lastPointerOutput() const noexcept { return m_lastPointerOutput; }

void WaylandConnection::setKeyboardEventCallback(WaylandSeat::KeyboardEventCallback callback) {
  m_seatHandler.setKeyboardEventCallback(std::move(callback));
}

int WaylandConnection::repeatPollTimeoutMs() const { return m_seatHandler.repeatPollTimeoutMs(); }

void WaylandConnection::repeatTick() { m_seatHandler.repeatTick(); }

void WaylandConnection::stopKeyRepeat() { m_seatHandler.stopKeyRepeat(); }

void WaylandConnection::setCursorShape(std::uint32_t serial, std::uint32_t shape) {
  m_seatHandler.setCursorShape(serial, shape);
}

void WaylandConnection::activateWorkspace(const std::string& id) { m_workspacesHandler.activate(id); }

void WaylandConnection::activateWorkspace(wl_output* output, const std::string& id) {
  m_workspacesHandler.activateForOutput(output, id);
}

void WaylandConnection::activateWorkspace(wl_output* output, const Workspace& workspace) {
  m_workspacesHandler.activateForOutput(output, workspace);
}

std::vector<Workspace> WaylandConnection::workspaces() const { return m_workspacesHandler.all(); }

std::vector<Workspace> WaylandConnection::workspaces(wl_output* output) const {
  return m_workspacesHandler.forOutput(output);
}

std::optional<ActiveToplevel> WaylandConnection::activeToplevel() const { return m_toplevelsHandler.current(); }
wl_output* WaylandConnection::activeToplevelOutput() const { return m_toplevelsHandler.currentOutput(); }

bool WaylandConnection::isConnected() const noexcept { return m_display != nullptr; }

bool WaylandConnection::hasRequiredGlobals() const noexcept {
  return m_compositor != nullptr && m_shm != nullptr && m_layerShell != nullptr;
}

bool WaylandConnection::hasLayerShell() const noexcept { return m_hasLayerShellGlobal; }

bool WaylandConnection::hasXdgOutputManager() const noexcept { return m_xdgOutputManager != nullptr; }

bool WaylandConnection::hasExtWorkspaceManager() const noexcept { return m_hasExtWorkspaceGlobal; }
bool WaylandConnection::hasForeignToplevelManager() const noexcept { return m_hasForeignToplevelManagerGlobal; }
bool WaylandConnection::hasSessionLockManager() const noexcept { return m_sessionLockManager != nullptr; }
bool WaylandConnection::hasXdgActivation() const noexcept { return m_xdgActivation != nullptr; }

std::string WaylandConnection::requestActivationToken(wl_surface* surface) const {
  if (m_xdgActivation == nullptr || m_display == nullptr) {
    return {};
  }

  struct TokenData {
    std::string token;
  } tokenData;

  auto* token = xdg_activation_v1_get_activation_token(m_xdgActivation);

  static const xdg_activation_token_v1_listener tokenListener = {
      .done =
          [](void* data, xdg_activation_token_v1* /*token*/, const char* tokenStr) {
            auto* td = static_cast<TokenData*>(data);
            td->token = tokenStr;
          },
  };

  xdg_activation_token_v1_add_listener(token, &tokenListener, &tokenData);
  xdg_activation_token_v1_set_serial(token, m_seatHandler.lastSerial(), m_seatHandler.seat());
  if (surface != nullptr) {
    xdg_activation_token_v1_set_surface(token, surface);
  }
  xdg_activation_token_v1_commit(token);
  wl_display_roundtrip(m_display);
  xdg_activation_token_v1_destroy(token);

  return tokenData.token;
}

wl_display* WaylandConnection::display() const noexcept { return m_display; }

wl_compositor* WaylandConnection::compositor() const noexcept { return m_compositor; }

wl_shm* WaylandConnection::shm() const noexcept { return m_shm; }

zwlr_layer_shell_v1* WaylandConnection::layerShell() const noexcept { return m_layerShell; }

ext_session_lock_manager_v1* WaylandConnection::sessionLockManager() const noexcept { return m_sessionLockManager; }

const std::vector<WaylandOutput>& WaylandConnection::outputs() const noexcept { return m_outputs; }

WaylandOutput* WaylandConnection::findOutputByWl(wl_output* wlOutput) {
  for (auto& out : m_outputs) {
    if (out.output == wlOutput) {
      return &out;
    }
  }
  return nullptr;
}

WaylandOutput* WaylandConnection::findOutputByXdg(zxdg_output_v1* xdgOutput) {
  for (auto& out : m_outputs) {
    if (out.xdgOutput == xdgOutput) {
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
  std::erase_if(self->m_outputs, [name](const WaylandOutput& output) {
    if (output.name != name) {
      return false;
    }
    if (output.output != nullptr) {
      if (wl_output_get_version(output.output) >= WL_OUTPUT_RELEASE_SINCE_VERSION) {
        wl_output_release(output.output);
      } else {
        wl_output_destroy(output.output);
      }
    }
    return true;
  });
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
    m_seatHandler.bind(m_seat);
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
    m_workspacesHandler.bind(manager);
    return;
  }

  if (interfaceName == zwlr_foreign_toplevel_manager_v1_interface.name) {
    m_hasForeignToplevelManagerGlobal = true;
    const auto bindVersion = std::min(version, kWlrForeignToplevelManagerVersion);
    auto* manager = static_cast<zwlr_foreign_toplevel_manager_v1*>(
        wl_registry_bind(registry, name, &zwlr_foreign_toplevel_manager_v1_interface, bindVersion));
    m_toplevelsHandler.bind(manager);
    return;
  }

  if (interfaceName == wp_cursor_shape_manager_v1_interface.name) {
    const auto bindVersion = std::min(version, kCursorShapeManagerVersion);
    m_cursorShapeManager = static_cast<wp_cursor_shape_manager_v1*>(
        wl_registry_bind(registry, name, &wp_cursor_shape_manager_v1_interface, bindVersion));
    m_seatHandler.setCursorShapeManager(m_cursorShapeManager);
    return;
  }

  if (interfaceName == xdg_activation_v1_interface.name) {
    const auto bindVersion = std::min(version, kXdgActivationVersion);
    m_xdgActivation =
        static_cast<xdg_activation_v1*>(wl_registry_bind(registry, name, &xdg_activation_v1_interface, bindVersion));
    return;
  }

  if (interfaceName == ext_session_lock_manager_v1_interface.name) {
    const auto bindVersion = std::min(version, kExtSessionLockManagerVersion);
    m_sessionLockManager = static_cast<ext_session_lock_manager_v1*>(
        wl_registry_bind(registry, name, &ext_session_lock_manager_v1_interface, bindVersion));
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
    if (m_xdgOutputManager != nullptr) {
      auto* xdgOut = zxdg_output_manager_v1_get_xdg_output(m_xdgOutputManager, output);
      m_outputs.back().xdgOutput = xdgOut;
      zxdg_output_v1_add_listener(xdgOut, &kXdgOutputListener, this);
    }
    if (m_outputChangeCallback) {
      m_outputChangeCallback();
    }
  }
}

void WaylandConnection::cleanup() {
  m_toplevelsHandler.cleanup();
  m_workspacesHandler.cleanup();

  for (auto& out : m_outputs) {
    if (out.xdgOutput != nullptr) {
      zxdg_output_v1_destroy(out.xdgOutput);
      out.xdgOutput = nullptr;
    }
  }

  if (m_xdgOutputManager != nullptr) {
    zxdg_output_manager_v1_destroy(m_xdgOutputManager);
    m_xdgOutputManager = nullptr;
  }

  if (m_layerShell != nullptr) {
    zwlr_layer_shell_v1_destroy(m_layerShell);
    m_layerShell = nullptr;
  }

  m_seatHandler.cleanup();

  if (m_xdgActivation != nullptr) {
    xdg_activation_v1_destroy(m_xdgActivation);
    m_xdgActivation = nullptr;
  }

  if (m_sessionLockManager != nullptr) {
    ext_session_lock_manager_v1_destroy(m_sessionLockManager);
    m_sessionLockManager = nullptr;
  }

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
  kLog.info("connected compositor={} shm={} layer-shell={} xdg-output={} ext-workspace={} session-lock={} outputs={}",
            m_compositor != nullptr ? "yes" : "no", m_shm != nullptr ? "yes" : "no", hasLayerShell() ? "yes" : "no",
            hasXdgOutputManager() ? "yes" : "no", hasExtWorkspaceManager() ? "yes" : "no",
            hasSessionLockManager() ? "yes" : "no", m_outputs.size());

  for (const auto& output : m_outputs) {
    kLog.info("output {} global={} scale={} mode={}x{} desc=\"{}\"", output.connectorName, output.name, output.scale,
              output.width, output.height, output.description);
  }
}
