#pragma once

#include "render/backend/render_backend.h"
#include "render/core/texture_manager.h"

class GlesRenderBackend final : public RenderBackend {
public:
  GlesRenderBackend() = default;
  ~GlesRenderBackend() override;

  GlesRenderBackend(const GlesRenderBackend&) = delete;
  GlesRenderBackend& operator=(const GlesRenderBackend&) = delete;

  void initialize(GlSharedContext& shared) override;
  void cleanup() override;

  void makeCurrent(RenderTarget& target) override;
  void makeCurrentNoSurface() override;
  void beginFrame(RenderTarget& target) override;
  void endFrame(RenderTarget& target) override;

  [[nodiscard]] TextureManager& textureManager() override { return m_textureManager; }
  [[nodiscard]] const GlesNativeHandles* glesNative() const noexcept override { return &m_native; }

private:
  GlesNativeHandles m_native;
  TextureManager m_textureManager;
};
