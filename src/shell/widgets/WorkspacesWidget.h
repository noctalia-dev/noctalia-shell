#pragma once

#include "shell/Widget.h"
#include "wayland/WaylandConnection.h"

#include <string>
#include <vector>

class Box;

class WorkspacesWidget : public Widget {
public:
  WorkspacesWidget(WaylandConnection& connection, wl_output* output);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

  void onPointerEnter(float localX, float localY) override;
  void onPointerLeave() override;
  void onPointerMotion(float localX, float localY) override;
  bool onPointerButton(std::uint32_t button, bool pressed) override;
  std::uint32_t cursorShape() const override;

private:
  void rebuild(Renderer& renderer);
  int pillIndexAt(float localX, float localY) const;

  WaylandConnection& m_connection;
  wl_output* m_output = nullptr;
  Box* m_container = nullptr;
  std::vector<Workspace> m_cachedState;
  std::vector<std::string> m_workspaceIds;
  int m_hoveredPill = -1;
};
