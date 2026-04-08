#pragma once

#include "render/animation/animation_manager.h"
#include "shell/widget/widget.h"
#include "wayland/wayland_connection.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

class Flex;

class WorkspacesWidget : public Widget {
public:
  enum class DisplayMode : std::uint8_t {
    None,
    Id,
    Name,
  };

  WorkspacesWidget(WaylandConnection& connection, wl_output* output, DisplayMode displayMode);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void rebuild(Renderer& renderer);
  [[nodiscard]] static std::optional<std::size_t> numericWorkspaceId(const Workspace& workspace);
  [[nodiscard]] std::string workspaceLabel(const Workspace& workspace, std::size_t displayIndex) const;

  WaylandConnection& m_connection;
  wl_output* m_output = nullptr;
  DisplayMode m_displayMode = DisplayMode::None;
  Flex* m_container = nullptr;
  std::vector<Workspace> m_cachedState;
};
