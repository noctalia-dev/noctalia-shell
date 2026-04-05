#pragma once

#include "shell/widget/widget.h"
#include "wayland/wayland_connection.h"

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

  WaylandConnection& m_connection;
  wl_output* m_output = nullptr;
  Box* m_container = nullptr;
  std::vector<Workspace> m_cachedState;
};
