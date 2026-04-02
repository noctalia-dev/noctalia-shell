#include "render/RendererFactory.hpp"

#include "render/GlRenderer.hpp"
#include "render/Renderer.hpp"
#include "render/SoftwareBarRenderer.hpp"

#include <cstdlib>
#include <iostream>
#include <memory>
#include <string_view>
#include <stdexcept>

std::unique_ptr<Renderer> createBarRenderer(wl_display* display, wl_surface* surface) {
    const char* requestedBackend = std::getenv("NOCTALIA_RENDERER");
    const std::string_view backend = (requestedBackend != nullptr) ? requestedBackend : "";

    if (backend == "software") {
        auto renderer = std::make_unique<SoftwareBarRenderer>();
        renderer->bind(display, surface);
        std::cout << "[noctalia] renderer: " << renderer->name() << " (forced)\n";
        return renderer;
    }

    try {
        auto renderer = std::make_unique<GlRenderer>();
        renderer->bind(display, surface);
        std::cout << "[noctalia] renderer: " << renderer->name();
        if (backend == "gl") {
            std::cout << " (forced)";
        }
        std::cout << '\n';
        return renderer;
    } catch (const std::exception& e) {
        if (backend == "gl") {
            throw;
        }

        std::cout << "[noctalia] renderer fallback: " << e.what() << '\n';
        auto renderer = std::make_unique<SoftwareBarRenderer>();
        renderer->bind(display, surface);
        std::cout << "[noctalia] renderer: " << renderer->name() << '\n';
        return renderer;
    }
}
