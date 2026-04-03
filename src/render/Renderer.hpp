#pragma once

#include <cstdint>
#include <string_view>

class Node;
struct wl_display;
struct wl_surface;

struct TextMetrics {
    float width = 0.0f;
    float top = 0.0f;
    float bottom = 0.0f;
};

class Renderer {
public:
    virtual ~Renderer() = default;

    [[nodiscard]] virtual const char* name() const noexcept = 0;

    virtual void bind(wl_display* display, wl_surface* surface) = 0;
    virtual void resize(std::uint32_t width, std::uint32_t height) = 0;
    virtual void render(std::uint32_t width, std::uint32_t height) = 0;
    virtual void setScene(Node* root) = 0;
    [[nodiscard]] virtual TextMetrics measureText(std::string_view text, float fontSize) = 0;
};
