#pragma once

#include "render/animation/AnimationManager.h"
#include "render/scene/InputDispatcher.h"
#include "render/scene/Node.h"
#include "shell/PanelContent.h"
#include "wayland/LayerSurface.h"

#include <functional>
#include <memory>
#include <string>
#include <unordered_map>

class ConfigService;
class WaylandConnection;
struct PointerEvent;
struct wl_output;
struct wl_surface;

class PanelManager {
public:
  using CloseCallback = std::function<void()>;

  PanelManager();

  void initialize(WaylandConnection& wayland, ConfigService* config);
  void setCloseCallback(CloseCallback callback);

  void registerPanel(const std::string& id, std::unique_ptr<PanelContent> content);

  void openPanel(const std::string& panelId, wl_output* output, std::int32_t scale, float anchorX);
  void closePanel();
  void togglePanel(const std::string& panelId, wl_output* output, std::int32_t scale, float anchorX);

  void onPointerEvent(const PointerEvent& event);

  [[nodiscard]] bool isOpen() const noexcept;
  [[nodiscard]] const std::string& activePanelId() const noexcept;

  void close();

private:
  void buildScene(std::uint32_t width, std::uint32_t height);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;

  std::unique_ptr<LayerSurface> m_surface;
  std::unique_ptr<Node> m_sceneRoot;
  AnimationManager m_animations;
  InputDispatcher m_inputDispatcher;

  std::unordered_map<std::string, std::unique_ptr<PanelContent>> m_panels;
  PanelContent* m_activePanel = nullptr;
  std::string m_activePanelId;

  CloseCallback m_closeCallback;
  wl_surface* m_wlSurface = nullptr;
  bool m_pointerInside = false;
  bool m_inTransition = false;
  bool m_justClosed = false;
};
