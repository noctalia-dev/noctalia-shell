#pragma once

#include <EGL/egl.h>

class GlSharedContext;
class RenderTarget;
class TextureManager;

// Temporary compatibility bridge for the current EGL/GLES RenderTarget path.
// Keep use of these handles inside render infrastructure so future backends do
// not leak native API types into shell/widget code.
struct GlesNativeHandles {
  EGLDisplay display = EGL_NO_DISPLAY;
  EGLConfig config = nullptr;
  EGLContext context = EGL_NO_CONTEXT;
};

class RenderBackend {
public:
  virtual ~RenderBackend() = default;

  virtual void initialize(GlSharedContext& shared) = 0;
  virtual void cleanup() = 0;

  virtual void makeCurrent(RenderTarget& target) = 0;
  virtual void makeCurrentNoSurface() = 0;
  virtual void beginFrame(RenderTarget& target) = 0;
  virtual void endFrame(RenderTarget& target) = 0;

  [[nodiscard]] virtual TextureManager& textureManager() = 0;
  [[nodiscard]] virtual const GlesNativeHandles* glesNative() const noexcept { return nullptr; }
};
