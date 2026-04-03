#pragma once

#include <cstdint>
#include <functional>
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
struct ext_workspace_manager_v1;
struct ext_workspace_group_handle_v1;
struct ext_workspace_handle_v1;

struct WaylandOutput {
    std::uint32_t name = 0;
    std::string interfaceName;
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
    void setOutputChangeCallback(ChangeCallback callback);
    void setWorkspaceChangeCallback(ChangeCallback callback);

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
        std::string name;
        bool active = false;
    };

    [[nodiscard]] std::vector<Workspace> workspaces() const;

    // Internal callback entrypoints used by C listeners for ext-workspace.
    void onWorkspaceGroupCreated(ext_workspace_group_handle_v1* group);
    void onWorkspaceGroupRemoved(ext_workspace_group_handle_v1* group);
    void onWorkspaceCreated(ext_workspace_handle_v1* workspace);
    void onWorkspaceNameChanged(ext_workspace_handle_v1* workspace, const char* name);
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
    std::vector<ext_workspace_group_handle_v1*> m_workspaceGroups;
    std::unordered_map<ext_workspace_handle_v1*, Workspace> m_workspaces;
    ChangeCallback m_outputChangeCallback;
    ChangeCallback m_workspaceChangeCallback;
};
