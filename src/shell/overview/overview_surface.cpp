#include "shell/overview/overview_surface.h"

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
    gl_FragColor = texture2D(u_texture, vec2(v_texcoord.x, 1.0 - v_texcoord.y));
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

OverviewSurface::~OverviewSurface() {
  m_wallpaperRenderer.makeCurrent();
  destroyFbos();
  m_blurProgram.destroy();
  m_blitProgram.destroy();
  m_tintProgram.destroy();
}

bool OverviewSurface::createWlSurface() {
  m_surface = wl_compositor_create_surface(m_connection.compositor());
  if (m_surface == nullptr) {
    return false;
  }

  m_wallpaperRenderer.bind(m_connection.display(), m_surface, m_shareContext);
  return true;
}

void OverviewSurface::onConfigure(std::uint32_t width, std::uint32_t height) {
  const auto bw = width * static_cast<std::uint32_t>(bufferScale());
  const auto bh = height * static_cast<std::uint32_t>(bufferScale());

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

void OverviewSurface::render() {
  if (m_surface == nullptr) {
    return;
  }

  requestFrame();

  // 3 rounds of H+V blur gives effective sigma ≈ radius * sqrt(3), much stronger result.
  static constexpr int kBlurRounds = 3;
  const float blurRadius = m_blurIntensity * 40.0f;

  if (blurRadius < 0.5f) {
    // No blur — render wallpaper directly to screen, then tint
    m_wallpaperRenderer.renderToFbo(0);

    if (m_tintIntensity > 0.001f) {
      ensurePrograms();
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

    m_wallpaperRenderer.swapBuffers();
    return;
  }

  // Blur path — render wallpaper to FBO1, then kBlurRounds × (H blur FBO1→FBO2, V blur FBO2→FBO1)
  ensurePrograms();
  ensureFbos();

  // Pass 1: wallpaper → FBO1
  m_wallpaperRenderer.renderToFbo(m_fbo1);

  glViewport(0, 0, static_cast<GLsizei>(m_bufW), static_cast<GLsizei>(m_bufH));
  glDisable(GL_BLEND);

  for (int round = 0; round < kBlurRounds; ++round) {
    // Horizontal blur FBO1.tex → FBO2
    glBindFramebuffer(GL_FRAMEBUFFER, m_fbo2);
    m_blurProgram.draw(m_fboTex1, m_bufW, m_bufH, 1.0f, 0.0f, blurRadius);

    // Vertical blur FBO2.tex → FBO1
    glBindFramebuffer(GL_FRAMEBUFFER, m_fbo1);
    m_blurProgram.draw(m_fboTex2, m_bufW, m_bufH, 0.0f, 1.0f, blurRadius);
  }

  // Blit blurred result to screen
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(0, 0, static_cast<GLsizei>(m_bufW), static_cast<GLsizei>(m_bufH));
  glDisable(GL_BLEND);

  {
    glUseProgram(m_blitProgram.id());
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, m_fboTex1);
    GLint texLoc = glGetUniformLocation(m_blitProgram.id(), "u_texture");
    glUniform1i(texLoc, 0);
    GLint posAttr = glGetAttribLocation(m_blitProgram.id(), "a_position");
    static constexpr float kQuad[] = {
        0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f,
    };
    glVertexAttribPointer(static_cast<GLuint>(posAttr), 2, GL_FLOAT, GL_FALSE, 0, kQuad);
    glEnableVertexAttribArray(static_cast<GLuint>(posAttr));
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(static_cast<GLuint>(posAttr));
  }

  if (m_tintIntensity > 0.001f) {
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

  m_wallpaperRenderer.swapBuffers();
}

void OverviewSurface::setWallpaperState(GLuint tex, float imgW, float imgH, WallpaperFillMode fillMode) {
  m_wallpaperRenderer.setTransitionState(tex, 0, imgW, imgH, 0.0f, 0.0f, 0.0f, WallpaperTransition::Fade, fillMode,
                                         TransitionParams{});
}

void OverviewSurface::ensurePrograms() {
  if (!m_blitProgram.isValid()) {
    m_blitProgram.create(kVertexShader, kBlitFragment);
  }
  if (!m_tintProgram.isValid()) {
    m_tintProgram.create(kVertexShader, kTintFragment);
  }
  m_blurProgram.ensureInitialized();
}

void OverviewSurface::ensureFbos() {
  if (m_fbo1 != 0 || m_bufW == 0 || m_bufH == 0) {
    return;
  }

  auto createFbo = [](GLuint& fbo, GLuint& tex, std::uint32_t w, std::uint32_t h) {
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, static_cast<GLsizei>(w), static_cast<GLsizei>(h), 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D, 0);

    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
  };

  createFbo(m_fbo1, m_fboTex1, m_bufW, m_bufH);
  createFbo(m_fbo2, m_fboTex2, m_bufW, m_bufH);
}

void OverviewSurface::destroyFbos() {
  if (m_fbo1 != 0) {
    glDeleteFramebuffers(1, &m_fbo1);
    glDeleteTextures(1, &m_fboTex1);
    m_fbo1 = 0;
    m_fboTex1 = 0;
  }
  if (m_fbo2 != 0) {
    glDeleteFramebuffers(1, &m_fbo2);
    glDeleteTextures(1, &m_fboTex2);
    m_fbo2 = 0;
    m_fboTex2 = 0;
  }
}
