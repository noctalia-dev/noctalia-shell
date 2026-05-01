#include "shell/backdrop/backdrop_surface.h"

#include "render/gl_shared_context.h"
#include "wayland/wayland_connection.h"

#include <GLES2/gl2.h>
#include <stdexcept>
#include <wayland-client.h>

namespace {

  constexpr char kVertexShader[] = R"(
precision highp float;
attribute vec2 a_position;
varying vec2 v_texcoord;

void main() {
    v_texcoord = a_position;
    vec2 ndc = a_position * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);
}
)";

  constexpr char kBlitFragment[] = R"(
precision highp float;
uniform sampler2D u_texture;
varying vec2 v_texcoord;

void main() {
    // FBOs use GL convention (Y=0 at bottom), EGL window surfaces have Y=0 at top.
    // Flip V to compensate.
    vec4 c = texture2D(u_texture, vec2(v_texcoord.x, 1.0 - v_texcoord.y));
    gl_FragColor = c;
}
)";

  constexpr char kTintFragment[] = R"(
precision mediump float;
uniform vec4 u_color;
varying vec2 v_texcoord;

void main() {
    gl_FragColor = u_color;
}
)";

} // namespace

BackdropSurface::~BackdropSurface() {
  m_wallpaperRenderer.makeCurrent();
  destroyFbos();
  m_blurProgram.destroy();
  m_blitProgram.destroy();
  m_tintProgram.destroy();
}

bool BackdropSurface::createWlSurface() {
  m_surface = wl_compositor_create_surface(m_connection.compositor());
  if (m_surface == nullptr) {
    return false;
  }

  initializeSurfaceScaleProtocol();

  if (m_shared == nullptr) {
    throw std::runtime_error("BackdropSurface requires a GlSharedContext");
  }
  m_wallpaperRenderer.bind(*m_shared, m_surface);
  return true;
}

void BackdropSurface::onConfigure(std::uint32_t width, std::uint32_t height) {
  const auto bw = bufferWidthFor(width);
  const auto bh = bufferHeightFor(height);

  m_bufW = bw;
  m_bufH = bh;

  m_wallpaperRenderer.resize(bw, bh, width, height);

  // Recreate FBOs when buffer size changes (if blur is active)
  if (m_fbo1 != 0) {
    m_wallpaperRenderer.makeCurrent();
    destroyFbos();
    ensureFbos();
  }

  Surface::onConfigure(width, height);
}

void BackdropSurface::onScaleChanged() {
  if (width() == 0 || height() == 0) {
    return;
  }
  onConfigure(width(), height());
}

void BackdropSurface::render() {
  if (m_surface == nullptr) {
    return;
  }
  if (!m_active) {
    return;
  }

  requestFrame();

  // 3 rounds of H+V blur gives effective sigma ≈ radius * sqrt(3), much stronger result.
  static constexpr int kBlurRounds = 3;
  const float blurRadius = m_blurIntensity * 40.0f;
  const auto blitToScreen = [this](TextureId texture) {
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glViewport(0, 0, static_cast<GLsizei>(m_bufW), static_cast<GLsizei>(m_bufH));
    glDisable(GL_BLEND);
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(m_blitProgram.id());
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, static_cast<GLuint>(texture.value()));
    const GLint texLoc = glGetUniformLocation(m_blitProgram.id(), "u_texture");
    glUniform1i(texLoc, 0);
    const GLint posAttr = glGetAttribLocation(m_blitProgram.id(), "a_position");
    static constexpr float kQuad[] = {
        0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f,
    };
    glVertexAttribPointer(static_cast<GLuint>(posAttr), 2, GL_FLOAT, GL_FALSE, 0, kQuad);
    glEnableVertexAttribArray(static_cast<GLuint>(posAttr));
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(static_cast<GLuint>(posAttr));
  };

  if (blurRadius < 0.5f) {
    // No blur — render wallpaper to FBO1, tint there, then blit to screen.
    ensurePrograms();
    ensureFbos();
    if (m_fbo1 == 0) {
      return;
    }
    m_wallpaperRenderer.renderToFbo(m_fbo1);

    if (m_tintIntensity > 0.001f) {
      glBindFramebuffer(GL_FRAMEBUFFER, m_fbo1);
      glViewport(0, 0, static_cast<GLsizei>(m_bufW), static_cast<GLsizei>(m_bufH));
      glEnable(GL_BLEND);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      glUseProgram(m_tintProgram.id());
      GLint colorLoc = glGetUniformLocation(m_tintProgram.id(), "u_color");
      glUniform4f(colorLoc, m_tintR, m_tintG, m_tintB, m_tintIntensity);
      GLint posAttr = glGetAttribLocation(m_tintProgram.id(), "a_position");
      static constexpr float kQuad[] = {
          0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f,
      };
      glVertexAttribPointer(static_cast<GLuint>(posAttr), 2, GL_FLOAT, GL_FALSE, 0, kQuad);
      glEnableVertexAttribArray(static_cast<GLuint>(posAttr));
      glDrawArrays(GL_TRIANGLES, 0, 6);
      glDisableVertexAttribArray(static_cast<GLuint>(posAttr));
    }

    blitToScreen(m_fboTex1.id);

    m_wallpaperRenderer.swapBuffers();
    return;
  }

  // Blur path — render wallpaper to FBO1, then kBlurRounds × (H blur FBO1→FBO2, V blur FBO2→FBO1)
  ensurePrograms();
  ensureFbos();
  if (m_fbo1 == 0 || m_fbo2 == 0) {
    return;
  }

  // Pass 1: wallpaper → FBO1
  m_wallpaperRenderer.renderToFbo(m_fbo1);

  glViewport(0, 0, static_cast<GLsizei>(m_bufW), static_cast<GLsizei>(m_bufH));
  glDisable(GL_BLEND);

  for (int round = 0; round < kBlurRounds; ++round) {
    // Horizontal blur FBO1.tex → FBO2
    glBindFramebuffer(GL_FRAMEBUFFER, m_fbo2);
    m_blurProgram.draw(m_fboTex1.id, m_bufW, m_bufH, 1.0f, 0.0f, blurRadius);

    // Vertical blur FBO2.tex → FBO1
    glBindFramebuffer(GL_FRAMEBUFFER, m_fbo1);
    m_blurProgram.draw(m_fboTex2.id, m_bufW, m_bufH, 0.0f, 1.0f, blurRadius);
  }

  if (m_tintIntensity > 0.001f) {
    glBindFramebuffer(GL_FRAMEBUFFER, m_fbo1);
    glViewport(0, 0, static_cast<GLsizei>(m_bufW), static_cast<GLsizei>(m_bufH));
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glUseProgram(m_tintProgram.id());
    GLint colorLoc = glGetUniformLocation(m_tintProgram.id(), "u_color");
    glUniform4f(colorLoc, m_tintR, m_tintG, m_tintB, m_tintIntensity);
    GLint posAttr = glGetAttribLocation(m_tintProgram.id(), "a_position");
    static constexpr float kQuad[] = {
        0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f,
    };
    glVertexAttribPointer(static_cast<GLuint>(posAttr), 2, GL_FLOAT, GL_FALSE, 0, kQuad);
    glEnableVertexAttribArray(static_cast<GLuint>(posAttr));
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(static_cast<GLuint>(posAttr));
  }

  blitToScreen(m_fboTex1.id);

  m_wallpaperRenderer.swapBuffers();
}

void BackdropSurface::setActive(bool active) {
  if (m_active == active) {
    return;
  }
  m_active = active;
  if (!m_active && m_unloadWhenInactive) {
    // Free blur render targets while backdrop is inactive to drop VRAM usage.
    m_wallpaperRenderer.makeCurrent();
    destroyFbos();
  }
}

void BackdropSurface::setWallpaperState(TextureId tex, float imgW, float imgH, WallpaperFillMode fillMode) {
  m_wallpaperRenderer.setTransitionState(tex, {}, imgW, imgH, 0.0f, 0.0f, 0.0f, WallpaperTransition::Fade, fillMode,
                                         TransitionParams{});
}

void BackdropSurface::ensurePrograms() {
  if (!m_blitProgram.isValid()) {
    m_blitProgram.create(kVertexShader, kBlitFragment);
  }
  if (!m_tintProgram.isValid()) {
    m_tintProgram.create(kVertexShader, kTintFragment);
  }
  m_blurProgram.ensureInitialized();
}

void BackdropSurface::ensureFbos() {
  if (m_fbo1 != 0 || m_bufW == 0 || m_bufH == 0) {
    return;
  }

  auto createFbo = [this](GLuint& fbo, TextureHandle& texture, std::uint32_t w, std::uint32_t h) {
    texture = m_textureManager.createEmpty(static_cast<int>(w), static_cast<int>(h), TextureDataFormat::Rgba,
                                           TextureFilter::Linear);
    if (texture.id == 0) {
      return;
    }

    glGenFramebuffers(1, &fbo);
    if (fbo == 0) {
      m_textureManager.unload(texture);
      return;
    }
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, static_cast<GLuint>(texture.id.value()),
                           0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
      glBindFramebuffer(GL_FRAMEBUFFER, 0);
      glDeleteFramebuffers(1, &fbo);
      fbo = 0;
      m_textureManager.unload(texture);
      return;
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
  };

  createFbo(m_fbo1, m_fboTex1, m_bufW, m_bufH);
  createFbo(m_fbo2, m_fboTex2, m_bufW, m_bufH);
}

void BackdropSurface::destroyFbos() {
  if (m_fbo1 != 0) {
    glDeleteFramebuffers(1, &m_fbo1);
    m_fbo1 = 0;
  }
  m_textureManager.unload(m_fboTex1);
  if (m_fbo2 != 0) {
    glDeleteFramebuffers(1, &m_fbo2);
    m_fbo2 = 0;
  }
  m_textureManager.unload(m_fboTex2);
}
