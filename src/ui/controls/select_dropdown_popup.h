#pragma once

#include "config/config_types.h"
#include "render/scene/input_dispatcher.h"
#include "ui/controls/select_popup_context.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

class Glyph;
class Label;
class Node;
class PopupSurface;
class RectNode;
class RenderContext;
class WaylandConnection;
struct KeyboardEvent;
struct PointerEvent;
struct wl_output;
struct wl_surface;
struct xdg_surface;
struct zwlr_layer_surface_v1;

class SelectDropdownPopup : public SelectPopupContext {
public:
  SelectDropdownPopup(WaylandConnection& wayland, RenderContext& renderContext);
  ~SelectDropdownPopup() override;

  void setParent(zwlr_layer_surface_v1* layerSurface, wl_output* output);
  void setParent(xdg_surface* xdgSurface, wl_output* output);
  void setShadowConfig(const ShellConfig::ShadowConfig& shadow);

  void openSelectDropdown(const DropdownRequest& request, DropdownCallbacks callbacks) override;
  void closeSelectDropdown() override;
  [[nodiscard]] bool isSelectDropdownOpen() const override;

  [[nodiscard]] bool onPointerEvent(const PointerEvent& event);
  void onKeyboardEvent(const KeyboardEvent& event);

  [[nodiscard]] wl_surface* wlSurface() const noexcept;

private:
  struct OptionView {
    RectNode* background = nullptr;
    Label* label = nullptr;
    Glyph* checkGlyph = nullptr;
  };

  void buildScene(const DropdownRequest& request);
  void handleKey(std::uint32_t sym, std::uint32_t utf32, bool pressed);
  void invalidateScene();
  void scrollBy(float delta);
  void clampScrollOffset();
  void applyHoverVisuals();
  void selectAndClose(std::size_t index);

  WaylandConnection& m_wayland;
  RenderContext& m_renderContext;
  zwlr_layer_surface_v1* m_parentLayerSurface = nullptr;
  xdg_surface* m_parentXdgSurface = nullptr;
  wl_output* m_parentOutput = nullptr;

  std::unique_ptr<PopupSurface> m_surface;
  std::unique_ptr<Node> m_sceneRoot;
  InputDispatcher m_inputDispatcher;
  wl_surface* m_wlSurface = nullptr;
  bool m_pointerInside = false;

  DropdownCallbacks m_callbacks;
  std::vector<std::string> m_options;
  std::vector<OptionView> m_optionViews;
  std::size_t m_selectedIndex = static_cast<std::size_t>(-1);
  std::size_t m_hoveredIndex = static_cast<std::size_t>(-1);
  float m_optionHeight = 0.0f;
  float m_scrollOffset = 0.0f;
  float m_viewportHeight = 0.0f;
  float m_totalHeight = 0.0f;
  float m_menuWidth = 0.0f;
  ShellConfig::ShadowConfig m_shadowConfig;
  bool m_sceneDirty = false;
  bool m_openInProgress = false;
  bool m_closeRequestedDuringOpen = false;
};
