#pragma once

#include "render/core/mat3.h"
#include "render/core/renderer.h"
#include "render/core/texture_manager.h"
#include "render/programs/color_glyph_program.h"
#include "render/programs/image_program.h"
#include "render/programs/linear_gradient_program.h"
#include "render/programs/rounded_rect_program.h"
#include "render/programs/spinner_program.h"
#include "render/text/cairo_glyph_renderer.h"
#include "render/text/cairo_text_renderer.h"

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
  // Sync text/glyph renderer content scale to the given target's
  // buffer-to-logical ratio. Must be called before any measureText /
  // measureGlyph performed on behalf of this target, because those
  // results depend on the rasterization scale and get baked into node
  // positions during layout.
  void syncContentScale(RenderTarget& target);

  [[nodiscard]] EGLDisplay eglDisplay() const noexcept { return m_eglDisplay; }
  [[nodiscard]] EGLConfig eglConfig() const noexcept { return m_eglConfig; }
  [[nodiscard]] EGLContext eglContext() const noexcept { return m_eglContext; }

  // Renderer interface — used by widgets for measurement and textures
  [[nodiscard]] TextMetrics measureText(std::string_view text, float fontSize, bool bold = false, float maxWidth = 0.0f,
                                        int maxLines = 0) override;
  [[nodiscard]] TextMetrics measureGlyph(char32_t codepoint, float fontSize) override;
  [[nodiscard]] TextureManager& textureManager() override;

private:
  void ensureGlPrograms();
  void makeCurrentNoSurface();
  void renderNode(const Node* node, const Mat3& parentTransform, float parentOpacity, float sw, float sh, float bw,
                  float bh, float clipLeft, float clipTop, float clipRight, float clipBottom, bool hasClip);

  EGLDisplay m_eglDisplay = EGL_NO_DISPLAY;
  EGLConfig m_eglConfig = nullptr;
  EGLContext m_eglContext = EGL_NO_CONTEXT;
  bool m_glReady = false;

  ImageProgram m_imageProgram;
  LinearGradientProgram m_linearGradientProgram;
  RoundedRectProgram m_roundedRectProgram;
  SpinnerProgram m_spinnerProgram;
  ColorGlyphProgram m_colorGlyphProgram;
  CairoTextRenderer m_textRenderer;
  CairoGlyphRenderer m_glyphRenderer;
  TextureManager m_textureManager;
};
