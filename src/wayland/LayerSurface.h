#pragma once

#include "wayland/Surface.h"

#include <cstdint>
#include <string>

struct wl_output;
struct zwlr_layer_surface_v1;

enum class LayerShellLayer : std::uint32_t {
  Background = 0,
  Bottom = 1,
  Top = 2,
  Overlay = 3,
};

enum class LayerShellKeyboard : std::uint32_t {
  None = 0,
  Exclusive = 1,
  OnDemand = 2,
};

namespace LayerShellAnchor {
inline constexpr std::uint32_t Top = 1;
inline constexpr std::uint32_t Bottom = 2;
inline constexpr std::uint32_t Left = 4;
inline constexpr std::uint32_t Right = 8;
} // namespace LayerShellAnchor

struct LayerSurfaceConfig {
  std::string nameSpace = "noctalia";
  LayerShellLayer layer = LayerShellLayer::Top;
  std::uint32_t anchor = 0;
  std::uint32_t width = 0;
  std::uint32_t height = 0;
  std::int32_t exclusiveZone = 0;
  std::int32_t marginTop = 0;
  std::int32_t marginRight = 0;
  std::int32_t marginBottom = 0;
  std::int32_t marginLeft = 0;
  LayerShellKeyboard keyboard = LayerShellKeyboard::None;
  std::uint32_t defaultWidth = 1920;
  std::uint32_t defaultHeight = 0;
};

class LayerSurface : public Surface {
public:
  LayerSurface(WaylandConnection& connection, LayerSurfaceConfig config);
  ~LayerSurface() override;

  bool initialize() override;
  bool initialize(wl_output* output, std::int32_t scale);

  static void handleConfigure(void* data, zwlr_layer_surface_v1* layerSurface, std::uint32_t serial,
                              std::uint32_t width, std::uint32_t height);
  static void handleClosed(void* data, zwlr_layer_surface_v1* layerSurface);

private:
  LayerSurfaceConfig m_config;
  zwlr_layer_surface_v1* m_layerSurface = nullptr;
};
