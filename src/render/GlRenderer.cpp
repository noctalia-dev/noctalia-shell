#include "render/GlRenderer.hpp"

#include <array>
#include <cstdint>
#include <stdexcept>

#if NOCTALIA_HAVE_EGL
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <wayland-egl.h>
#endif

namespace {

#if NOCTALIA_HAVE_EGL
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

constexpr char kVertexShaderSource[] = R"(
attribute vec2 a_position;

void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
}
)";

constexpr char kFragmentShaderSource[] = R"(
precision mediump float;

uniform vec3 u_color;

void main() {
    gl_FragColor = vec4(u_color, 1.0);
}
)";
#endif

} // namespace

GlRenderer::GlRenderer() {
#if !NOCTALIA_HAVE_EGL
    throw std::runtime_error("OpenGL/EGL support was not compiled in");
#endif
}

GlRenderer::~GlRenderer() {
    cleanup();
}

const char* GlRenderer::name() const noexcept {
    return "gl";
}

bool GlRenderer::usesSharedMemory() const noexcept {
    return false;
}

void GlRenderer::bind(wl_display* display, wl_surface* surface) {
#if NOCTALIA_HAVE_EGL
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
#else
    (void)display;
    (void)surface;
    throw std::runtime_error("OpenGL/EGL support was not compiled in");
#endif
}

void GlRenderer::resize(std::uint32_t width, std::uint32_t height) {
#if NOCTALIA_HAVE_EGL
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

    ensureProgram();
#else
    (void)width;
    (void)height;
#endif
}

void GlRenderer::render(std::span<std::uint32_t> /*pixels*/,
                        std::uint32_t width,
                        std::uint32_t height) {
#if NOCTALIA_HAVE_EGL
    if (m_eglDisplay == EGL_NO_DISPLAY || m_eglSurface == EGL_NO_SURFACE || m_eglContext == EGL_NO_CONTEXT) {
        throw std::runtime_error("OpenGL renderer is not ready");
    }

    if (eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext) != EGL_TRUE) {
        throw std::runtime_error("eglMakeCurrent failed");
    }

    glViewport(0, 0, static_cast<GLint>(width), static_cast<GLint>(height));
    glClearColor(0.07f, 0.10f, 0.14f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    drawRect(10.0f, 6.0f, static_cast<float>(width) - 20.0f, static_cast<float>(height) - 12.0f,
             0.09f, 0.14f, 0.19f);
    drawRect(18.0f, 12.0f, 116.0f, 4.0f, 0.41f, 0.84f, 1.0f);
    drawRect(104.0f, 12.0f, 30.0f, 4.0f, 0.85f, 0.91f, 1.0f);

    if (eglSwapBuffers(m_eglDisplay, m_eglSurface) != EGL_TRUE) {
        throw std::runtime_error("eglSwapBuffers failed");
    }
#else
    (void)width;
    (void)height;
    throw std::runtime_error("OpenGL/EGL support was not compiled in");
#endif
}

void GlRenderer::ensureProgram() {
#if NOCTALIA_HAVE_EGL
    if (m_program.isValid()) {
        return;
    }

    m_program.create(kVertexShaderSource, kFragmentShaderSource);
    m_positionLocation = glGetAttribLocation(m_program.id(), "a_position");
    m_colorLocation = glGetUniformLocation(m_program.id(), "u_color");

    if (m_positionLocation < 0 || m_colorLocation < 0) {
        throw std::runtime_error("failed to query shader attribute/uniform locations");
    }
#endif
}

void GlRenderer::drawRect(float x,
                          float y,
                          float width,
                          float height,
                          float red,
                          float green,
                          float blue) const {
#if NOCTALIA_HAVE_EGL
    if (width <= 0.0f || height <= 0.0f) {
        return;
    }

    EGLint surfaceWidth = 0;
    EGLint surfaceHeight = 0;
    eglQuerySurface(m_eglDisplay, m_eglSurface, EGL_WIDTH, &surfaceWidth);
    eglQuerySurface(m_eglDisplay, m_eglSurface, EGL_HEIGHT, &surfaceHeight);

    if (surfaceWidth <= 0 || surfaceHeight <= 0) {
        return;
    }

    const auto toNdcX = [surfaceWidth](float value) {
        return (value / static_cast<float>(surfaceWidth)) * 2.0f - 1.0f;
    };
    const auto toNdcY = [surfaceHeight](float value) {
        return 1.0f - (value / static_cast<float>(surfaceHeight)) * 2.0f;
    };

    const std::array<GLfloat, 12> vertices = {
        toNdcX(x),         toNdcY(y),
        toNdcX(x + width), toNdcY(y),
        toNdcX(x),         toNdcY(y + height),
        toNdcX(x),         toNdcY(y + height),
        toNdcX(x + width), toNdcY(y),
        toNdcX(x + width), toNdcY(y + height),
    };

    glUseProgram(m_program.id());
    glUniform3f(m_colorLocation, red, green, blue);
    glVertexAttribPointer(m_positionLocation, 2, GL_FLOAT, GL_FALSE, 0, vertices.data());
    glEnableVertexAttribArray(m_positionLocation);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(m_positionLocation);
#else
    (void)x;
    (void)y;
    (void)width;
    (void)height;
    (void)red;
    (void)green;
    (void)blue;
#endif
}

void GlRenderer::cleanup() {
#if NOCTALIA_HAVE_EGL
    m_program.destroy();
    m_positionLocation = -1;
    m_colorLocation = -1;

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
#endif
}
