#include "render/SoftwareBarRenderer.hpp"

#include <algorithm>
#include <cstddef>

namespace {

constexpr std::uint32_t kBackgroundColor = 0x00121A24u;
constexpr std::uint32_t kAccentColor = 0x0068D5FFu;
constexpr std::uint32_t kHighlightColor = 0x00D9E7FFu;

} // namespace

const char* SoftwareBarRenderer::name() const noexcept {
    return "software";
}

bool SoftwareBarRenderer::usesSharedMemory() const noexcept {
    return true;
}

void SoftwareBarRenderer::bind(wl_display* /*display*/, wl_surface* /*surface*/) {}

void SoftwareBarRenderer::resize(std::uint32_t /*width*/, std::uint32_t /*height*/) {}

void SoftwareBarRenderer::render(std::span<std::uint32_t> pixels,
                                 std::uint32_t width,
                                 std::uint32_t height) {
    std::fill(pixels.begin(), pixels.end(), kBackgroundColor);

    if (width == 0 || height == 0) {
        return;
    }

    const std::uint32_t accentWidth = std::min<std::uint32_t>(width, 96);
    const std::uint32_t accentHeight = std::min<std::uint32_t>(height, 4);
    const std::uint32_t highlightStart = std::min<std::uint32_t>(accentWidth, 72);

    for (std::uint32_t y = 0; y < accentHeight; ++y) {
        for (std::uint32_t x = 0; x < accentWidth; ++x) {
            const std::size_t index =
                static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + x;
            pixels[index] = (x >= highlightStart) ? kHighlightColor : kAccentColor;
        }
    }
}
