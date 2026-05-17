#pragma once

#include "render/animation/animation_manager.h"
#include "ui/controls/progress_bar.h"
#include "wayland/layer_surface.h"

#include <memory>
#include <string>
#include <vector>

class ConfigService;
class Box;
class Flex;
class Glyph;
class Label;
class Node;
class RenderContext;
class WaylandConnection;
struct wl_surface;

struct OsdContent {
  std::string icon;
  std::string value;
  float progress = 0.0f;
  bool showProgress = true;
};

class OsdOverlay {
public:
  OsdOverlay() = default;
  ~OsdOverlay() = default;

  OsdOverlay(const OsdOverlay&) = delete;
  OsdOverlay& operator=(const OsdOverlay&) = delete;

  void initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext);
  void requestLayout();
  void requestRedraw();

  void show(const OsdContent& content);

private:
  struct Instance {
    wl_output* output = nullptr;
    std::int32_t scale = 1;
    float uiLayoutScale = 1.0f;
    std::unique_ptr<LayerSurface> surface;
    // sceneRoot must be destroyed before `animations` — ~Node() calls cancelForOwner().
    AnimationManager animations;
    std::unique_ptr<Node> sceneRoot;
    wl_surface* wlSurface = nullptr;

    Node* card = nullptr;
    Flex* row = nullptr;
    Box* background = nullptr;
    Glyph* glyph = nullptr;
    Label* value = nullptr;
    ProgressBar* progress = nullptr;
    float progressValueMinWidth = 0.0f;
    AnimationManager::Id showAnimId = 0;
    AnimationManager::Id hideAnimId = 0;
    bool showPending = false;
    bool visible = false;
    float appliedCornerRadiusScale = -1.0f;
  };

  void ensureSurfaces();
  void destroySurfaces();
  void prepareFrame(Instance& inst, bool needsUpdate, bool needsLayout);
  void buildScene(Instance& inst, std::uint32_t width, std::uint32_t height);
  void updateInstanceContent(Instance& inst);
  void animateInstance(Instance& inst);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;
  OsdContent m_content;
  std::string m_lastPosition;
  float m_lastLayoutScale = 1.0f;
  float m_lastCornerRadiusScale = 1.0f;
  std::vector<std::unique_ptr<Instance>> m_instances;
};
