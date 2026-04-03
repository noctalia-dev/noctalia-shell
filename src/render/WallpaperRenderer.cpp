#include "render/WallpaperRenderer.hpp"

#include <stdexcept>

#include <GLES2/gl2.h>
#include <wayland-egl.h>

namespace {

constexpr EGLint kConfigAttributes[] = {
    EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
    EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
    EGL_RED_SIZE, 8,
    EGL_GREEN_SIZE, 8,
    EGL_BLUE_SIZE, 8,
    EGL_ALPHA_SIZE, 8,
    EGL_NONE,
};

constexpr EGLint kContextAttributes[] = {
    EGL_CONTEXT_CLIENT_VERSION, 2,
    EGL_NONE,
};

} // namespace

WallpaperRenderer::WallpaperRenderer() = default;

WallpaperRenderer::~WallpaperRenderer() {
    cleanup();
}

const char* WallpaperRenderer::name() const noexcept {
    return "wallpaper";
}

void WallpaperRenderer::bind(wl_display* display, wl_surface* surface) {
    if (display == nullptr || surface == nullptr) {
        throw std::runtime_error("wallpaper renderer requires a valid Wayland display and surface");
    }

    m_display = display;
    m_surface = surface;

    m_eglDisplay = eglGetDisplay(reinterpret_cast<EGLNativeDisplayType>(display));
    if (m_eglDisplay == EGL_NO_DISPLAY) {
        throw std::runtime_error("eglGetDisplay failed");
    }

    EGLint major = 0;
    EGLint minor = 0;
    if (eglInitialize(m_eglDisplay, &major, &minor) != EGL_TRUE) {
        throw std::runtime_error("eglInitialize failed");
    }

    if (eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE) {
        throw std::runtime_error("eglBindAPI failed");
    }

    EGLint configCount = 0;
    if (eglChooseConfig(m_eglDisplay, kConfigAttributes, &m_eglConfig, 1, &configCount) != EGL_TRUE ||
        configCount != 1) {
        throw std::runtime_error("eglChooseConfig failed");
    }

    m_eglContext = eglCreateContext(m_eglDisplay, m_eglConfig, EGL_NO_CONTEXT, kContextAttributes);
    if (m_eglContext == EGL_NO_CONTEXT) {
        throw std::runtime_error("eglCreateContext failed");
    }
}

void WallpaperRenderer::makeCurrent() {
    if (m_eglDisplay != EGL_NO_DISPLAY && m_eglSurface != EGL_NO_SURFACE && m_eglContext != EGL_NO_CONTEXT) {
        eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext);
    }
}

void WallpaperRenderer::resize(std::uint32_t bufferWidth, std::uint32_t bufferHeight,
                                std::uint32_t logicalWidth, std::uint32_t logicalHeight) {
    if (bufferWidth == 0 || bufferHeight == 0) {
        return;
    }

    if (m_surface == nullptr || m_eglDisplay == EGL_NO_DISPLAY || m_eglContext == EGL_NO_CONTEXT) {
        throw std::runtime_error("wallpaper renderer is not bound");
    }

    if (m_window == nullptr) {
        m_window = wl_egl_window_create(
            m_surface,
            static_cast<int>(bufferWidth),
            static_cast<int>(bufferHeight));
        if (m_window == nullptr) {
            throw std::runtime_error("wl_egl_window_create failed");
        }

        m_eglSurface = eglCreateWindowSurface(
            m_eglDisplay, m_eglConfig,
            reinterpret_cast<EGLNativeWindowType>(m_window),
            nullptr);
        if (m_eglSurface == EGL_NO_SURFACE) {
            throw std::runtime_error("eglCreateWindowSurface failed");
        }
    } else {
        wl_egl_window_resize(m_window,
            static_cast<int>(bufferWidth),
            static_cast<int>(bufferHeight), 0, 0);
    }

    eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext);

    m_bufferWidth = bufferWidth;
    m_bufferHeight = bufferHeight;
    m_logicalWidth = logicalWidth;
    m_logicalHeight = logicalHeight;

    glViewport(0, 0, static_cast<GLsizei>(bufferWidth), static_cast<GLsizei>(bufferHeight));

    m_program.ensureInitialized();
}

void WallpaperRenderer::render() {
    if (m_eglSurface == EGL_NO_SURFACE || m_tex1 == 0) {
        return;
    }

    eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext);
    glViewport(0, 0, static_cast<GLsizei>(m_bufferWidth), static_cast<GLsizei>(m_bufferHeight));
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    auto sw = static_cast<float>(m_logicalWidth);
    auto sh = static_cast<float>(m_logicalHeight);

    // If no second texture, just draw the first using fade at progress 0
    GLuint tex2 = (m_tex2 != 0) ? m_tex2 : m_tex1;
    float progress = (m_tex2 != 0) ? m_progress : 0.0f;

    m_program.draw(m_transition, m_tex1, tex2,
                   sw, sh,
                   m_imgW1, m_imgH1,
                   m_imgW2, m_imgH2,
                   progress,
                   static_cast<float>(m_fillMode),
                   m_params);

    eglSwapBuffers(m_eglDisplay, m_eglSurface);
}

void WallpaperRenderer::setScene(Node* /*root*/) {
    // Not used by wallpaper renderer
}

TextMetrics WallpaperRenderer::measureText(std::string_view /*text*/, float /*fontSize*/) {
    return {};
}

TextureManager& WallpaperRenderer::textureManager() {
    return m_textureManager;
}

void WallpaperRenderer::setTransitionState(GLuint tex1, GLuint tex2,
                                            float imgW1, float imgH1,
                                            float imgW2, float imgH2,
                                            float progress,
                                            WallpaperTransition transition,
                                            WallpaperFillMode fillMode,
                                            const TransitionParams& params) {
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
    m_program.destroy();
    m_textureManager.cleanup();

    if (m_eglDisplay != EGL_NO_DISPLAY) {
        eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (m_eglSurface != EGL_NO_SURFACE) {
            eglDestroySurface(m_eglDisplay, m_eglSurface);
        }
        if (m_eglContext != EGL_NO_CONTEXT) {
            eglDestroyContext(m_eglDisplay, m_eglContext);
        }
        eglTerminate(m_eglDisplay);
    }

    if (m_window != nullptr) {
        wl_egl_window_destroy(m_window);
    }
}
