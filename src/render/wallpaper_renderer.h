#pragma once

#include "config/config_service.h"
#include "render/core/color.h"
#include "render/core/texture_handle.h"
#include "render/programs/wallpaper_program.h"
#include "render/render_target.h"

#include <EGL/egl.h>
#include <cstdint>
#include <memory>

struct wl_surface;

class GlSharedContext;
class RenderBackend;
class RenderFramebuffer;

class WallpaperRenderer {
public:
  WallpaperRenderer();
  ~WallpaperRenderer();

  WallpaperRenderer(const WallpaperRenderer&) = delete;
  WallpaperRenderer& operator=(const WallpaperRenderer&) = delete;

  void bind(GlSharedContext& shared, wl_surface* surface);
  void makeCurrent();
  [[nodiscard]] EGLContext eglContext() const noexcept;
  void resize(std::uint32_t bufferWidth, std::uint32_t bufferHeight, std::uint32_t logicalWidth,
              std::uint32_t logicalHeight);
  void render();
  void renderToFbo(const RenderFramebuffer& target);
  void swapBuffers();
  [[nodiscard]] std::unique_ptr<RenderFramebuffer> createFramebuffer(std::uint32_t width, std::uint32_t height);
  void bindDefaultFramebuffer();

  void setTransitionState(TextureId tex1, TextureId tex2, float imgW1, float imgH1, float imgW2, float imgH2,
                          float progress, WallpaperTransition transition, WallpaperFillMode fillMode,
                          const TransitionParams& params);

private:
  void cleanup();

  wl_surface* m_surface = nullptr;
  std::unique_ptr<RenderBackend> m_backend;
  RenderTarget m_target;

  WallpaperProgram m_program;

  std::uint32_t m_bufferWidth = 0;
  std::uint32_t m_bufferHeight = 0;
  std::uint32_t m_logicalWidth = 0;
  std::uint32_t m_logicalHeight = 0;

  TextureId m_tex1;
  TextureId m_tex2;
  float m_imgW1 = 0.0f;
  float m_imgH1 = 0.0f;
  float m_imgW2 = 0.0f;
  float m_imgH2 = 0.0f;
  float m_progress = 0.0f;
  WallpaperTransition m_transition = WallpaperTransition::Fade;
  WallpaperFillMode m_fillMode = WallpaperFillMode::Crop;
  Color m_fillColor = rgba(0.0f, 0.0f, 0.0f, 1.0f);
  TransitionParams m_params;
};
