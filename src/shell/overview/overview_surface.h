#pragma once

#include "render/core/shader_program.h"
#include "render/programs/blur_program.h"
#include "render/wallpaper_renderer.h"
#include "wayland/layer_surface.h"

#include <GLES2/gl2.h>
#include <cstdint>

class GlSharedContext;

class OverviewSurface : public LayerSurface {
public:
  using LayerSurface::LayerSurface;
  ~OverviewSurface() override;

  void setSharedGl(GlSharedContext* shared) noexcept { m_shared = shared; }
  void setBlurIntensity(float v) noexcept { m_blurIntensity = v; }
  void setTintIntensity(float v) noexcept { m_tintIntensity = v; }
  void setTintColor(float r, float g, float b) noexcept {
    m_tintR = r;
    m_tintG = g;
    m_tintB = b;
  }
  void setUnloadWhenInactive(bool v) noexcept { m_unloadWhenInactive = v; }
  void setActive(bool active);
  void setWallpaperState(GLuint tex, float imgW, float imgH, WallpaperFillMode fillMode);

  [[nodiscard]] WallpaperRenderer* wallpaperRenderer() noexcept { return &m_wallpaperRenderer; }

protected:
  bool createWlSurface() override;
  void onConfigure(std::uint32_t width, std::uint32_t height) override;
  void render() override;

private:
  void ensurePrograms();
  void ensureFbos();
  void destroyFbos();

  WallpaperRenderer m_wallpaperRenderer;
  BlurProgram m_blurProgram;
  ShaderProgram m_blitProgram;
  ShaderProgram m_tintProgram;

  GLuint m_fbo1 = 0;
  GLuint m_fboTex1 = 0;
  GLuint m_fbo2 = 0;
  GLuint m_fboTex2 = 0;

  std::uint32_t m_bufW = 0;
  std::uint32_t m_bufH = 0;

  GlSharedContext* m_shared = nullptr;
  float m_blurIntensity = 0.5f;
  float m_tintIntensity = 0.3f;
  float m_tintR = 0.0f;
  float m_tintG = 0.0f;
  float m_tintB = 0.0f;
  bool m_unloadWhenInactive = true;
  bool m_active = true;
};
