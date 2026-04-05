#pragma once

#include "wayland/wayland_seat.h"
#include "wayland/wayland_workspaces.h"

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

struct wl_compositor;
struct wl_display;
struct wl_output;
struct wl_registry;
struct wl_seat;
struct wl_shm;
struct zwlr_layer_shell_v1;
struct zxdg_output_manager_v1;
struct wp_cursor_shape_manager_v1;

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
  [[nodiscard]] wl_display* display() const noexcept;
  [[nodiscard]] wl_compositor* compositor() const noexcept;
  [[nodiscard]] wl_shm* shm() const noexcept;
  [[nodiscard]] zwlr_layer_shell_v1* layerShell() const noexcept;
  [[nodiscard]] const std::vector<WaylandOutput>& outputs() const noexcept;
  [[nodiscard]] WaylandOutput* findOutputByWl(wl_output* wlOutput);

  [[nodiscard]] std::vector<Workspace> workspaces() const;
  [[nodiscard]] std::vector<Workspace> workspaces(wl_output* output) const;

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
  bool m_hasLayerShellGlobal = false;
  bool m_hasExtWorkspaceGlobal = false;
  std::vector<WaylandOutput> m_outputs;
  ChangeCallback m_outputChangeCallback;

  WaylandSeat m_seatHandler;
  WaylandWorkspaces m_workspacesHandler;
};
