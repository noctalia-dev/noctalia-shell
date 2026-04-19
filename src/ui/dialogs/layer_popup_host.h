#pragma once

#include <cstdint>
#include <functional>
#include <optional>
#include <vector>

struct wl_output;
struct wl_surface;
struct zwlr_layer_surface_v1;

struct LayerPopupParentContext {
  wl_surface* surface = nullptr;
  zwlr_layer_surface_v1* layerSurface = nullptr;
  wl_output* output = nullptr;
  std::uint32_t width = 0;
  std::uint32_t height = 0;
};

class LayerPopupHostRegistry {
public:
  using ContextResolver = std::function<std::optional<LayerPopupParentContext>(wl_surface*)>;
  using PopupHook = std::function<void(wl_surface*)>;
  using FallbackResolver = std::function<std::optional<LayerPopupParentContext>()>;

  void registerHost(ContextResolver contextResolver, PopupHook beginAttachedPopup = {}, PopupHook endAttachedPopup = {},
                    FallbackResolver fallbackResolver = {});

  [[nodiscard]] std::optional<LayerPopupParentContext> contextForSurface(wl_surface* surface) const;
  [[nodiscard]] std::optional<LayerPopupParentContext> fallbackContext() const;

  void beginAttachedPopup(wl_surface* surface) const;
  void endAttachedPopup(wl_surface* surface) const;

private:
  struct Host {
    ContextResolver contextResolver;
    PopupHook beginAttachedPopup;
    PopupHook endAttachedPopup;
    FallbackResolver fallbackResolver;
  };

  std::vector<Host> m_hosts;
};
