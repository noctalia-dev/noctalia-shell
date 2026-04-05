#pragma once

#include "render/animation/animation_manager.h"
#include "shell/widget/widget.h"
#include "wayland/wayland_connection.h"

#include <optional>
#include <string>
#include <vector>

class Box;

class WorkspacesWidget : public Widget {
public:
  WorkspacesWidget(WaylandConnection& connection, wl_output* output);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void rebuild(Renderer& renderer);
  void playSwitchAnimation(int direction);
  [[nodiscard]] static std::optional<int> activeCoordinateX(const std::vector<Workspace>& workspaces);

  WaylandConnection& m_connection;
  wl_output* m_output = nullptr;
  Box* m_container = nullptr;
  std::vector<Workspace> m_cachedState;
  AnimationManager::Id m_slideAnimId = 0;
  AnimationManager::Id m_fadeAnimId = 0;
};
