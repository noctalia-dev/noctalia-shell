#pragma once

#include "render/RoundedRectProgram.hpp"
#include "render/Renderer.hpp"

#include <EGL/egl.h>

struct wl_egl_window;

class GlRenderer final : public Renderer {
public:
    GlRenderer();
    ~GlRenderer() override;

    [[nodiscard]] const char* name() const noexcept override;

    void bind(wl_display* display, wl_surface* surface) override;
    void resize(std::uint32_t width, std::uint32_t height) override;
    void render(std::uint32_t width, std::uint32_t height) override;

private:
    void cleanup();

    wl_display* m_display = nullptr;
    wl_surface* m_surface = nullptr;
    wl_egl_window* m_window = nullptr;
    EGLDisplay m_eglDisplay = EGL_NO_DISPLAY;
    EGLConfig m_eglConfig = nullptr;
    EGLContext m_eglContext = EGL_NO_CONTEXT;
    EGLSurface m_eglSurface = EGL_NO_SURFACE;
    RoundedRectProgram m_roundedRectProgram;
    std::uint32_t m_surfaceWidth = 0;
    std::uint32_t m_surfaceHeight = 0;
};
