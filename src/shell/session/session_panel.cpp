#include "shell/session/session_panel.h"

#include "core/log.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>
#include <utility>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {
constexpr Logger kLog("session");
} // namespace

namespace {

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

} // namespace

SessionPanel::SessionPanel(Actions actions) : m_actions(std::move(actions)) {}

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
    kLog.debug("button onClick: id={}", static_cast<std::size_t>(id));
    PanelManager::instance().close();
    switch (id) {
    case ActionId::Logout:
      if (m_actions.logout) {
        m_actions.logout();
      }
      break;
    case ActionId::Reboot:
      if (m_actions.reboot) {
        m_actions.reboot();
      }
      break;
    case ActionId::Shutdown:
      if (m_actions.shutdown) {
        m_actions.shutdown();
      }
      break;
    case ActionId::Lock:
      kLog.debug("button onClick: triggering lock");
      if (m_actions.lock) {
        m_actions.lock();
      }
      break;
    case ActionId::Count:
      break;
    }
  });

  auto* raw = button.get();
  m_actionButtons[static_cast<std::size_t>(id)] = raw;
  return button.release();
}

InputArea* SessionPanel::initialFocusArea() const { return m_focusArea; }

void SessionPanel::onOpen(std::string_view /*context*/) {
  kLog.debug("onOpen: resetting selectedIndex to 0");
  m_selectedIndex = 0;
  updateSelectionVisuals();
}

void SessionPanel::activateSelected() {
  if (m_selectedIndex >= static_cast<std::size_t>(ActionId::Count)) {
    return;
  }

  const ActionId selectedAction = m_actionOrder[m_selectedIndex];
  kLog.debug("activateSelected: index={} action={}", m_selectedIndex, static_cast<std::size_t>(selectedAction));
  if (Button* button = m_actionButtons[static_cast<std::size_t>(selectedAction)]; button != nullptr && button->enabled()) {
    PanelManager::instance().close();
    switch (selectedAction) {
    case ActionId::Logout:
      if (m_actions.logout) {
        m_actions.logout();
      }
      break;
    case ActionId::Reboot:
      if (m_actions.reboot) {
        m_actions.reboot();
      }
      break;
    case ActionId::Shutdown:
      if (m_actions.shutdown) {
        m_actions.shutdown();
      }
      break;
    case ActionId::Lock:
      kLog.debug("activateSelected: triggering lock");
      if (m_actions.lock) {
        m_actions.lock();
      }
      break;
    case ActionId::Count:
      break;
    }
  }
}

bool SessionPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t /*modifiers*/) {
  if (sym == XKB_KEY_Left) {
    if (m_selectedIndex > 0) {
      --m_selectedIndex;
      updateSelectionVisuals();
      if (root() != nullptr) {
        root()->markDirty();
      }
      PanelManager::instance().refresh();
    }
    return true;
  }

  if (sym == XKB_KEY_Right) {
    const std::size_t lastIndex = static_cast<std::size_t>(ActionId::Count) - 1;
    if (m_selectedIndex < lastIndex) {
      ++m_selectedIndex;
      updateSelectionVisuals();
      if (root() != nullptr) {
        root()->markDirty();
      }
      PanelManager::instance().refresh();
    }
    return true;
  }

  if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter || sym == XKB_KEY_space) {
    kLog.debug("handleKeyEvent: Enter/Space pressed, calling activateSelected");
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
    button->setSelected(i == m_selectedIndex);
  }
}

void SessionPanel::layout(Renderer& renderer, float width, float height) {
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

void SessionPanel::update(Renderer& /*renderer*/) {}

void SessionPanel::onClose() {
  m_rootLayout = nullptr;
  m_focusArea = nullptr;
  m_actionOrder.fill(ActionId::Logout);
  m_actionButtons.fill(nullptr);
}
