#pragma once

#include "render/Renderer.hpp"

#include <cstdint>
#include <functional>
#include <memory>

struct wl_callback;
struct wl_surface;

class WaylandConnection;

class Surface {
public:
    using ConfigureCallback = std::function<void(std::uint32_t width, std::uint32_t height)>;

    explicit Surface(WaylandConnection& connection);
    virtual ~Surface();

    Surface(const Surface&) = delete;
    Surface& operator=(const Surface&) = delete;

    virtual bool initialize() = 0;

    [[nodiscard]] bool isRunning() const noexcept;

    void setConfigureCallback(ConfigureCallback callback);
    [[nodiscard]] Renderer* renderer() const noexcept;
    [[nodiscard]] std::uint32_t width() const noexcept { return m_width; }
    [[nodiscard]] std::uint32_t height() const noexcept { return m_height; }

    static void handleFrameDone(void* data,
                                wl_callback* callback,
                                std::uint32_t callbackData);

protected:
    bool createWlSurface();
    void onConfigure(std::uint32_t width, std::uint32_t height);
    void render();
    void requestFrame();
    void destroySurface();

    void setRunning(bool running) noexcept { m_running = running; }

    WaylandConnection& m_connection;
    wl_surface* m_surface = nullptr;

private:
    std::unique_ptr<Renderer> m_renderer;
    ConfigureCallback m_configureCallback;
    wl_callback* m_frameCallback = nullptr;
    bool m_running = false;
    bool m_configured = false;
    std::uint32_t m_width = 0;
    std::uint32_t m_height = 0;
};
