#include "render/GlRenderer.hpp"
#include "render/Palette.hpp"
#include "render/scene/Node.hpp"
#include "render/scene/RectNode.hpp"
#include "render/scene/TextNode.hpp"
#include "render/scene/ImageNode.hpp"

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
    EGL_ALPHA_SIZE, 8,
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
    m_linearGradientProgram.ensureInitialized();
    m_roundedRectProgram.ensureInitialized();
    const auto fontPath = m_fontService.resolvePath("sans-serif");
    m_textRenderer.initialize(fontPath.c_str());
}

void GlRenderer::render(std::uint32_t width, std::uint32_t height) {
    if (m_eglDisplay == EGL_NO_DISPLAY || m_eglSurface == EGL_NO_SURFACE || m_eglContext == EGL_NO_CONTEXT) {
        throw std::runtime_error("OpenGL renderer is not ready");
    }

    if (eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext) != EGL_TRUE) {
        throw std::runtime_error("eglMakeCurrent failed");
    }

    glViewport(0, 0, static_cast<GLint>(width), static_cast<GLint>(height));
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    if (m_sceneRoot != nullptr) {
        renderNode(m_sceneRoot, 0.0f, 0.0f, 1.0f);
    }

    if (eglSwapBuffers(m_eglDisplay, m_eglSurface) != EGL_TRUE) {
        throw std::runtime_error("eglSwapBuffers failed");
    }
}

void GlRenderer::setScene(Node* root) {
    m_sceneRoot = root;
}

TextMetrics GlRenderer::measureText(std::string_view text, float fontSize) {
    auto m = m_textRenderer.measure(text, fontSize);
    return TextMetrics{.width = m.width, .top = m.top, .bottom = m.bottom};
}

void GlRenderer::renderNode(const Node* node, float parentX, float parentY, float parentOpacity) {
    if (!node->visible()) {
        return;
    }

    const float absX = parentX + node->x();
    const float absY = parentY + node->y();
    const float effectiveOpacity = parentOpacity * node->opacity();

    const auto sw = static_cast<float>(m_surfaceWidth);
    const auto sh = static_cast<float>(m_surfaceHeight);

    switch (node->type()) {
    case NodeType::Rect: {
        const auto* rect = static_cast<const RectNode*>(node);
        auto style = rect->style();
        style.fill.a *= effectiveOpacity;
        style.fillEnd.a *= effectiveOpacity;
        style.border.a *= effectiveOpacity;
        m_roundedRectProgram.draw(sw, sh, absX, absY, node->width(), node->height(), style);
        break;
    }
    case NodeType::Text: {
        const auto* text = static_cast<const TextNode*>(node);
        if (!text->text().empty()) {
            auto color = text->color();
            color.a *= effectiveOpacity;
            m_textRenderer.draw(sw, sh, absX, absY, text->text(), text->fontSize(), color);
        }
        break;
    }
    case NodeType::Image:
        // Placeholder -- image loading not yet implemented
        break;
    case NodeType::Base:
        break;
    }

    for (const auto& child : node->children()) {
        renderNode(child.get(), absX, absY, effectiveOpacity);
    }
}

void GlRenderer::cleanup() {
    m_linearGradientProgram.destroy();
    m_roundedRectProgram.destroy();
    m_textRenderer.cleanup();
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
