#pragma once

#include <cstdint>
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

struct WaylandOutput {
    std::uint32_t name = 0;
    std::string interfaceName;
    std::uint32_t version = 0;
    wl_output* output = nullptr;
};

class WaylandConnection {
public:
    WaylandConnection();
    ~WaylandConnection();

    WaylandConnection(const WaylandConnection&) = delete;
    WaylandConnection& operator=(const WaylandConnection&) = delete;

    bool connect();

    bool isConnected() const noexcept;
    bool hasRequiredGlobals() const noexcept;
    bool hasLayerShell() const noexcept;
    bool hasXdgOutputManager() const noexcept;
    wl_display* display() const noexcept;
    wl_compositor* compositor() const noexcept;
    wl_shm* shm() const noexcept;
    zwlr_layer_shell_v1* layerShell() const noexcept;
    const std::vector<WaylandOutput>& outputs() const noexcept;
    static void handleGlobal(void* data,
                             wl_registry* registry,
                             std::uint32_t name,
                             const char* interface,
                             std::uint32_t version);
    static void handleGlobalRemove(void* data,
                                   wl_registry* registry,
                                   std::uint32_t name);

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
    bool m_hasLayerShellGlobal = false;
    std::vector<WaylandOutput> m_outputs;
};
