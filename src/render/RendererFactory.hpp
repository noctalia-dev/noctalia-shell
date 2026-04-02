#pragma once

#include <memory>

class Renderer;
struct wl_display;
struct wl_surface;

std::unique_ptr<Renderer> createBarRenderer(wl_display* display, wl_surface* surface);
