#pragma once

#include "config/config_types.h"
#include "render/scene/input_dispatcher.h"
#include "shell/dock/dock_items.h"
#include "shell/dock/dock_model.h"
#include "ui/signal.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <vector>

class Box;
class CompositorPlatform;
class ConfigService;
class Flex;
class LayerSurface;
class Node;
class RenderContext;
struct wl_output;

namespace shell::dock {

  struct DockInstance {
    std::uint32_t outputName = 0;
    wl_output* output = nullptr;
    std::int32_t scale = 1;
    std::unique_ptr<LayerSurface> surface;
    // sceneRoot must be destroyed before `animations` — ~Node() calls cancelForOwner().
    AnimationManager animations;
    std::unique_ptr<Node> sceneRoot;
    Node* slideRoot = nullptr;
    float slideHiddenDx = 0.0f;
    float slideHiddenDy = 0.0f;
    Box* shadow = nullptr;
    Box* panel = nullptr;
    Flex* row = nullptr;
    InputDispatcher inputDispatcher;
    std::vector<shell::dock::DockItemView> items;
    DockSnapshot snapshot;
    bool pointerInside = false;
    float hoverPointerMain = 0.0f;
    bool hoverPointerValid = false;
    InputArea* launcherArea = nullptr;
    Node* launcherIconNode = nullptr;
    float launcherRestMainPos = 0.0f;
    float launcherRestCrossPos = 0.0f;
    float launcherHoverMainOffset = 0.0f;
    float launcherVisualScale = -1.0f;
    AnimationManager::Id launcherScaleAnimId = 0;
    // Auto-hide: tracks visibility [0,1] driven by hover.
    float hideOpacity = 1.0f;
    AnimationManager::Id hideAnimId = 0;
    Signal<>::ScopedConnection paletteConn;
  };

  struct DockInstanceDependencies {
    CompositorPlatform& platform;
    ConfigService& config;
    RenderContext& renderContext;
  };

  struct DockInstanceCallbacks {
    std::function<bool(DockInstance&)> syncModel;
    std::function<void(DockInstance&)> rebuildItems;
    std::function<void(DockInstance&)> updateVisuals;
  };

  void prepareFrame(
      DockInstance& instance, DockInstanceDependencies deps, const DockInstanceCallbacks& callbacks, bool needsUpdate,
      bool needsLayout
  );
  void buildScene(DockInstance& instance, DockInstanceDependencies deps, const DockInstanceCallbacks& callbacks);
  void resizeSurface(DockInstance& instance, const DockConfig& cfg, const ShellConfig::ShadowConfig& shadowConfig);
  void applyPanelPalette(DockInstance& instance, const DockConfig& cfg);
  void syncDockSlideLayerTransform(DockInstance& instance, const DockConfig& cfg);
  void applyDockCompositorBlur(DockInstance& instance, const DockConfig& cfg);
  void startHideFadeOut(DockInstance& instance, ConfigService& config);

} // namespace shell::dock
