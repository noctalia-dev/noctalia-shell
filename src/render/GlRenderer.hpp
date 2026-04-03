#pragma once

#include "font/FontService.hpp"
#include "render/ImageProgram.hpp"
#include "render/LinearGradientProgram.hpp"
#include "render/RoundedRectProgram.hpp"
#include "render/Renderer.hpp"
#include "render/MsdfTextRenderer.hpp"
#include "render/TextureManager.hpp"

#include <EGL/egl.h>

class Node;
struct wl_egl_window;

class GlRenderer final : public Renderer {
public:
    GlRenderer();
    ~GlRenderer() override;

    [[nodiscard]] const char* name() const noexcept override;

    void bind(wl_display* display, wl_surface* surface) override;
    void resize(std::uint32_t bufferWidth, std::uint32_t bufferHeight,
                std::uint32_t logicalWidth, std::uint32_t logicalHeight) override;
    void render() override;
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
    ImageProgram m_imageProgram;
    LinearGradientProgram m_linearGradientProgram;
    RoundedRectProgram m_roundedRectProgram;
    MsdfTextRenderer m_textRenderer;
    TextureManager m_textureManager;
    Node* m_sceneRoot = nullptr;
    std::uint32_t m_bufferWidth = 0;
    std::uint32_t m_bufferHeight = 0;
    std::uint32_t m_logicalWidth = 0;
    std::uint32_t m_logicalHeight = 0;
};
