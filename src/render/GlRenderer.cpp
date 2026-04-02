#include "render/GlRenderer.hpp"

#include <cstdint>
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
    EGL_ALPHA_SIZE, 0,
    EGL_NONE,
};

constexpr EGLint kContextAttributes[] = {
    EGL_CONTEXT_CLIENT_VERSION, 2,
    EGL_NONE,
};

} // namespace

GlRenderer::GlRenderer() = default;

GlRenderer::~GlRenderer() {
    cleanup();
}

const char* GlRenderer::name() const noexcept {
    return "gl";
}

void GlRenderer::bind(wl_display* display, wl_surface* surface) {
    if (display == nullptr || surface == nullptr) {
        throw std::runtime_error("OpenGL renderer requires a valid Wayland display and surface");
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

void GlRenderer::resize(std::uint32_t width, std::uint32_t height) {
    if (width == 0 || height == 0) {
        return;
    }

    if (m_surface == nullptr || m_eglDisplay == EGL_NO_DISPLAY || m_eglContext == EGL_NO_CONTEXT) {
        throw std::runtime_error("OpenGL renderer is not bound");
    }

    if (m_window == nullptr) {
        m_window = wl_egl_window_create(
            m_surface,
            static_cast<int>(width),
            static_cast<int>(height));
        if (m_window == nullptr) {
            throw std::runtime_error("wl_egl_window_create failed");
        }
    } else {
        wl_egl_window_resize(m_window, static_cast<int>(width), static_cast<int>(height), 0, 0);
    }

    if (m_eglSurface == EGL_NO_SURFACE) {
        m_eglSurface = eglCreateWindowSurface(
            m_eglDisplay,
            m_eglConfig,
            reinterpret_cast<EGLNativeWindowType>(m_window),
            nullptr);
        if (m_eglSurface == EGL_NO_SURFACE) {
            throw std::runtime_error("eglCreateWindowSurface failed");
        }
    }

    if (eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext) != EGL_TRUE) {
        throw std::runtime_error("eglMakeCurrent failed during resize");
    }

    m_surfaceWidth = width;
    m_surfaceHeight = height;
    m_roundedRectProgram.ensureInitialized();
}

void GlRenderer::render(std::uint32_t width, std::uint32_t height) {
    if (m_eglDisplay == EGL_NO_DISPLAY || m_eglSurface == EGL_NO_SURFACE || m_eglContext == EGL_NO_CONTEXT) {
        throw std::runtime_error("OpenGL renderer is not ready");
    }

    if (eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext) != EGL_TRUE) {
        throw std::runtime_error("eglMakeCurrent failed");
    }

    glViewport(0, 0, static_cast<GLint>(width), static_cast<GLint>(height));
    glClearColor(0.07f, 0.10f, 0.14f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    m_roundedRectProgram.draw(
        static_cast<float>(m_surfaceWidth),
        static_cast<float>(m_surfaceHeight),
        10.0f,
        6.0f,
        static_cast<float>(width) - 20.0f,
        static_cast<float>(height) - 12.0f,
        RoundedRectStyle{
            .red = 0.09f,
            .green = 0.14f,
            .blue = 0.19f,
            .alpha = 1.0f,
            .radius = 10.0f,
            .softness = 1.2f,
        });
    m_roundedRectProgram.draw(
        static_cast<float>(m_surfaceWidth),
        static_cast<float>(m_surfaceHeight),
        18.0f,
        12.0f,
        116.0f,
        4.0f,
        RoundedRectStyle{
            .red = 0.41f,
            .green = 0.84f,
            .blue = 1.0f,
            .alpha = 1.0f,
            .radius = 2.0f,
            .softness = 0.8f,
        });
    m_roundedRectProgram.draw(
        static_cast<float>(m_surfaceWidth),
        static_cast<float>(m_surfaceHeight),
        104.0f,
        12.0f,
        30.0f,
        4.0f,
        RoundedRectStyle{
            .red = 0.85f,
            .green = 0.91f,
            .blue = 1.0f,
            .alpha = 1.0f,
            .radius = 2.0f,
            .softness = 0.8f,
        });

    if (eglSwapBuffers(m_eglDisplay, m_eglSurface) != EGL_TRUE) {
        throw std::runtime_error("eglSwapBuffers failed");
    }
}

void GlRenderer::cleanup() {
    m_roundedRectProgram.destroy();
    m_surfaceWidth = 0;
    m_surfaceHeight = 0;

    if (m_eglDisplay != EGL_NO_DISPLAY) {
        eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }

    if (m_eglSurface != EGL_NO_SURFACE) {
        eglDestroySurface(m_eglDisplay, m_eglSurface);
        m_eglSurface = EGL_NO_SURFACE;
    }

    if (m_window != nullptr) {
        wl_egl_window_destroy(m_window);
        m_window = nullptr;
    }

    if (m_eglContext != EGL_NO_CONTEXT) {
        eglDestroyContext(m_eglDisplay, m_eglContext);
        m_eglContext = EGL_NO_CONTEXT;
    }

    if (m_eglDisplay != EGL_NO_DISPLAY) {
        eglTerminate(m_eglDisplay);
        m_eglDisplay = EGL_NO_DISPLAY;
    }

    m_eglConfig = nullptr;
    m_display = nullptr;
    m_surface = nullptr;
}
