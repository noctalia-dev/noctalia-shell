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

  [[nodiscard]] std::unique_ptr<RenderFramebuffer> createFramebuffer(std::uint32_t width,
                                                                     std::uint32_t height) override;
  void bindFramebuffer(const RenderFramebuffer& framebuffer) override;
  void bindDefaultFramebuffer() override;
  void setViewport(std::uint32_t width, std::uint32_t height) override;
  void clear(Color color) override;
  void setBlendMode(RenderBlendMode mode) override;

  [[nodiscard]] TextureManager& textureManager() override { return m_textureManager; }
  [[nodiscard]] const GlesNativeHandles* glesNative() const noexcept override { return &m_native; }

private:
  GlesNativeHandles m_native;
  TextureManager m_textureManager;
};
