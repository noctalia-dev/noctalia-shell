#pragma once

#include "render/Renderer.hpp"

class SoftwareBarRenderer final : public Renderer {
public:
    [[nodiscard]] const char* name() const noexcept override;
    [[nodiscard]] bool usesSharedMemory() const noexcept override;

    void bind(wl_display* display, wl_surface* surface) override;
    void resize(std::uint32_t width, std::uint32_t height) override;

    void render(std::span<std::uint32_t> pixels,
                std::uint32_t width,
                std::uint32_t height) override;
};
