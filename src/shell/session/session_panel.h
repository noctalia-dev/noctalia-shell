#pragma once

#include "shell/panel/panel.h"

#include <array>
#include <functional>
#include <optional>

class Button;
class Flex;
class InputArea;
class Renderer;
class ConfigService;

struct SessionActionHooks {
  std::function<void()> onLogout;
  std::function<void()> onReboot;
  std::function<void()> onShutdown;
};

class SessionPanel : public Panel {
public:
  enum class ActionId : std::size_t {
    Logout = 0,
    Reboot = 1,
    Shutdown = 2,
    Lock = 3,
    Count = 4,
  };

  explicit SessionPanel(ConfigService* config, SessionActionHooks actionHooks = {})
      : m_config(config), m_actionHooks(std::move(actionHooks)) {}

  void create() override;
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
  void doLayout(Renderer& renderer, float width, float height) override;
  void doUpdate(Renderer& renderer) override;
  void activateSelected();
  bool handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers);
  void updateSelectionVisuals();
  void activateMouse();
  void invokeAction(ActionId id);
  [[nodiscard]] Button* createActionButton(ActionId id, float scale);

  Flex* m_rootLayout = nullptr;
  InputArea* m_focusArea = nullptr;
  std::array<ActionId, static_cast<std::size_t>(ActionId::Count)> m_actionOrder{};
  std::array<Button*, static_cast<std::size_t>(ActionId::Count)> m_actionButtons{};
  std::optional<std::size_t> m_selectedIndex;
  bool m_mouseActive = false;
  ConfigService* m_config = nullptr;
  SessionActionHooks m_actionHooks;
};
