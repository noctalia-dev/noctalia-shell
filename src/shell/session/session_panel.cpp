#include "shell/session/session_panel.h"

#include "config/config_service.h"
#include "core/log.h"
#include "core/process.h"
#include "notification/notifications.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/lockscreen/lock_screen.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cstdlib>
#include <memory>
#include <utility>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr Logger kLog("session");

  struct ActionSpec {
    SessionPanel::ActionId id;
    const char* label;
    const char* glyph;
    ButtonVariant variant;
  };

  constexpr std::array<ActionSpec, 4> kActionSpecs{{
      {SessionPanel::ActionId::Lock, "Lock", "lock", ButtonVariant::Outline},
      {SessionPanel::ActionId::Logout, "Log Out", "logout", ButtonVariant::Outline},
      {SessionPanel::ActionId::Reboot, "Reboot", "reboot", ButtonVariant::Outline},
      {SessionPanel::ActionId::Shutdown, "Shut Down", "shutdown", ButtonVariant::Destructive},
  }};

  bool doLogout() {
    if (process::runAsync({"systemctl", "--user", "stop", "graphical-session.target"})) {
      return true;
    }
    if (const char* sessionId = std::getenv("XDG_SESSION_ID"); sessionId != nullptr && sessionId[0] != '\0') {
      return process::runAsync({"loginctl", "terminate-session", sessionId});
    }
    if (const char* user = std::getenv("USER"); user != nullptr && user[0] != '\0') {
      return process::runAsync({"loginctl", "terminate-user", user});
    }
    return false;
  }

  bool doReboot() { return process::launchFirstAvailable({{"systemctl", "reboot"}, {"loginctl", "reboot"}}); }

  bool doShutdown() { return process::launchFirstAvailable({{"systemctl", "poweroff"}, {"loginctl", "poweroff"}}); }

} // namespace

void SessionPanel::create() {
  const float scale = contentScale();

  auto rootLayout = std::make_unique<Flex>();
  rootLayout->setDirection(FlexDirection::Horizontal);
  rootLayout->setAlign(FlexAlign::Stretch);
  rootLayout->setGap(Style::spaceSm * scale);
  rootLayout->setJustify(FlexJustify::Start);
  m_rootLayout = rootLayout.get();

  auto focusArea = std::make_unique<InputArea>();
  focusArea->setFocusable(true);
  focusArea->setVisible(false);
  focusArea->setOnKeyDown([this](const InputArea::KeyData& key) {
    if (key.pressed) {
      handleKeyEvent(key.sym, key.modifiers);
    }
  });
  m_focusArea = static_cast<InputArea*>(rootLayout->addChild(std::move(focusArea)));

  for (const auto& spec : kActionSpecs) {
    const std::size_t visualIndex = rootLayout->children().size() - (m_focusArea != nullptr ? 1U : 0U);
    if (auto* button = createActionButton(spec.id, scale); button != nullptr) {
      m_actionOrder[visualIndex] = spec.id;
      rootLayout->addChild(std::unique_ptr<Button>(button));
    }
  }
  setRoot(std::move(rootLayout));

  if (m_animations != nullptr) {
    root()->setAnimationManager(m_animations);
  }

  updateSelectionVisuals();
}

Button* SessionPanel::createActionButton(ActionId id, float scale) {
  const auto* spec = std::find_if(kActionSpecs.begin(), kActionSpecs.end(),
                                  [id](const ActionSpec& candidate) { return candidate.id == id; });
  if (spec == kActionSpecs.end()) {
    return nullptr;
  }

  auto button = std::make_unique<Button>();
  button->setText(spec->label);
  button->setGlyph(spec->glyph);
  button->setVariant(spec->variant);
  button->setDirection(FlexDirection::Vertical);
  button->setAlign(FlexAlign::Center);
  button->setJustify(FlexJustify::Center);
  button->setGap(Style::spaceSm * scale);
  button->setContentAlign(ButtonContentAlign::Center);
  button->setFontSize((Style::fontSizeBody + 1.0f) * scale);
  button->setGlyphSize(28.0f * scale);
  button->setPadding(Style::spaceMd * scale, Style::spaceLg * scale);
  button->setRadius(Style::radiusLg * scale);
  button->setMinWidth(152.0f * scale);
  button->setMinHeight(112.0f * scale);
  button->setFlexGrow(1.0f);

  button->setOnClick([this, id]() {
    PanelManager::instance().close();
    invokeAction(id);
  });
  button->setOnMotion([this]() { activateMouse(); });
  button->setHoverSuppressed(!m_mouseActive);

  auto* raw = button.get();
  m_actionButtons[static_cast<std::size_t>(id)] = raw;
  return button.release();
}

InputArea* SessionPanel::initialFocusArea() const { return m_focusArea; }

void SessionPanel::onOpen(std::string_view /*context*/) {
  m_selectedIndex.reset();
  m_mouseActive = false;
  updateSelectionVisuals();
}

void SessionPanel::activateMouse() {
  if (m_mouseActive) {
    return;
  }
  m_mouseActive = true;
  for (Button* button : m_actionButtons) {
    if (button != nullptr) {
      button->setHoverSuppressed(false);
    }
  }
  PanelManager::instance().refresh();
}

void SessionPanel::activateSelected() {
  if (!m_selectedIndex.has_value() || *m_selectedIndex >= static_cast<std::size_t>(ActionId::Count)) {
    return;
  }

  const ActionId selectedAction = m_actionOrder[*m_selectedIndex];
  if (Button* button = m_actionButtons[static_cast<std::size_t>(selectedAction)];
      button != nullptr && button->enabled()) {
    PanelManager::instance().close();
    invokeAction(selectedAction);
  }
}

void SessionPanel::invokeAction(ActionId id) {
  switch (id) {
  case ActionId::Logout:
    if (m_actionHooks.onLogout) {
      m_actionHooks.onLogout();
    }
    if (!doLogout()) {
      notify::error("Noctalia", "Logout unavailable", "Could not determine how to terminate this session.");
    }
    break;
  case ActionId::Reboot:
    if (m_actionHooks.onReboot) {
      m_actionHooks.onReboot();
    }
    if (!doReboot()) {
      notify::error("Noctalia", "Reboot failed", "Could not launch systemctl reboot.");
    }
    break;
  case ActionId::Shutdown:
    if (m_actionHooks.onShutdown) {
      m_actionHooks.onShutdown();
    }
    if (!doShutdown()) {
      notify::error("Noctalia", "Shutdown failed", "Could not launch a shutdown command.");
    }
    break;
  case ActionId::Lock:
    if (auto* ls = LockScreen::instance(); ls == nullptr || !ls->lock()) {
      notify::error("Noctalia", "Lock unavailable", "The session lock protocol is not available.");
    }
    break;
  case ActionId::Count:
    break;
  }
}

bool SessionPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers) {
  const std::size_t lastIndex = static_cast<std::size_t>(ActionId::Count) - 1;

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Left, sym, modifiers)) {
    if (!m_selectedIndex.has_value()) {
      m_selectedIndex = lastIndex;
      updateSelectionVisuals();
      if (root() != nullptr) {
        root()->markPaintDirty();
      }
      PanelManager::instance().refresh();
    } else if (*m_selectedIndex > 0) {
      --(*m_selectedIndex);
      updateSelectionVisuals();
      if (root() != nullptr) {
        root()->markPaintDirty();
      }
      PanelManager::instance().refresh();
    }
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Right, sym, modifiers)) {
    if (!m_selectedIndex.has_value()) {
      m_selectedIndex = 0;
      updateSelectionVisuals();
      if (root() != nullptr) {
        root()->markPaintDirty();
      }
      PanelManager::instance().refresh();
    } else if (*m_selectedIndex < lastIndex) {
      ++(*m_selectedIndex);
      updateSelectionVisuals();
      if (root() != nullptr) {
        root()->markPaintDirty();
      }
      PanelManager::instance().refresh();
    }
    return true;
  }

  if ((m_config != nullptr && m_config->matchesKeybind(KeybindAction::Validate, sym, modifiers)) ||
      sym == XKB_KEY_space) {
    activateSelected();
    return true;
  }

  return false;
}

void SessionPanel::updateSelectionVisuals() {
  for (std::size_t i = 0; i < m_actionOrder.size(); ++i) {
    const ActionId actionId = m_actionOrder[i];
    Button* button = m_actionButtons[static_cast<std::size_t>(actionId)];
    if (button == nullptr) {
      continue;
    }
    button->setSelected(m_selectedIndex.has_value() && i == *m_selectedIndex);
  }
}

void SessionPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr) {
    return;
  }

  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);

  for (Button* button : m_actionButtons) {
    if (button != nullptr) {
      button->updateInputArea();
    }
  }
}

void SessionPanel::doUpdate(Renderer& /*renderer*/) {}

void SessionPanel::onClose() {
  m_rootLayout = nullptr;
  m_focusArea = nullptr;
  m_actionOrder.fill(ActionId::Logout);
  m_actionButtons.fill(nullptr);
  clearReleasedRoot();
}
