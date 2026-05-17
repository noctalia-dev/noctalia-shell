#pragma once

#include "core/timer_manager.h"
#include "render/animation/animation_manager.h"
#include "shell/tooltip/tooltip_content.h"
#include "ui/signal.h"

#include <memory>

class Box;
class Flex;
class InputArea;
class Label;
class Node;
class PopupSurface;
class RenderContext;
class WaylandConnection;
struct wl_output;
struct zwlr_layer_surface_v1;

class TooltipManager {
public:
  static TooltipManager& instance();

  void initialize(WaylandConnection& wayland, RenderContext* renderContext);

  void onHoverChange(InputArea* area, zwlr_layer_surface_v1* parentLayerSurface, wl_output* output);

private:
  TooltipManager() = default;

  enum class State { Idle, Pending, Showing, FadingOut };

  struct Size {
    std::uint32_t w = 0;
    std::uint32_t h = 0;
  };

  void showPopup();
  void dismissPopup();
  void destroyPopup();
  Size measureContent(const TooltipContent& content);
  void buildScene(const TooltipContent& content, float w, float h);
  void prepareFrame(bool needsUpdate, bool needsLayout);

  WaylandConnection* m_wayland = nullptr;
  RenderContext* m_renderContext = nullptr;

  State m_state = State::Idle;
  Timer m_showTimer;

  TooltipContent m_pendingContent;
  zwlr_layer_surface_v1* m_pendingParent = nullptr;
  wl_output* m_pendingOutput = nullptr;
  InputArea* m_pendingArea = nullptr;

  std::unique_ptr<PopupSurface> m_surface;
  AnimationManager m_animations;
  std::unique_ptr<Node> m_sceneRoot;
  AnimationManager::Id m_fadeAnimId = 0;

  Signal<>::ScopedConnection m_paletteConn;
};
