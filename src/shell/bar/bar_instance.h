#pragma once

#include "config/config_service.h"
#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "shell/bar/widget.h"
#include "shell/panel/attached_panel_context.h"
#include "ui/signal.h"
#include "wayland/layer_surface.h"

#include <cstdint>
#include <memory>
#include <optional>
#include <vector>

class Flex;
class Node;
class RectNode;

struct BarInstance {
  std::uint32_t outputName = 0;
  wl_output* output = nullptr;
  std::int32_t scale = 1;
  std::size_t barIndex = 0;
  BarConfig barConfig;
  std::unique_ptr<LayerSurface> surface;
  // sceneRoot must be destroyed before `animations` — ~Node() calls cancelForOwner().
  AnimationManager animations;
  std::unique_ptr<Node> sceneRoot;
  Node* slideRoot = nullptr;
  float slideHiddenDx = 0.0f;
  float slideHiddenDy = 0.0f;
  InputDispatcher inputDispatcher;
  float hideOpacity = 1.0f;
  bool pointerInside = false;
  std::size_t attachedPopupCount = 0;

  // Bar background, shadow, and layout sections (start/center/end along main axis)
  RectNode* bg = nullptr;
  RectNode* shadow = nullptr;
  Node* shadowLeftClip = nullptr;
  Node* shadowRightClip = nullptr;
  RectNode* shadowLeft = nullptr;
  RectNode* shadowRight = nullptr;
  Node* contentClip = nullptr;
  Node* startSlot = nullptr;
  Node* centerSlot = nullptr;
  Node* endSlot = nullptr;
  Flex* startSection = nullptr;
  Flex* centerSection = nullptr;
  Flex* endSection = nullptr;

  std::vector<std::unique_ptr<Widget>> startWidgets;
  std::vector<std::unique_ptr<Widget>> centerWidgets;
  std::vector<std::unique_ptr<Widget>> endWidgets;

  Signal<>::ScopedConnection paletteConn;
  std::optional<AttachedPanelGeometry> attachedPanelGeometry;
  // Set when an attached panel borrows the bar surface for keyboard focus.
  // Holds the value the bar's layer surface had before the borrow so it can be restored.
  std::optional<LayerShellKeyboard> attachedKeyboardSavedMode;
};
