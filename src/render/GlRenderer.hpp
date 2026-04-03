#pragma once

#include "font/FontService.hpp"
#include "render/LinearGradientProgram.hpp"
#include "render/RoundedRectProgram.hpp"
#include "render/Renderer.hpp"
#include "render/MsdfTextRenderer.hpp"

#include <EGL/egl.h>

class Node;
struct wl_egl_window;

class GlRenderer final : public Renderer {
public:
    GlRenderer();
    ~GlRenderer() override;

    [[nodiscard]] const char* name() const noexcept override;

    void bind(wl_display* display, wl_surface* surface) override;
    void resize(std::uint32_t width, std::uint32_t height) override;
    void render(std::uint32_t width, std::uint32_t height) override;
    void setScene(Node* root) override;
    [[nodiscard]] TextMetrics measureText(std::string_view text, float fontSize) override;

private:
    void cleanup();
    void renderNode(const Node* node, float parentX, float parentY, float parentOpacity);

    wl_display* m_display = nullptr;
    wl_surface* m_surface = nullptr;
    wl_egl_window* m_window = nullptr;
    EGLDisplay m_eglDisplay = EGL_NO_DISPLAY;
    EGLConfig m_eglConfig = nullptr;
    EGLContext m_eglContext = EGL_NO_CONTEXT;
    EGLSurface m_eglSurface = EGL_NO_SURFACE;
    FontService m_fontService;
    LinearGradientProgram m_linearGradientProgram;
    RoundedRectProgram m_roundedRectProgram;
    MsdfTextRenderer m_textRenderer;
    Node* m_sceneRoot = nullptr;
    std::uint32_t m_surfaceWidth = 0;
    std::uint32_t m_surfaceHeight = 0;
};
