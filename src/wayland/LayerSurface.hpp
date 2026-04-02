#pragma once

#include <cstdint>
#include <vector>

struct wl_buffer;
struct wl_callback;
struct wl_shm_pool;
struct wl_surface;
struct zwlr_layer_surface_v1;

class WaylandConnection;

class LayerSurface {
public:
    explicit LayerSurface(WaylandConnection& connection);
    ~LayerSurface();

    LayerSurface(const LayerSurface&) = delete;
    LayerSurface& operator=(const LayerSurface&) = delete;

    bool initialize();
    bool isRunning() const noexcept;
    void dispatch();

    static void handleConfigure(void* data,
                                zwlr_layer_surface_v1* layerSurface,
                                std::uint32_t serial,
                                std::uint32_t width,
                                std::uint32_t height);
    static void handleClosed(void* data,
                             zwlr_layer_surface_v1* layerSurface);
    static void handleFrameDone(void* data,
                                wl_callback* callback,
                                std::uint32_t callbackData);
    static void handleBufferRelease(void* data,
                                    wl_buffer* buffer);

private:
    struct ShmBuffer {
        int fd = -1;
        std::size_t size = 0;
        void* data = nullptr;
        wl_shm_pool* pool = nullptr;
        wl_buffer* buffer = nullptr;
        std::vector<std::uint32_t> pixels;
    };

    bool createSurface();
    bool createOrResizeBuffer(std::uint32_t width, std::uint32_t height);
    void render();
    void requestFrame();
    void destroyBuffer();
    void cleanup();

    WaylandConnection& m_connection;
    wl_surface* m_surface = nullptr;
    zwlr_layer_surface_v1* m_layerSurface = nullptr;
    wl_callback* m_frameCallback = nullptr;
    bool m_running = false;
    bool m_configured = false;
    bool m_bufferBusy = false;
    std::uint32_t m_width = 0;
    std::uint32_t m_height = 0;
    ShmBuffer m_shmBuffer;
};
