#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

struct wl_compositor;
struct wl_display;
struct wl_output;
struct wl_pointer;
struct wl_registry;
struct wl_seat;
struct wl_shm;
struct wl_surface;
struct wl_array;
struct zwlr_layer_shell_v1;
struct zxdg_output_manager_v1;
struct ext_workspace_manager_v1;
struct ext_workspace_group_handle_v1;
struct ext_workspace_handle_v1;
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
    using PointerEventCallback = std::function<void(const PointerEvent&)>;

    bool connect();
    void setOutputChangeCallback(ChangeCallback callback);
    void setWorkspaceChangeCallback(ChangeCallback callback);
    void setPointerEventCallback(PointerEventCallback callback);
    void setCursorShape(std::uint32_t serial, std::uint32_t shape);
    void activateWorkspace(const std::string& id);

    bool isConnected() const noexcept;
    bool hasRequiredGlobals() const noexcept;
    bool hasLayerShell() const noexcept;
    bool hasXdgOutputManager() const noexcept;
    bool hasExtWorkspaceManager() const noexcept;
    wl_display* display() const noexcept;
    wl_compositor* compositor() const noexcept;
    wl_shm* shm() const noexcept;
    zwlr_layer_shell_v1* layerShell() const noexcept;
    const std::vector<WaylandOutput>& outputs() const noexcept;
    WaylandOutput* findOutputByWl(wl_output* wlOutput);
    static void handleGlobal(void* data,
                             wl_registry* registry,
                             std::uint32_t name,
                             const char* interface,
                             std::uint32_t version);
    static void handleGlobalRemove(void* data,
                                   wl_registry* registry,
                                   std::uint32_t name);

public:
    struct Workspace {
        std::string id;
        std::string name;
        std::vector<std::uint32_t> coordinates;  // N-dimensional position in workspace grid
        bool active = false;
    };

    [[nodiscard]] std::vector<Workspace> workspaces() const;
    [[nodiscard]] std::vector<Workspace> workspaces(wl_output* output) const;

    // Seat + pointer listener entrypoints
    static void handleSeatCapabilities(void* data, wl_seat* seat, std::uint32_t caps);
    static void handleSeatName(void* data, wl_seat* seat, const char* name);
    static void handlePointerEnter(void* data, wl_pointer* pointer, std::uint32_t serial,
                                    wl_surface* surface, std::int32_t sx, std::int32_t sy);
    static void handlePointerLeave(void* data, wl_pointer* pointer, std::uint32_t serial,
                                    wl_surface* surface);
    static void handlePointerMotion(void* data, wl_pointer* pointer, std::uint32_t time,
                                     std::int32_t sx, std::int32_t sy);
    static void handlePointerButton(void* data, wl_pointer* pointer, std::uint32_t serial,
                                     std::uint32_t time, std::uint32_t button, std::uint32_t state);
    static void handlePointerFrame(void* data, wl_pointer* pointer);

    // Internal callback entrypoints used by C listeners for ext-workspace.
    void onWorkspaceGroupCreated(ext_workspace_group_handle_v1* group);
    void onWorkspaceGroupRemoved(ext_workspace_group_handle_v1* group);
    void onWorkspaceGroupOutputEnter(ext_workspace_group_handle_v1* group, wl_output* output);
    void onWorkspaceGroupOutputLeave(ext_workspace_group_handle_v1* group, wl_output* output);
    void onWorkspaceGroupWorkspaceEnter(ext_workspace_group_handle_v1* group, ext_workspace_handle_v1* workspace);
    void onWorkspaceGroupWorkspaceLeave(ext_workspace_group_handle_v1* group, ext_workspace_handle_v1* workspace);
    void onWorkspaceCreated(ext_workspace_handle_v1* workspace);
    void onWorkspaceIdChanged(ext_workspace_handle_v1* workspace, const char* id);
    void onWorkspaceNameChanged(ext_workspace_handle_v1* workspace, const char* name);
    void onWorkspaceCoordinatesChanged(ext_workspace_handle_v1* workspace, wl_array* coordinates);
    void onWorkspaceStateChanged(ext_workspace_handle_v1* workspace, std::uint32_t state);
    void onWorkspaceRemoved(ext_workspace_handle_v1* workspace);
    void onWorkspaceManagerDone();
    void onWorkspaceManagerFinished();

private:

    void bindGlobal(wl_registry* registry,
                    std::uint32_t name,
                    const char* interface,
                    std::uint32_t version);
    void cleanup();
    void logStartupSummary() const;

    wl_display* m_display = nullptr;
    wl_registry* m_registry = nullptr;
    wl_compositor* m_compositor = nullptr;
    wl_seat* m_seat = nullptr;
    wl_shm* m_shm = nullptr;
    zwlr_layer_shell_v1* m_layerShell = nullptr;
    zxdg_output_manager_v1* m_xdgOutputManager = nullptr;
    ext_workspace_manager_v1* m_workspaceManager = nullptr;
    bool m_hasLayerShellGlobal = false;
    bool m_hasExtWorkspaceGlobal = false;
    std::vector<WaylandOutput> m_outputs;
    struct WorkspaceGroup {
        ext_workspace_group_handle_v1* handle = nullptr;
        std::vector<wl_output*> outputs;
        std::vector<ext_workspace_handle_v1*> workspaces;
    };

    std::vector<WorkspaceGroup> m_workspaceGroups;
    std::unordered_map<ext_workspace_handle_v1*, Workspace> m_workspaces;
    wl_pointer* m_pointer = nullptr;
    wp_cursor_shape_manager_v1* m_cursorShapeManager = nullptr;
    wp_cursor_shape_device_v1* m_cursorShapeDevice = nullptr;
    PointerEventCallback m_pointerEventCallback;
    std::vector<PointerEvent> m_pendingPointerEvents;
    ChangeCallback m_outputChangeCallback;
    ChangeCallback m_workspaceChangeCallback;
};
