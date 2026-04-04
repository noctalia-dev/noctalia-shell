#pragma once

#include "render/animation/AnimationManager.h"
#include "render/scene/InputDispatcher.h"
#include "render/scene/Node.h"
#include "shell/PanelContent.h"
#include "wayland/LayerSurface.h"

#include <memory>
#include <string>
#include <unordered_map>

class ConfigService;
class RenderContext;
class WaylandConnection;
struct PointerEvent;
struct wl_output;
struct wl_surface;

class PanelManager {
public:
  PanelManager();
  ~PanelManager();

  PanelManager(const PanelManager&) = delete;
  PanelManager& operator=(const PanelManager&) = delete;

  static PanelManager& instance();

  void initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext);

  void registerPanel(const std::string& id, std::unique_ptr<PanelContent> content);

  void openPanel(const std::string& panelId, wl_output* output, std::int32_t scale, float anchorX);
  void closePanel();
  void togglePanel(const std::string& panelId, wl_output* output, std::int32_t scale, float anchorX);

  void onPointerEvent(const PointerEvent& event);

  [[nodiscard]] bool isOpen() const noexcept;
  [[nodiscard]] const std::string& activePanelId() const noexcept;

  void close();

private:
  static PanelManager* s_instance;

  void buildScene(std::uint32_t width, std::uint32_t height);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;

  std::unique_ptr<LayerSurface> m_surface;
  std::unique_ptr<Node> m_sceneRoot;
  AnimationManager m_animations;
  InputDispatcher m_inputDispatcher;

  std::unordered_map<std::string, std::unique_ptr<PanelContent>> m_panels;
  PanelContent* m_activePanel = nullptr;
  std::string m_activePanelId;

  wl_surface* m_wlSurface = nullptr;
  bool m_pointerInside = false;
  bool m_inTransition = false;
  bool m_justClosed = false;
};
