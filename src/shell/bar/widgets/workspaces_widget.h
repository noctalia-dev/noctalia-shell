#pragma once

#include "render/animation/animation_manager.h"
#include "shell/bar/widget.h"
#include "ui/palette.h"
#include "wayland/wayland_connection.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

class Box;
class InputArea;
class Label;

class WorkspacesWidget : public Widget {
public:
  enum class DisplayMode : std::uint8_t {
    None,
    Id,
    Name,
  };

  WorkspacesWidget(WaylandConnection& connection, wl_output* output, DisplayMode displayMode, ColorSpec focusedColor,
                   ColorSpec occupiedColor, ColorSpec emptyColor);
  ~WorkspacesWidget() override;

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void rebuild(Renderer& renderer);
  void computeTargets();
  void retarget(Renderer& renderer);
  void startAnimation();
  void cancelAnimation();
  void applyItemLayout(std::size_t i);
  [[nodiscard]] std::optional<std::size_t> activeWorkspaceIndex() const;
  void activateAdjacentWorkspace(int direction);

  [[nodiscard]] static std::optional<std::size_t> numericWorkspaceId(const Workspace& workspace);
  [[nodiscard]] std::string workspaceLabel(const Workspace& workspace, std::size_t displayIndex) const;

  struct Item {
    InputArea* area = nullptr;
    Box* indicator = nullptr;
    Label* text = nullptr;
    std::string label;
    bool showLabel = false;
    bool active = false;
    float inactiveWidth = 0.0f;
    float activeWidth = 0.0f;
    float fromX = 0.0f;
    float fromWidth = 0.0f;
    float targetX = 0.0f;
    float targetWidth = 0.0f;
    float currentX = 0.0f;
    float currentWidth = 0.0f;
    float textInkCenterX = 0.0f;
  };

  [[nodiscard]] ColorRole workspaceFillRole(const Workspace& workspace) const;
  [[nodiscard]] ColorRole workspaceTextRole(const Workspace& workspace) const;
  [[nodiscard]] float workspaceFillAlpha(const Workspace& workspace) const;
  [[nodiscard]] static ColorRole onRoleForFill(ColorRole fill);
  [[nodiscard]] ColorRole emptyWorkspaceTextRole() const;

  WaylandConnection& m_connection;
  wl_output* m_output = nullptr;
  DisplayMode m_displayMode = DisplayMode::None;
  Node* m_container = nullptr;
  std::vector<Workspace> m_cachedState;
  std::vector<Item> m_items;
  bool m_rebuildPending = true;

  float m_gap = 0.0f;
  float m_indicatorHeight = 0.0f;
  bool m_isVertical = false;

  AnimationManager::Id m_animId = 0;
  ColorSpec m_focusedColor = colorSpecFromRole(ColorRole::Primary);
  ColorSpec m_occupiedColor = colorSpecFromRole(ColorRole::Secondary);
  ColorSpec m_emptyColor = colorSpecFromRole(ColorRole::Secondary);
};
