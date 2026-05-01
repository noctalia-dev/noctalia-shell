#pragma once

#include "render/core/texture_handle.h"

#include <EGL/egl.h>
#include <cstdint>
#include <memory>

class GlSharedContext;
class RenderTarget;
class TextureManager;

class RenderFramebuffer {
public:
  virtual ~RenderFramebuffer() = default;

  virtual void bind() const = 0;

  [[nodiscard]] virtual bool valid() const noexcept = 0;
  [[nodiscard]] virtual TextureId colorTexture() const noexcept = 0;
  [[nodiscard]] virtual std::uint32_t width() const noexcept = 0;
  [[nodiscard]] virtual std::uint32_t height() const noexcept = 0;
};

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

  [[nodiscard]] virtual std::unique_ptr<RenderFramebuffer> createFramebuffer(std::uint32_t width,
                                                                             std::uint32_t height) = 0;
  virtual void bindDefaultFramebuffer() = 0;

  [[nodiscard]] virtual TextureManager& textureManager() = 0;
  [[nodiscard]] virtual const GlesNativeHandles* glesNative() const noexcept { return nullptr; }
};
