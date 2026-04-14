#pragma once

#include "config/config_service.h"
#include "render/programs/wallpaper_program.h"

#include <EGL/egl.h>

struct wl_surface;
struct wl_egl_window;

class GlSharedContext;

class WallpaperRenderer {
public:
  WallpaperRenderer();
  ~WallpaperRenderer();

  WallpaperRenderer(const WallpaperRenderer&) = delete;
  WallpaperRenderer& operator=(const WallpaperRenderer&) = delete;

  void bind(GlSharedContext& shared, wl_surface* surface);
  void makeCurrent();
  [[nodiscard]] EGLContext eglContext() const noexcept { return m_eglContext; }
  void resize(std::uint32_t bufferWidth, std::uint32_t bufferHeight, std::uint32_t logicalWidth,
              std::uint32_t logicalHeight);
  void render();
  void renderToFbo(GLuint targetFbo);
  void swapBuffers();

  void setTransitionState(GLuint tex1, GLuint tex2, float imgW1, float imgH1, float imgW2, float imgH2, float progress,
                          WallpaperTransition transition, WallpaperFillMode fillMode, const TransitionParams& params);

private:
  void cleanup();

  wl_surface* m_surface = nullptr;
  wl_egl_window* m_window = nullptr;
  EGLDisplay m_eglDisplay = EGL_NO_DISPLAY;
  EGLConfig m_eglConfig = nullptr;
  EGLContext m_eglContext = EGL_NO_CONTEXT;
  EGLSurface m_eglSurface = EGL_NO_SURFACE;

  WallpaperProgram m_program;

  std::uint32_t m_bufferWidth = 0;
  std::uint32_t m_bufferHeight = 0;
  std::uint32_t m_logicalWidth = 0;
  std::uint32_t m_logicalHeight = 0;

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
