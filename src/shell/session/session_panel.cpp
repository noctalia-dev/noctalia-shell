#include "shell/session/session_panel.h"

#include "compositors/compositor_detect.h"
#include "config/config_service.h"
#include "core/log.h"
#include "core/process.h"
#include "i18n/i18n.h"
#include "notification/notifications.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/lockscreen/lock_screen.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/glyph.h"
#include "ui/controls/grid_view.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/string_utils.h"

#include <algorithm>
#include <cstdlib>
#include <memory>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr Logger kLog("session");

  [[nodiscard]] const char* valueOrUnset(const char* value) {
    return value != nullptr && value[0] != '\0' ? value : "<unset>";
  }

  compositors::CompositorKind logActionContext(std::string_view action) {
    const compositors::CompositorKind compositor = compositors::detect();
    kLog.info("{} requested: compositor={} env_hint=\"{}\" xdg_session_id={} user={}", action,
              compositors::name(compositor), compositors::envHint(), valueOrUnset(std::getenv("XDG_SESSION_ID")),
              valueOrUnset(std::getenv("USER")));
    return compositor;
  }

  bool doLogout() {
    const compositors::CompositorKind compositor = logActionContext("logout");

    switch (compositor) {
    case compositors::CompositorKind::Hyprland:
      return process::launchFirstAvailable({{"hyprctl", "dispatch", "exit"}});
    case compositors::CompositorKind::Sway:
      return process::launchFirstAvailable({{"swaymsg", "exit"}, {"i3-msg", "exit"}});
    case compositors::CompositorKind::Niri:
      return process::launchFirstAvailable({{"niri", "msg", "action", "quit", "--skip-confirmation"}});
    case compositors::CompositorKind::Mango:
      return process::launchFirstAvailable({{"mmsg", "-q"}});
    case compositors::CompositorKind::Unknown:
      break;
    }

    if (process::launchFirstAvailable({{"systemctl", "--user", "stop", "graphical-session.target"}})) {
      return true;
    }
    if (const char* sessionId = std::getenv("XDG_SESSION_ID"); sessionId != nullptr && sessionId[0] != '\0') {
      if (process::launchFirstAvailable({{"loginctl", "terminate-session", sessionId}})) {
        return true;
      }
    }
    if (const char* user = std::getenv("USER"); user != nullptr && user[0] != '\0') {
      if (process::launchFirstAvailable({{"loginctl", "terminate-user", user}})) {
        return true;
      }
    }
    return false;
  }

  bool doReboot() {
    logActionContext("reboot");
    const bool launched = process::launchFirstAvailable({{"systemctl", "reboot"}, {"loginctl", "reboot"}});
    if (!launched) {
      kLog.warn("reboot: all reboot methods failed");
    }
    return launched;
  }

  bool doShutdown() {
    logActionContext("shutdown");
    const bool launched = process::launchFirstAvailable({{"systemctl", "poweroff"}, {"loginctl", "poweroff"}});
    if (!launched) {
      kLog.warn("shutdown: all shutdown methods failed");
    }
    return launched;
  }

  bool doLock() {
    logActionContext("lock");
    LockScreen* lockScreen = LockScreen::instance();
    if (lockScreen == nullptr) {
      kLog.warn("lock: lock screen service unavailable");
      return false;
    }
    if (!lockScreen->lock()) {
      kLog.warn("lock: lock screen request failed");
      return false;
    }
    kLog.info("lock: lock screen requested");
    return true;
  }

  void runPowerAction(std::function<bool()> hook, bool (*action)(), std::string_view actionName) {
    std::thread([hook = std::move(hook), action, actionName = std::string(actionName)]() mutable {
      if (hook && !hook()) {
        kLog.warn("{} cancelled because a configured hook failed", actionName);
        return;
      }
      if (!action()) {
        kLog.warn("{} failed after hooks completed", actionName);
      }
    }).detach();
  }

  void runShellCommand(std::function<bool()> hook, std::string command, std::string_view actionName) {
    std::thread([hook = std::move(hook), command = std::move(command), actionName = std::string(actionName)]() mutable {
      if (hook && !hook()) {
        kLog.warn("{} cancelled because a configured hook failed", actionName);
        return;
      }
      if (!process::runAsync(command)) {
        kLog.warn("{}: command failed", actionName);
      }
    }).detach();
  }

  [[nodiscard]] bool isKnownAction(std::string_view action) {
    return action == "lock" || action == "logout" || action == "reboot" || action == "shutdown" || action == "command";
  }

  [[nodiscard]] const char* labelKeyForAction(std::string_view action) {
    if (action == "lock") {
      return "session.actions.lock";
    }
    if (action == "logout") {
      return "session.actions.logout";
    }
    if (action == "reboot") {
      return "session.actions.reboot";
    }
    if (action == "shutdown") {
      return "session.actions.shutdown";
    }
    return "session.actions.custom";
  }

  [[nodiscard]] const char* defaultGlyphForAction(std::string_view action) {
    if (action == "lock") {
      return "lock";
    }
    if (action == "logout") {
      return "logout";
    }
    if (action == "reboot") {
      return "reboot";
    }
    if (action == "shutdown") {
      return "shutdown";
    }
    return "terminal";
  }

  [[nodiscard]] ButtonVariant variantFor(const SessionPanelActionConfig& cfg) {
    if (cfg.destructive) {
      return ButtonVariant::Destructive;
    }
    if (cfg.action == "shutdown" && !cfg.command.has_value()) {
      return ButtonVariant::Destructive;
    }
    return ButtonVariant::Default;
  }

} // namespace

std::vector<SessionPanelActionConfig> SessionPanel::effectiveActions() const {
  std::vector<SessionPanelActionConfig> src;
  if (m_config != nullptr) {
    src = m_config->config().shell.session.actions;
  }
  if (src.empty()) {
    src = defaultSessionPanelActions();
  }

  std::vector<SessionPanelActionConfig> out;
  out.reserve(src.size());
  for (const auto& row : src) {
    if (!row.enabled) {
      continue;
    }
    if (!isKnownAction(row.action)) {
      kLog.warn("session panel: skipping unknown action \"{}\"", row.action);
      continue;
    }
    if (row.action == "command" && (!row.command.has_value() || StringUtils::trim(*row.command).empty())) {
      kLog.warn("session panel: skipping \"command\" entry with no command");
      continue;
    }
    out.push_back(row);
  }
  return out;
}

std::function<bool()> SessionPanel::hookFor(const std::string& action) const {
  if (action == "logout") {
    return m_actionHooks.onLogout;
  }
  if (action == "reboot") {
    return m_actionHooks.onReboot;
  }
  if (action == "shutdown") {
    return m_actionHooks.onShutdown;
  }
  return {};
}

float SessionPanel::preferredWidth() const {
  const std::size_t n = visibleColumnCount();
  const float gap = Style::spaceSm;
  const float w = kButtonMinWidth * static_cast<float>(n) + gap * static_cast<float>(n > 1 ? n - 1 : 0) +
                  Style::panelPadding * 2.0f;
  return scaled(std::max(kPanelMinWidth, w));
}

float SessionPanel::preferredHeight() const {
  const std::size_t rows = visibleRowCount();
  const float gap = Style::spaceSm;
  const float h = kActionButtonMinHeight * static_cast<float>(rows) +
                  gap * static_cast<float>(rows > 1 ? rows - 1 : 0) + Style::panelPadding * 2.0f;
  return std::ceil(scaled(h));
}

std::size_t SessionPanel::entryCountForLayout() const {
  if (!m_visibleEntries.empty()) {
    return m_visibleEntries.size();
  }
  return effectiveActions().size();
}

std::size_t SessionPanel::visibleColumnCount() const {
  const std::size_t n = std::max<std::size_t>(1, entryCountForLayout());
  if (n <= kMaxColumns) {
    return n;
  }
  return std::min<std::size_t>(kMaxColumns, (n + 1) / 2);
}

std::size_t SessionPanel::visibleRowCount() const {
  const std::size_t n = std::max<std::size_t>(1, entryCountForLayout());
  const std::size_t columns = visibleColumnCount();
  return (n + columns - 1) / columns;
}

void SessionPanel::create() {
  const float scale = contentScale();
  m_visibleEntries = effectiveActions();
  const std::size_t columns = visibleColumnCount();

  auto rootLayout = std::make_unique<GridView>();
  rootLayout->setColumns(columns);
  rootLayout->setColumnGap(Style::spaceSm * scale);
  rootLayout->setRowGap(Style::spaceSm * scale);
  rootLayout->setStretchItems(true);
  rootLayout->setUniformCellSize(true);
  rootLayout->setMinCellWidth(kButtonMinWidth * scale);
  rootLayout->setMinCellHeight(kActionButtonMinHeight * scale);
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

  m_visibleButtons.clear();
  m_visibleButtons.reserve(m_visibleEntries.size());
  for (std::size_t i = 0; i < m_visibleEntries.size(); ++i) {
    if (Button* b = createActionButton(m_visibleEntries[i], i, scale); b != nullptr) {
      m_visibleButtons.push_back(b);
      rootLayout->addChild(std::unique_ptr<Button>(b));
    }
  }

  setRoot(std::move(rootLayout));

  if (m_animations != nullptr) {
    root()->setAnimationManager(m_animations);
  }

  updateSelectionVisuals();
}

Button* SessionPanel::createActionButton(const SessionPanelActionConfig& cfg, std::size_t index, float scale) {
  auto button = std::make_unique<Button>();
  button->setVariant(variantFor(cfg));
  button->setDirection(FlexDirection::Vertical);
  button->setAlign(FlexAlign::Center);
  button->setJustify(FlexJustify::Center);
  button->setGap(Style::spaceSm * scale);
  button->setContentAlign(ButtonContentAlign::Center);
  button->setFontSize((Style::fontSizeBody + 1.0f) * scale);
  button->setGlyphSize(28.0f * scale);
  button->setPadding(Style::spaceMd * scale, Style::spaceLg * scale);
  button->setRadius(Style::radiusLg * scale);
  button->setMinWidth(kButtonMinWidth * scale);
  button->setMinHeight(kActionButtonMinHeight * scale);
  button->setFlexGrow(1.0f);

  if (index < 9) {
    const float badgeSize = 22.0f * scale;
    auto badge = std::make_unique<Glyph>();
    badge->setGlyph("circle");
    badge->setGlyphSize(badgeSize);
    badge->setParticipatesInLayout(false);
    badge->setZIndex(2);
    badge->setOpacity(0.7f);
    button->addChild(std::move(badge));

    auto badgeLabel = std::make_unique<Label>();
    badgeLabel->setText(std::to_string(index + 1));
    badgeLabel->setFontSize((Style::fontSizeCaption - 1.0f) * scale);
    badgeLabel->setBold(true);
    badgeLabel->setParticipatesInLayout(false);
    badgeLabel->setZIndex(3);
    button->addChild(std::move(badgeLabel));
  }

  const std::string labelText =
      cfg.label.has_value() && !cfg.label->empty() ? *cfg.label : i18n::tr(labelKeyForAction(cfg.action));
  button->setText(labelText);
  button->setGlyph(cfg.glyph.has_value() && !cfg.glyph->empty() ? *cfg.glyph : defaultGlyphForAction(cfg.action));

  SessionPanelActionConfig cfgCopy = cfg;
  button->setOnClick([this, cfgCopy]() {
    PanelManager::instance().close();
    invokeEntry(cfgCopy);
  });
  button->setOnMotion([this]() { activateMouse(); });
  button->setHoverSuppressed(!m_mouseActive);

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
  for (Button* button : m_visibleButtons) {
    if (button != nullptr) {
      button->setHoverSuppressed(false);
    }
  }
  PanelManager::instance().refresh();
}

void SessionPanel::activateSelected() {
  if (!m_selectedIndex.has_value() || m_visibleButtons.empty()) {
    return;
  }
  const std::size_t i = *m_selectedIndex;
  if (i >= m_visibleButtons.size() || i >= m_visibleEntries.size()) {
    return;
  }
  Button* button = m_visibleButtons[i];
  if (button != nullptr && button->enabled()) {
    PanelManager::instance().close();
    invokeEntry(m_visibleEntries[i]);
  }
}

void SessionPanel::invokeEntry(const SessionPanelActionConfig& cfg) {
  if (cfg.command.has_value()) {
    const std::string cmd = StringUtils::trim(*cfg.command);
    if (!cmd.empty()) {
      std::function<bool()> hook;
      if (cfg.action == "logout" || cfg.action == "reboot" || cfg.action == "shutdown") {
        hook = hookFor(cfg.action);
      }
      runShellCommand(std::move(hook), cmd, cfg.action);
      return;
    }
  }

  if (cfg.action == "command") {
    kLog.warn("session panel: custom action missing command");
    return;
  }

  if (cfg.action == "logout") {
    runPowerAction(m_actionHooks.onLogout, doLogout, "logout");
    return;
  }
  if (cfg.action == "reboot") {
    runPowerAction(m_actionHooks.onReboot, doReboot, "reboot");
    return;
  }
  if (cfg.action == "shutdown") {
    runPowerAction(m_actionHooks.onShutdown, doShutdown, "shutdown");
    return;
  }
  if (cfg.action == "lock") {
    if (!doLock()) {
      notify::error("Noctalia", i18n::tr("session.errors.lock-title"), i18n::tr("session.errors.lock-body"));
    }
    return;
  }
}

bool SessionPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers) {
  if (m_visibleButtons.empty()) {
    return false;
  }
  const std::size_t lastIndex = m_visibleButtons.size() - 1;

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

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Up, sym, modifiers)) {
    const std::size_t columns = visibleColumnCount();
    if (!m_selectedIndex.has_value()) {
      m_selectedIndex = lastIndex;
    } else if (*m_selectedIndex >= columns) {
      *m_selectedIndex -= columns;
    }
    updateSelectionVisuals();
    if (root() != nullptr) {
      root()->markPaintDirty();
    }
    PanelManager::instance().refresh();
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Down, sym, modifiers)) {
    const std::size_t columns = visibleColumnCount();
    if (!m_selectedIndex.has_value()) {
      m_selectedIndex = 0;
    } else if (*m_selectedIndex + columns <= lastIndex) {
      *m_selectedIndex += columns;
    }
    updateSelectionVisuals();
    if (root() != nullptr) {
      root()->markPaintDirty();
    }
    PanelManager::instance().refresh();
    return true;
  }

  if (sym >= XKB_KEY_1 && sym <= XKB_KEY_9) {
    const std::size_t index = sym - XKB_KEY_1;
    if (index < m_visibleButtons.size()) {
      m_selectedIndex = index;
      updateSelectionVisuals();
      activateSelected();
      return true;
    }
  }

  if (sym >= XKB_KEY_KP_1 && sym <= XKB_KEY_KP_9) {
    const std::size_t index = sym - XKB_KEY_KP_1;
    if (index < m_visibleButtons.size()) {
      m_selectedIndex = index;
      updateSelectionVisuals();
      activateSelected();
      return true;
    }
  }

  if ((m_config != nullptr && m_config->matchesKeybind(KeybindAction::Validate, sym, modifiers)) ||
      sym == XKB_KEY_space) {
    activateSelected();
    return true;
  }

  return false;
}

void SessionPanel::updateSelectionVisuals() {
  for (std::size_t i = 0; i < m_visibleButtons.size(); ++i) {
    Button* button = m_visibleButtons[i];
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

  doUpdate(renderer);

  const float scale = contentScale();
  for (Button* button : m_visibleButtons) {
    if (button != nullptr) {
      button->updateInputArea();

      for (auto& child : button->children()) {
        if (child->participatesInLayout()) {
          continue;
        }

        if (child->zIndex() == 2) {
          if (auto* glyph = dynamic_cast<Glyph*>(child.get())) {
            glyph->measure(renderer);
          }
          const float margin = Style::spaceMd * scale;
          child->setPosition(button->width() - child->width() - margin, margin);
        } else if (child->zIndex() == 3) {
          if (auto* label = dynamic_cast<Label*>(child.get())) {
            label->measure(renderer);
            const float margin = Style::spaceMd * scale;
            const float badgeSize = 22.0f * scale;
            const float centerX = button->width() - margin - badgeSize * 0.5f;
            const float centerY = margin + badgeSize * 0.5f;
            label->setPosition(centerX - label->width() * 0.5f, centerY - label->height() * 0.5f + 0.5f * scale);
          }
        }
      }
    }
  }
}

void SessionPanel::doUpdate(Renderer& /*renderer*/) {
  for (Button* button : m_visibleButtons) {
    if (button == nullptr || button->label() == nullptr) {
      continue;
    }

    const Color activeColor = button->label()->color();

    for (auto& child : button->children()) {
      if (child->participatesInLayout()) {
        continue;
      }

      if (child->zIndex() == 2) {
        if (auto* glyph = dynamic_cast<Glyph*>(child.get())) {
          glyph->setColor(activeColor);
        }
      } else if (child->zIndex() == 3) {
        if (auto* label = dynamic_cast<Label*>(child.get())) {
          label->setColor(activeColor);
        }
      }
    }
  }
}

void SessionPanel::onClose() {
  m_rootLayout = nullptr;
  m_focusArea = nullptr;
  m_visibleEntries.clear();
  m_visibleButtons.clear();
  clearReleasedRoot();
}
