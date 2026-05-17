#include "render/visualizer/projectm_renderer.h"

#include "core/log.h"
#include "pipewire/pipewire_pcm_tap.h"
#include "render/gl_shared_context.h"

#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <algorithm>
#include <cstdint>

#include <projectM-4/audio.h>
#include <projectM-4/core.h>
#include <projectM-4/parameters.h>
#include <projectM-4/render_opengl.h>

namespace {

  constexpr Logger kLog{"projectm-renderer"};

  // libprojectM works at any sample rate; we deliver whatever the tap gives us.
  // pulls per frame: enough at 48 kHz / 30 FPS (~1600 stereo frames) with slack.
  constexpr int kMaxFramesPerPull = 4096;

  projectm_channels toProjectmChannels(int channels) {
    if (channels >= 2) {
      return PROJECTM_STEREO;
    }
    return PROJECTM_MONO;
  }

} // namespace

struct ProjectMRenderer::GlState {
  EGLDisplay display = EGL_NO_DISPLAY;
  EGLContext context = EGL_NO_CONTEXT;
  EGLSurface drawSurface = EGL_NO_SURFACE;
  EGLSurface readSurface = EGL_NO_SURFACE;
};

ProjectMRenderer::ProjectMRenderer() = default;

ProjectMRenderer::~ProjectMRenderer() { shutdown(); }

bool ProjectMRenderer::initialize(GlSharedContext& shared, std::uint32_t width, std::uint32_t height) {
  if (m_projectm != nullptr) {
    kLog.warn("initialize() called twice");
    return false;
  }
  if (width == 0 || height == 0) {
    kLog.warn("refusing to initialise with zero-sized framebuffer");
    return false;
  }
  m_shared = &shared;

  GlState prev{};
  makeCurrentSaved(prev);

  if (!createFbo(width, height)) {
    restore(prev);
    m_shared = nullptr;
    return false;
  }

  m_projectm = projectm_create();
  if (m_projectm == nullptr) {
    kLog.warn("projectm_create() failed");
    destroyFbo();
    restore(prev);
    m_shared = nullptr;
    return false;
  }

  auto* handle = static_cast<projectm_handle>(m_projectm);
  projectm_set_window_size(handle, width, height);
  projectm_set_mesh_size(handle, static_cast<std::size_t>(m_meshW), static_cast<std::size_t>(m_meshH));
  projectm_set_fps(handle, m_fps);
  // We drive preset rotation from VisualizerService — disable libprojectM's
  // own internal rotation timer.
  projectm_set_preset_locked(handle, true);

  m_pcmScratch.assign(static_cast<std::size_t>(kMaxFramesPerPull) * PipeWirePcmTap::kMaxChannels, 0.0f);

  restore(prev);
  return true;
}

void ProjectMRenderer::shutdown() {
  if (m_projectm != nullptr) {
    GlState prev{};
    if (m_shared != nullptr) {
      makeCurrentSaved(prev);
    }
    projectm_destroy(static_cast<projectm_handle>(m_projectm));
    m_projectm = nullptr;
    destroyFbo();
    if (m_shared != nullptr) {
      restore(prev);
    }
  }
  m_shared = nullptr;
  m_width = 0;
  m_height = 0;
}

void ProjectMRenderer::resize(std::uint32_t width, std::uint32_t height) {
  if (m_projectm == nullptr || (width == m_width && height == m_height) || width == 0 || height == 0) {
    return;
  }
  GlState prev{};
  makeCurrentSaved(prev);
  destroyFbo();
  if (createFbo(width, height)) {
    projectm_set_window_size(static_cast<projectm_handle>(m_projectm), width, height);
  }
  restore(prev);
}

TextureHandle ProjectMRenderer::textureHandle() const noexcept {
  return TextureHandle{TextureId(m_textureName), static_cast<int>(m_width), static_cast<int>(m_height)};
}

void ProjectMRenderer::setMeshSize(int meshW, int meshH) {
  m_meshW = std::max(meshW, 4);
  m_meshH = std::max(meshH, 4);
  if (m_projectm != nullptr) {
    projectm_set_mesh_size(static_cast<projectm_handle>(m_projectm), static_cast<std::size_t>(m_meshW),
                           static_cast<std::size_t>(m_meshH));
  }
}

void ProjectMRenderer::setFps(int fps) {
  m_fps = std::clamp(fps, 1, 240);
  if (m_projectm != nullptr) {
    projectm_set_fps(static_cast<projectm_handle>(m_projectm), m_fps);
  }
}

void ProjectMRenderer::loadPreset(const std::string& path) {
  if (m_projectm == nullptr || m_shared == nullptr || path.empty()) {
    return;
  }
  // projectm_load_preset_file constructs the preset's GL objects *synchronously*
  // — in particular FinalComposite's VAO + element buffer (libprojectM
  // RenderItem::Init). VAOs are container objects and are NOT shared across an
  // EGL share group, so the preset's VAO must be created in the very same
  // context renderFrame() draws with (the shared surfaceless root context). If
  // we load with the caller's context current instead, the VAO name is invalid
  // when renderFrame() binds it, no element buffer is bound, and libprojectM's
  // glDrawElements(..., nullptr) faults reading indices from a null offset.
  // Hence the same make-current/restore dance as renderFrame().
  GlState prev{};
  makeCurrentSaved(prev);
  // Smooth = true: libprojectM cross-fades over its built-in transition window
  // rather than hard-cutting. Cheap enough that we always opt in.
  projectm_load_preset_file(static_cast<projectm_handle>(m_projectm), path.c_str(), /*smooth=*/true);
  restore(prev);
}

void ProjectMRenderer::renderFrame() {
  if (m_projectm == nullptr || m_shared == nullptr || m_fboName == 0) {
    return;
  }
  GlState prev{};
  makeCurrentSaved(prev);

  pumpPcm();

  // Render into our private FBO. libprojectM honours the currently bound FBO
  // and viewport. We restore the viewport to whatever was last set inside the
  // shared context after, which is unused by other consumers (they each set
  // their own).
  glBindFramebuffer(GL_FRAMEBUFFER, m_fboName);
  glViewport(0, 0, static_cast<GLsizei>(m_width), static_cast<GLsizei>(m_height));
  projectm_opengl_render_frame(static_cast<projectm_handle>(m_projectm));
  glBindFramebuffer(GL_FRAMEBUFFER, 0);

  // Finish this context's work before eglMakeCurrent (in restore()) releases
  // it. eglMakeCurrent only flushes, it does not wait; a hard finish keeps the
  // shared root context and the surface contexts that sample our texture from
  // racing on the FBO contents across the per-frame context handoff.
  //
  // NOTE: this is conservative defence, not the crash fix. The first-frame
  // SIGSEGV was a context-ownership bug in loadPreset() (see above), not an
  // async-marshalling race. This could likely be relaxed to glFlush, or
  // dropped, with separate testing — left as glFinish for now because that is
  // the configuration verified stable end-to-end.
  glFinish();
  restore(prev);
}

void ProjectMRenderer::pumpPcm() {
  if (m_pcmTap == nullptr) {
    return;
  }
  const int channels = m_pcmTap->channels();
  if (channels <= 0) {
    return;
  }
  // Drain whatever the tap accumulated since our last frame. libprojectM has
  // its own internal PCM ring, so feeding everything in one go is fine and
  // keeps the visualization tracking transients.
  int frames = m_pcmTap->consume(m_pcmScratch.data(), kMaxFramesPerPull);
  if (frames <= 0) {
    return;
  }
  // libprojectM accepts mono or interleaved stereo. Downmix anything wider
  // (5.1, 7.1) to stereo by averaging extra channels into L/R; for mono we
  // pass through as-is.
  const projectm_channels target = toProjectmChannels(channels);
  if (channels == 1 || channels == 2) {
    projectm_pcm_add_float(static_cast<projectm_handle>(m_projectm), m_pcmScratch.data(),
                           static_cast<unsigned int>(frames * channels), target);
    return;
  }
  // Downmix to stereo in place. Safe because the target stride (2) is smaller
  // than the source stride (channels).
  for (int i = 0; i < frames; ++i) {
    const float* src = m_pcmScratch.data() + static_cast<std::size_t>(i) * static_cast<std::size_t>(channels);
    float l = src[0];
    float r = src[1];
    const float invExtra = 1.0f / static_cast<float>(channels - 1);
    for (int c = 2; c < channels; ++c) {
      // Distribute centre/surround equally across L/R.
      l += src[c] * invExtra * 0.5f;
      r += src[c] * invExtra * 0.5f;
    }
    m_pcmScratch[static_cast<std::size_t>(i) * 2] = l;
    m_pcmScratch[static_cast<std::size_t>(i) * 2 + 1] = r;
  }
  projectm_pcm_add_float(static_cast<projectm_handle>(m_projectm), m_pcmScratch.data(),
                         static_cast<unsigned int>(frames * 2), PROJECTM_STEREO);
}

void ProjectMRenderer::makeCurrentSaved(GlState& saved) {
  saved.display = m_shared->display();
  saved.context = eglGetCurrentContext();
  saved.drawSurface = eglGetCurrentSurface(EGL_DRAW);
  saved.readSurface = eglGetCurrentSurface(EGL_READ);
  m_shared->makeCurrentSurfaceless();
}

void ProjectMRenderer::restore(const GlState& saved) {
  if (saved.display != EGL_NO_DISPLAY) {
    eglMakeCurrent(saved.display, saved.drawSurface, saved.readSurface, saved.context);
  }
}

bool ProjectMRenderer::createFbo(std::uint32_t width, std::uint32_t height) {
  glGenTextures(1, &m_textureName);
  if (m_textureName == 0) {
    kLog.warn("glGenTextures failed");
    return false;
  }
  glBindTexture(GL_TEXTURE_2D, m_textureName);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, static_cast<GLsizei>(width), static_cast<GLsizei>(height), 0, GL_RGBA,
               GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  glGenFramebuffers(1, &m_fboName);
  if (m_fboName == 0) {
    glDeleteTextures(1, &m_textureName);
    m_textureName = 0;
    kLog.warn("glGenFramebuffers failed");
    return false;
  }
  glBindFramebuffer(GL_FRAMEBUFFER, m_fboName);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_textureName, 0);
  const GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  if (status != GL_FRAMEBUFFER_COMPLETE) {
    kLog.warn("FBO incomplete: 0x{:x}", static_cast<unsigned>(status));
    destroyFbo();
    return false;
  }
  m_width = width;
  m_height = height;
  return true;
}

void ProjectMRenderer::destroyFbo() {
  if (m_fboName != 0) {
    glDeleteFramebuffers(1, &m_fboName);
    m_fboName = 0;
  }
  if (m_textureName != 0) {
    glDeleteTextures(1, &m_textureName);
    m_textureName = 0;
  }
}
