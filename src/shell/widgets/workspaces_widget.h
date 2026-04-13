#pragma once

#include "render/animation/animation_manager.h"
#include "shell/widget/widget.h"
#include "ui/palette.h"
#include "wayland/wayland_connection.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

class Box;
class Flex;
class Label;

class WorkspacesWidget : public Widget {
public:
  enum class DisplayMode : std::uint8_t {
    None,
    Id,
    Name,
  };

  WorkspacesWidget(WaylandConnection& connection, wl_output* output, DisplayMode displayMode);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void rebuild(Renderer& renderer);
  [[nodiscard]] static std::optional<std::size_t> numericWorkspaceId(const Workspace& workspace);
  [[nodiscard]] std::string workspaceLabel(const Workspace& workspace, std::size_t displayIndex) const;

  struct Item {
    Box* indicator = nullptr;
    Label* text = nullptr; // may be null when no label
    bool active = false;
  };

  [[nodiscard]] static ColorRole workspaceFillRole(const Workspace& workspace);
  [[nodiscard]] static ColorRole workspaceTextRole(const Workspace& workspace);

  WaylandConnection& m_connection;
  wl_output* m_output = nullptr;
  DisplayMode m_displayMode = DisplayMode::None;
  Flex* m_container = nullptr;
  std::vector<Workspace> m_cachedState;
  std::vector<Item> m_items;
  bool m_rebuildPending = true;
};
