#include "render/wallpaper_renderer.h"

#include "core/log.h"
#include "render/backend/gles_render_backend.h"
#include "render/gl_shared_context.h"

#include <GLES2/gl2.h>
#include <chrono>
#include <format>
#include <stdexcept>
#include <utility>

namespace {

  constexpr Logger kLog("wallpaper-render");
  constexpr float kSlowWallpaperRenderOperationDebugMs = 50.0f;
  constexpr float kSlowWallpaperRenderOperationWarnMs = 1000.0f;

  float elapsedSince(std::chrono::steady_clock::time_point start) {
    return std::chrono::duration<float, std::milli>(std::chrono::steady_clock::now() - start).count();
  }

  template <typename... Args>
  void logSlowWallpaperRenderOperation(float ms, std::format_string<Args...> fmt, Args&&... args) {
    if (ms >= kSlowWallpaperRenderOperationWarnMs) {
      kLog.warn(fmt, std::forward<Args>(args)...);
    } else if (ms >= kSlowWallpaperRenderOperationDebugMs) {
      kLog.debug(fmt, std::forward<Args>(args)...);
    }
  }

} // namespace

WallpaperRenderer::WallpaperRenderer() = default;

WallpaperRenderer::~WallpaperRenderer() { cleanup(); }

void WallpaperRenderer::bind(GlSharedContext& shared, wl_surface* surface) {
  cleanup();

  if (surface == nullptr) {
    throw std::runtime_error("wallpaper renderer requires a valid Wayland surface");
  }

  m_surface = surface;
  m_backend = std::make_unique<GlesRenderBackend>();
  m_backend->initialize(shared);
  m_target.create(surface, *m_backend);
}

void WallpaperRenderer::makeCurrent() {
  if (m_backend != nullptr && m_target.isReady()) {
    m_backend->makeCurrent(m_target);
  }
}

EGLContext WallpaperRenderer::eglContext() const noexcept {
  const auto* native = m_backend != nullptr ? m_backend->glesNative() : nullptr;
  return native != nullptr ? native->context : EGL_NO_CONTEXT;
}

void WallpaperRenderer::resize(std::uint32_t bufferWidth, std::uint32_t bufferHeight, std::uint32_t logicalWidth,
                               std::uint32_t logicalHeight) {
  if (bufferWidth == 0 || bufferHeight == 0) {
    return;
  }

  if (m_surface == nullptr || m_backend == nullptr) {
    throw std::runtime_error("wallpaper renderer is not bound");
  }

  m_target.setLogicalSize(logicalWidth, logicalHeight);
  m_target.resize(bufferWidth, bufferHeight);
  if (!m_target.isReady()) {
    throw std::runtime_error("wallpaper renderer failed to create render target");
  }

  makeCurrent();

  m_bufferWidth = bufferWidth;
  m_bufferHeight = bufferHeight;
  m_logicalWidth = logicalWidth;
  m_logicalHeight = logicalHeight;

  glViewport(0, 0, static_cast<GLsizei>(bufferWidth), static_cast<GLsizei>(bufferHeight));

  m_program.ensureInitialized();
}

void WallpaperRenderer::render() {
  if (!m_target.isReady() || m_tex1 == 0) {
    return;
  }

  const auto totalStart = std::chrono::steady_clock::now();
  makeCurrent();
  const auto drawStart = std::chrono::steady_clock::now();
  glViewport(0, 0, static_cast<GLsizei>(m_bufferWidth), static_cast<GLsizei>(m_bufferHeight));
  glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  auto sw = static_cast<float>(m_logicalWidth);
  auto sh = static_cast<float>(m_logicalHeight);

  // If no second texture, just draw the first using fade at progress 0
  TextureId tex2 = (m_tex2 != 0) ? m_tex2 : m_tex1;
  float progress = (m_tex2 != 0) ? m_progress : 0.0f;

  m_program.draw(m_transition, WallpaperSourceKind::Image, m_tex1, rgba(0.0f, 0.0f, 0.0f, 1.0f),
                 WallpaperSourceKind::Image, tex2, rgba(0.0f, 0.0f, 0.0f, 1.0f), sw, sh, sw, sh, m_imgW1, m_imgH1,
                 m_imgW2, m_imgH2, progress, static_cast<float>(m_fillMode), m_params, m_fillColor);

  float ms = elapsedSince(drawStart);
  logSlowWallpaperRenderOperation(ms, "wallpaper draw took {:.1f}ms ({}x{} logical, {}x{} buffer)", ms, m_logicalWidth,
                                  m_logicalHeight, m_bufferWidth, m_bufferHeight);

  if (m_backend != nullptr) {
    const auto swapStart = std::chrono::steady_clock::now();
    m_backend->endFrame(m_target);
    ms = elapsedSince(swapStart);
    logSlowWallpaperRenderOperation(ms, "wallpaper swap took {:.1f}ms ({}x{} logical, {}x{} buffer)", ms,
                                    m_logicalWidth, m_logicalHeight, m_bufferWidth, m_bufferHeight);
  }
  ms = elapsedSince(totalStart);
  logSlowWallpaperRenderOperation(ms, "wallpaper render took {:.1f}ms total", ms);
}

void WallpaperRenderer::renderToFbo(const RenderFramebuffer& target) {
  if (!m_target.isReady() || m_tex1 == 0 || !target.valid()) {
    return;
  }

  const auto totalStart = std::chrono::steady_clock::now();
  makeCurrent();
  const auto drawStart = std::chrono::steady_clock::now();
  target.bind();
  glViewport(0, 0, static_cast<GLsizei>(m_bufferWidth), static_cast<GLsizei>(m_bufferHeight));
  glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  auto sw = static_cast<float>(m_logicalWidth);
  auto sh = static_cast<float>(m_logicalHeight);

  TextureId tex2 = (m_tex2 != 0) ? m_tex2 : m_tex1;
  float progress = (m_tex2 != 0) ? m_progress : 0.0f;

  m_program.draw(m_transition, WallpaperSourceKind::Image, m_tex1, rgba(0.0f, 0.0f, 0.0f, 1.0f),
                 WallpaperSourceKind::Image, tex2, rgba(0.0f, 0.0f, 0.0f, 1.0f), sw, sh, sw, sh, m_imgW1, m_imgH1,
                 m_imgW2, m_imgH2, progress, static_cast<float>(m_fillMode), m_params, m_fillColor);
  float ms = elapsedSince(drawStart);
  logSlowWallpaperRenderOperation(ms, "wallpaper FBO draw took {:.1f}ms ({}x{} logical, {}x{} buffer)", ms,
                                  m_logicalWidth, m_logicalHeight, m_bufferWidth, m_bufferHeight);
  ms = elapsedSince(totalStart);
  logSlowWallpaperRenderOperation(ms, "wallpaper FBO render took {:.1f}ms total", ms);
  // No eglSwapBuffers — caller is responsible for presentation
}

void WallpaperRenderer::swapBuffers() {
  if (m_backend == nullptr || !m_target.isReady()) {
    return;
  }

  const auto start = std::chrono::steady_clock::now();
  m_backend->endFrame(m_target);
  const float ms = elapsedSince(start);
  logSlowWallpaperRenderOperation(ms, "wallpaper swap took {:.1f}ms ({}x{} logical, {}x{} buffer)", ms, m_logicalWidth,
                                  m_logicalHeight, m_bufferWidth, m_bufferHeight);
}

std::unique_ptr<RenderFramebuffer> WallpaperRenderer::createFramebuffer(std::uint32_t width, std::uint32_t height) {
  if (m_backend == nullptr || width == 0 || height == 0) {
    return nullptr;
  }
  makeCurrent();
  return m_backend->createFramebuffer(width, height);
}

void WallpaperRenderer::bindDefaultFramebuffer() {
  if (m_backend != nullptr) {
    m_backend->bindDefaultFramebuffer();
  }
}

void WallpaperRenderer::setTransitionState(TextureId tex1, TextureId tex2, float imgW1, float imgH1, float imgW2,
                                           float imgH2, float progress, WallpaperTransition transition,
                                           WallpaperFillMode fillMode, const TransitionParams& params) {
  m_tex1 = tex1;
  m_tex2 = tex2;
  m_imgW1 = imgW1;
  m_imgH1 = imgH1;
  m_imgW2 = imgW2;
  m_imgH2 = imgH2;
  m_progress = progress;
  m_transition = transition;
  m_fillMode = fillMode;
  m_params = params;
}

void WallpaperRenderer::cleanup() {
  if (m_backend != nullptr) {
    m_backend->makeCurrentNoSurface();
  }

  m_program.destroy();

  m_target.destroy();

  if (m_backend != nullptr) {
    m_backend->cleanup();
    m_backend.reset();
  }

  m_surface = nullptr;
  m_bufferWidth = 0;
  m_bufferHeight = 0;
  m_logicalWidth = 0;
  m_logicalHeight = 0;
}
