#pragma once

#include "wayland/wayland_seat.h"
#include "wayland/wayland_toplevels.h"
#include "wayland/wayland_workspaces.h"

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

struct wl_compositor;
struct wl_display;
struct wl_output;
struct wl_registry;
struct wl_seat;
struct wl_shm;
struct zwlr_layer_shell_v1;
struct zxdg_output_manager_v1;
struct zxdg_output_v1;
struct wp_cursor_shape_manager_v1;
struct xdg_activation_v1;
struct ext_session_lock_manager_v1;
struct zwlr_foreign_toplevel_manager_v1;

struct WaylandOutput {
  std::uint32_t name = 0;
  std::string interfaceName;
  std::string connectorName;
  std::string description;
  std::uint32_t version = 0;
  wl_output* output = nullptr;
  std::int32_t scale = 1;
  std::int32_t width = 0;
  std::int32_t height = 0;
  std::int32_t logicalWidth = 0;
  std::int32_t logicalHeight = 0;
  zxdg_output_v1* xdgOutput = nullptr;
  bool done = false;
};

class WaylandConnection {
public:
  WaylandConnection();
  ~WaylandConnection();

  WaylandConnection(const WaylandConnection&) = delete;
  WaylandConnection& operator=(const WaylandConnection&) = delete;

  using ChangeCallback = std::function<void()>;

  bool connect();

  // Delegate setters
  void setOutputChangeCallback(ChangeCallback callback);
  void setWorkspaceChangeCallback(ChangeCallback callback);
  void setToplevelChangeCallback(ChangeCallback callback);
  void setPointerEventCallback(WaylandSeat::PointerEventCallback callback);
  void setKeyboardEventCallback(WaylandSeat::KeyboardEventCallback callback);
  void setCursorShape(std::uint32_t serial, std::uint32_t shape);

  [[nodiscard]] int repeatPollTimeoutMs() const;
  void repeatTick();
  void stopKeyRepeat();
  void activateWorkspace(const std::string& id);
  void activateWorkspace(wl_output* output, const std::string& id);
  void activateWorkspace(wl_output* output, const Workspace& workspace);

  // Queries
  [[nodiscard]] bool isConnected() const noexcept;
  [[nodiscard]] bool hasRequiredGlobals() const noexcept;
  [[nodiscard]] bool hasLayerShell() const noexcept;
  [[nodiscard]] bool hasXdgOutputManager() const noexcept;
  [[nodiscard]] bool hasExtWorkspaceManager() const noexcept;
  [[nodiscard]] bool hasForeignToplevelManager() const noexcept;
  [[nodiscard]] bool hasSessionLockManager() const noexcept;
  [[nodiscard]] wl_display* display() const noexcept;
  [[nodiscard]] wl_compositor* compositor() const noexcept;
  [[nodiscard]] wl_shm* shm() const noexcept;
  [[nodiscard]] zwlr_layer_shell_v1* layerShell() const noexcept;
  [[nodiscard]] ext_session_lock_manager_v1* sessionLockManager() const noexcept;
  [[nodiscard]] const std::vector<WaylandOutput>& outputs() const noexcept;
  [[nodiscard]] WaylandOutput* findOutputByWl(wl_output* wlOutput);
  [[nodiscard]] WaylandOutput* findOutputByXdg(zxdg_output_v1* xdgOutput);

  [[nodiscard]] bool hasXdgActivation() const noexcept;
  [[nodiscard]] std::string requestActivationToken(wl_surface* surface) const;

  [[nodiscard]] std::vector<Workspace> workspaces() const;
  [[nodiscard]] std::vector<Workspace> workspaces(wl_output* output) const;
  [[nodiscard]] std::optional<ActiveToplevel> activeToplevel() const;
  [[nodiscard]] wl_output* activeToplevelOutput() const;
  [[nodiscard]] wl_output* lastPointerOutput() const noexcept;

  void registerSurfaceOutput(wl_surface* surface, wl_output* output);
  void unregisterSurface(wl_surface* surface);

  // Registry listener entrypoints
  static void handleGlobal(void* data, wl_registry* registry, std::uint32_t name, const char* interface,
                           std::uint32_t version);
  static void handleGlobalRemove(void* data, wl_registry* registry, std::uint32_t name);

private:
  void bindGlobal(wl_registry* registry, std::uint32_t name, const char* interface, std::uint32_t version);
  void cleanup();
  void logStartupSummary() const;

  wl_display* m_display = nullptr;
  wl_registry* m_registry = nullptr;
  wl_compositor* m_compositor = nullptr;
  wl_seat* m_seat = nullptr;
  wl_shm* m_shm = nullptr;
  zwlr_layer_shell_v1* m_layerShell = nullptr;
  zxdg_output_manager_v1* m_xdgOutputManager = nullptr;
  wp_cursor_shape_manager_v1* m_cursorShapeManager = nullptr;
  xdg_activation_v1* m_xdgActivation = nullptr;
  ext_session_lock_manager_v1* m_sessionLockManager = nullptr;
  bool m_hasLayerShellGlobal = false;
  bool m_hasExtWorkspaceGlobal = false;
  bool m_hasForeignToplevelManagerGlobal = false;
  std::vector<WaylandOutput> m_outputs;
  ChangeCallback m_outputChangeCallback;
  std::unordered_map<wl_surface*, wl_output*> m_surfaceOutputMap;
  wl_output* m_lastPointerOutput = nullptr;
  WaylandSeat::PointerEventCallback m_pointerEventCallback;

  WaylandSeat m_seatHandler;
  WaylandWorkspaces m_workspacesHandler;
  WaylandToplevels m_toplevelsHandler;
};
