#pragma once

#include "font/font_service.h"
#include "render/core/renderer.h"
#include "render/core/texture_manager.h"
#include "render/programs/image_program.h"
#include "render/programs/linear_gradient_program.h"
#include "render/programs/rounded_rect_program.h"
#include "render/programs/spinner_program.h"
#include "render/text/msdf_text_renderer.h"

#include <EGL/egl.h>

struct wl_display;
class Node;
class RenderTarget;

class RenderContext : public Renderer {
public:
  RenderContext();
  ~RenderContext() override;

  RenderContext(const RenderContext&) = delete;
  RenderContext& operator=(const RenderContext&) = delete;

  void initialize(wl_display* display);
  void cleanup();

  void renderScene(RenderTarget& target, Node* sceneRoot);
  void makeCurrent(RenderTarget& target);

  [[nodiscard]] EGLDisplay eglDisplay() const noexcept { return m_eglDisplay; }
  [[nodiscard]] EGLConfig eglConfig() const noexcept { return m_eglConfig; }
  [[nodiscard]] EGLContext eglContext() const noexcept { return m_eglContext; }

  // Renderer interface — used by widgets for measurement and textures
  [[nodiscard]] TextMetrics measureText(std::string_view text, float fontSize, bool bold = false) override;
  [[nodiscard]] TextMetrics measureGlyph(char32_t codepoint, float fontSize) override;
  [[nodiscard]] TextureManager& textureManager() override;

private:
  void ensureGlPrograms();
  void renderNode(const Node* node, float parentX, float parentY, float parentOpacity, float sw, float sh, float bw,
                  float bh, float clipLeft, float clipTop, float clipRight, float clipBottom, bool hasClip);

  EGLDisplay m_eglDisplay = EGL_NO_DISPLAY;
  EGLConfig m_eglConfig = nullptr;
  EGLContext m_eglContext = EGL_NO_CONTEXT;
  bool m_glReady = false;

  FontService m_fontService;
  ImageProgram m_imageProgram;
  LinearGradientProgram m_linearGradientProgram;
  RoundedRectProgram m_roundedRectProgram;
  SpinnerProgram m_spinnerProgram;
  MsdfTextRenderer m_textRenderer;
  MsdfTextRenderer m_boldTextRenderer;
  MsdfTextRenderer m_iconTextRenderer;
  TextureManager m_textureManager;
};
