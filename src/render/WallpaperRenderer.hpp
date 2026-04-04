#pragma once

#include "config/ConfigService.hpp"
#include "render/core/Renderer.hpp"
#include "render/core/TextureManager.hpp"
#include "render/programs/WallpaperProgram.hpp"

#include <EGL/egl.h>

struct wl_egl_window;

class WallpaperRenderer final : public Renderer {
public:
    WallpaperRenderer();
    ~WallpaperRenderer() override;

    [[nodiscard]] const char* name() const noexcept override;

    void bind(wl_display* display, wl_surface* surface) override;
    void makeCurrent() override;
    void resize(std::uint32_t bufferWidth, std::uint32_t bufferHeight,
                std::uint32_t logicalWidth, std::uint32_t logicalHeight) override;
    void render() override;
    void setScene(Node* root) override;
    [[nodiscard]] TextMetrics measureText(std::string_view text, float fontSize) override;
    [[nodiscard]] TextMetrics measureIcon(std::string_view text, float fontSize) override;
    [[nodiscard]] TextureManager& textureManager() override;

    // Wallpaper-specific: set state before render() is called by Surface
    void setTransitionState(GLuint tex1, GLuint tex2,
                            float imgW1, float imgH1,
                            float imgW2, float imgH2,
                            float progress,
                            WallpaperTransition transition,
                            WallpaperFillMode fillMode,
                            const TransitionParams& params);

private:
    void cleanup();

    wl_display* m_display = nullptr;
    wl_surface* m_surface = nullptr;
    wl_egl_window* m_window = nullptr;
    EGLDisplay m_eglDisplay = EGL_NO_DISPLAY;
    EGLConfig m_eglConfig = nullptr;
    EGLContext m_eglContext = EGL_NO_CONTEXT;
    EGLSurface m_eglSurface = EGL_NO_SURFACE;

    WallpaperProgram m_program;
    TextureManager m_textureManager;

    std::uint32_t m_bufferWidth = 0;
    std::uint32_t m_bufferHeight = 0;
    std::uint32_t m_logicalWidth = 0;
    std::uint32_t m_logicalHeight = 0;

    // Cached transition state for render()
    GLuint m_tex1 = 0;
    GLuint m_tex2 = 0;
    float m_imgW1 = 0.0f;
    float m_imgH1 = 0.0f;
    float m_imgW2 = 0.0f;
    float m_imgH2 = 0.0f;
    float m_progress = 0.0f;
    WallpaperTransition m_transition = WallpaperTransition::Fade;
    WallpaperFillMode m_fillMode = WallpaperFillMode::Crop;
    TransitionParams m_params;
};
