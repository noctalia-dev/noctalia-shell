#pragma once

#include "render/Renderer.hpp"

#include <cstdint>
#include <functional>
#include <memory>
struct wl_callback;
struct wl_surface;
struct zwlr_layer_surface_v1;

class WaylandConnection;

class LayerSurface {
public:
    using ConfigureCallback = std::function<void(std::uint32_t width, std::uint32_t height)>;

    explicit LayerSurface(WaylandConnection& connection);
    ~LayerSurface();

    LayerSurface(const LayerSurface&) = delete;
    LayerSurface& operator=(const LayerSurface&) = delete;

    bool initialize();
    bool isRunning() const noexcept;
    void dispatch();

    void setConfigureCallback(ConfigureCallback callback);
    [[nodiscard]] Renderer* renderer() const noexcept;
    [[nodiscard]] std::uint32_t width() const noexcept { return m_width; }
    [[nodiscard]] std::uint32_t height() const noexcept { return m_height; }

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

private:
    bool createSurface();
    void render();
    void requestFrame();
    void cleanup();

    WaylandConnection& m_connection;
    std::unique_ptr<Renderer> m_renderer;
    ConfigureCallback m_configureCallback;
    wl_surface* m_surface = nullptr;
    zwlr_layer_surface_v1* m_layerSurface = nullptr;
    wl_callback* m_frameCallback = nullptr;
    bool m_running = false;
    bool m_configured = false;
    std::uint32_t m_width = 0;
    std::uint32_t m_height = 0;
};
