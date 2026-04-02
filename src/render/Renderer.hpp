#pragma once

#include <cstdint>
#include <span>

struct wl_display;
struct wl_surface;

class Renderer {
public:
    virtual ~Renderer() = default;

    [[nodiscard]] virtual const char* name() const noexcept = 0;
    [[nodiscard]] virtual bool usesSharedMemory() const noexcept = 0;

    virtual void bind(wl_display* display, wl_surface* surface) = 0;
    virtual void resize(std::uint32_t width, std::uint32_t height) = 0;

    virtual void render(std::span<std::uint32_t> pixels,
                        std::uint32_t width,
                        std::uint32_t height) = 0;
};
