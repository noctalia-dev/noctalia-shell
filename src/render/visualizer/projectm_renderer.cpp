#include "render/visualizer/projectm_renderer.h"

#include "core/log.h"
#include "pipewire/pipewire_pcm_tap.h"
#include "render/gl_shared_context.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <algorithm>
#include <cstdint>
#include <projectM-4/audio.h>
#include <projectM-4/core.h>
#include <projectM-4/parameters.h>
#include <projectM-4/render_opengl.h>
#include <wayland-client.h>
#include <wayland-egl.h>

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

  // EGL extension function-pointer lookups. eglGetProcAddress is a string
  // dispatch on every call (and on some drivers requires a current context),
  // so cache once on first use. The pointers are valid for the lifetime of
  // the EGL implementation, which here is the lifetime of the process.
  PFNEGLCREATEIMAGEKHRPROC eglCreateImageKHR_p() {
    static auto* fn = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(eglGetProcAddress("eglCreateImageKHR"));
    return fn;
  }

  PFNEGLDESTROYIMAGEKHRPROC eglDestroyImageKHR_p() {
    static auto* fn = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(eglGetProcAddress("eglDestroyImageKHR"));
    return fn;
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

bool ProjectMRenderer::initialize(
    GlSharedContext& shared, wl_compositor* compositor, std::uint32_t width, std::uint32_t height
) {
  if (m_projectm != nullptr) {
    kLog.warn("initialize() called twice");
    return false;
  }
  if (width == 0 || height == 0) {
    kLog.warn("refusing to initialise with zero-sized framebuffer");
    return false;
  }
  if (compositor == nullptr) {
    kLog.warn("refusing to initialise without a wl_compositor");
    return false;
  }
  m_shared = &shared;
  m_compositor = compositor;

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
    projectm_set_mesh_size(
        static_cast<projectm_handle>(m_projectm), static_cast<std::size_t>(m_meshW), static_cast<std::size_t>(m_meshH)
    );
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
  GlState prev{};
  makeCurrentSaved(prev);
  // Smooth = true: libprojectM cross-fades over its built-in transition window
  // rather than hard-cutting. Cheap enough that we always opt in.
  projectm_load_preset_file(static_cast<projectm_handle>(m_projectm), path.c_str(), /*smooth=*/true);
  restore(prev);
}

void ProjectMRenderer::setTextureSearchPaths(const std::vector<std::string>& paths) {
  if (m_projectm == nullptr) {
    return;
  }
  std::vector<const char*> cstrs;
  cstrs.reserve(paths.size());
  for (const auto& p : paths) {
    cstrs.push_back(p.c_str());
  }
  projectm_set_texture_search_paths(static_cast<projectm_handle>(m_projectm), cstrs.data(), cstrs.size());
}

void ProjectMRenderer::renderFrame() {
  if (m_projectm == nullptr || m_shared == nullptr || m_eglSurface == nullptr) {
    return;
  }
  GlState prev{};
  makeCurrentSaved(prev);

  pumpPcm();

  // libprojectM 4.1.x ignores any externally bound FBO and composites its
  // final image to draw framebuffer 0 (== our hidden window surface's back
  // buffer, made current above).
  glViewport(0, 0, static_cast<GLsizei>(m_width), static_cast<GLsizei>(m_height));
  projectm_opengl_render_frame(static_cast<projectm_handle>(m_projectm));

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glBindTexture(GL_TEXTURE_2D, m_textureName);
  glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 0, 0, static_cast<GLsizei>(m_width), static_cast<GLsizei>(m_height));
  glBindTexture(GL_TEXTURE_2D, 0);

  // Finish this context's work before eglMakeCurrent (in restore()) releases
  // it. eglMakeCurrent only flushes, it does not wait; a hard finish keeps the
  // shared root context and the surface contexts that sample our texture from
  // racing on the FBO contents across the per-frame context handoff.
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
    projectm_pcm_add_float(
        static_cast<projectm_handle>(m_projectm), m_pcmScratch.data(), static_cast<unsigned int>(frames), target
    );
    return;
  }
  // Downmix to stereo in place. Safe because the target stride (2) is smaller
  // than the source stride (channels).
  const float invChannels = 1.0f / static_cast<float>(channels);
  for (int i = 0; i < frames; ++i) {
    const float* src = m_pcmScratch.data() + static_cast<std::size_t>(i) * static_cast<std::size_t>(channels);
    float l = src[0];
    float r = src[1];
    for (int c = 2; c < channels; ++c) {
      l += src[c] * invChannels;
      r += src[c] * invChannels;
    }
    m_pcmScratch[static_cast<std::size_t>(i) * 2] = l;
    m_pcmScratch[static_cast<std::size_t>(i) * 2 + 1] = r;
  }
  projectm_pcm_add_float(
      static_cast<projectm_handle>(m_projectm), m_pcmScratch.data(), static_cast<unsigned int>(frames), PROJECTM_STEREO
  );
}

void ProjectMRenderer::makeCurrentSaved(GlState& saved) {
  saved.display = m_shared->display();
  saved.context = eglGetCurrentContext();
  saved.drawSurface = eglGetCurrentSurface(EGL_DRAW);
  saved.readSurface = eglGetCurrentSurface(EGL_READ);
  // Bind the root context with the hidden window surface so libprojectM's
  // hard-coded draw-framebuffer-0 composite has a real target. Before
  // createFbo() has run (the first makeCurrentSaved() in initialize()) there is
  // no surface yet, so fall back to surfaceless just to create GL objects.
  if (m_eglSurface != nullptr) {
    if (eglMakeCurrent(
            m_shared->display(), static_cast<EGLSurface>(m_eglSurface), static_cast<EGLSurface>(m_eglSurface),
            m_shared->rootContext()
        )
        != EGL_TRUE) {
      kLog.warn("eglMakeCurrent (producer surface) failed (EGL error 0x{:x})", static_cast<unsigned>(eglGetError()));
    }
    return;
  }
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
  glTexImage2D(
      GL_TEXTURE_2D, 0, GL_RGBA, static_cast<GLsizei>(width), static_cast<GLsizei>(height), 0, GL_RGBA,
      GL_UNSIGNED_BYTE, nullptr
  );
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  auto* surface = wl_compositor_create_surface(m_compositor);
  if (surface == nullptr) {
    kLog.warn("wl_compositor_create_surface failed");
    glDeleteTextures(1, &m_textureName);
    m_textureName = 0;
    return false;
  }
  auto* eglWindow = wl_egl_window_create(surface, static_cast<int>(width), static_cast<int>(height));
  if (eglWindow == nullptr) {
    kLog.warn("wl_egl_window_create failed");
    wl_surface_destroy(surface);
    glDeleteTextures(1, &m_textureName);
    m_textureName = 0;
    return false;
  }
  EGLSurface eglSurface = eglCreateWindowSurface(
      m_shared->display(), m_shared->config(), reinterpret_cast<EGLNativeWindowType>(eglWindow), nullptr
  );
  if (eglSurface == EGL_NO_SURFACE) {
    kLog.warn("eglCreateWindowSurface (producer) failed (EGL error 0x{:x})", static_cast<unsigned>(eglGetError()));
    wl_egl_window_destroy(eglWindow);
    wl_surface_destroy(surface);
    glDeleteTextures(1, &m_textureName);
    m_textureName = 0;
    return false;
  }
  m_wlSurface = surface;
  m_wlEglWindow = eglWindow;
  m_eglSurface = eglSurface;

  // Wrap the offscreen texture in an EGLImage so the wallpaper/lock surfaces
  // (different contexts in the share group) can import and sample it. A raw
  // shared GL texture name written via FBO in this context is not reliably
  // sampleable in another context on Mesa; an EGLImage is the supported
  // cross-context primitive. Created against the root context that owns the
  // texture (current here via makeCurrentSaved()).
  auto* createImg = eglCreateImageKHR_p();
  if (createImg != nullptr && m_shared != nullptr) {
    const EGLint imgAttrs[] = {EGL_GL_TEXTURE_LEVEL_KHR, 0, EGL_NONE};
    EGLImageKHR img = createImg(
        m_shared->display(), m_shared->rootContext(), EGL_GL_TEXTURE_2D_KHR,
        reinterpret_cast<EGLClientBuffer>(static_cast<std::uintptr_t>(m_textureName)), imgAttrs
    );
    if (img == EGL_NO_IMAGE_KHR) {
      kLog.warn(
          "eglCreateImageKHR failed (EGL error 0x{:x}); live paper will not be visible",
          static_cast<unsigned>(eglGetError())
      );
      m_eglImage = nullptr;
    } else {
      m_eglImage = img;
    }
  } else {
    kLog.warn("eglCreateImageKHR unavailable; live paper will not be visible");
    m_eglImage = nullptr;
  }

  ++m_eglImageSerial;

  m_width = width;
  m_height = height;
  return true;
}

void ProjectMRenderer::destroyFbo() {
  if (m_eglImage != nullptr && m_shared != nullptr) {
    if (auto* destroyImg = eglDestroyImageKHR_p()) {
      destroyImg(m_shared->display(), static_cast<EGLImageKHR>(m_eglImage));
    }
  }
  m_eglImage = nullptr;
  if (m_eglSurface != nullptr && m_shared != nullptr) {
    eglDestroySurface(m_shared->display(), static_cast<EGLSurface>(m_eglSurface));
    m_eglSurface = nullptr;
  }
  if (m_wlEglWindow != nullptr) {
    wl_egl_window_destroy(static_cast<wl_egl_window*>(m_wlEglWindow));
    m_wlEglWindow = nullptr;
  }
  if (m_wlSurface != nullptr) {
    wl_surface_destroy(static_cast<wl_surface*>(m_wlSurface));
    m_wlSurface = nullptr;
  }
  if (m_textureName != 0) {
    glDeleteTextures(1, &m_textureName);
    m_textureName = 0;
  }
}
