#pragma once

#include "shell/panel/panel.h"

#include <array>
#include <functional>

class Button;
class Flex;
class InputArea;
class Renderer;

class SessionPanel : public Panel {
public:
  enum class ActionId : std::size_t {
    Logout = 0,
    Reboot = 1,
    Shutdown = 2,
    Lock = 3,
    Count = 4,
  };

  struct Actions {
    std::function<void()> logout;
    std::function<void()> reboot;
    std::function<void()> shutdown;
    std::function<void()> lock;
  };

  explicit SessionPanel(Actions actions);

  void create() override;
  void layout(Renderer& renderer, float width, float height) override;
  void update(Renderer& renderer) override;
  void onOpen(std::string_view context) override;
  void onClose() override;

  [[nodiscard]] float preferredWidth() const override { return scaled(680.0f); }
  [[nodiscard]] float preferredHeight() const override { return scaled(136.0f); }
  [[nodiscard]] bool centeredHorizontally() const override { return true; }
  [[nodiscard]] bool centeredVertically() const override { return true; }
  [[nodiscard]] bool hasDecoration() const override { return true; }
  [[nodiscard]] LayerShellLayer layer() const override { return LayerShellLayer::Overlay; }
  [[nodiscard]] LayerShellKeyboard keyboardMode() const override { return LayerShellKeyboard::Exclusive; }
  [[nodiscard]] InputArea* initialFocusArea() const override;

private:
  void activateSelected();
  bool handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers);
  void updateSelectionVisuals();
  void activateMouse();
  [[nodiscard]] Button* createActionButton(ActionId id, float scale);

  Actions m_actions;
  Flex* m_rootLayout = nullptr;
  InputArea* m_focusArea = nullptr;
  std::array<ActionId, static_cast<std::size_t>(ActionId::Count)> m_actionOrder{};
  std::array<Button*, static_cast<std::size_t>(ActionId::Count)> m_actionButtons{};
  std::size_t m_selectedIndex = 0;
  bool m_mouseActive = false;
};
