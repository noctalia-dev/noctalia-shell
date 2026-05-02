#include "shell/polkit/polkit_panel.h"

#include "config/config_service.h"
#include "config/config_types.h"
#include "dbus/polkit/polkit_agent.h"
#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_seat.h"

#include <cctype>
#include <memory>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  std::string wrapLongRuns(std::string text, std::size_t maxRun = 48) {
    std::string out;
    out.reserve(text.size() + text.size() / maxRun);
    std::size_t run = 0;
    for (char ch : text) {
      const bool breakable = std::isspace(static_cast<unsigned char>(ch)) != 0 || ch == '/' || ch == ':' || ch == '-';
      out.push_back(ch);
      if (breakable) {
        run = 0;
        continue;
      }
      ++run;
      if (run >= maxRun) {
        out.push_back('\n');
        run = 0;
      }
    }
    return out;
  }

} // namespace

PolkitPanel::PolkitPanel(ConfigService* config, std::function<PolkitAgent*()> agentProvider)
    : m_config(config), m_agentProvider(std::move(agentProvider)) {}

void PolkitPanel::create() {
  const float scale = contentScale();
  auto root = std::make_unique<Flex>();
  root->setDirection(FlexDirection::Vertical);
  root->setAlign(FlexAlign::Stretch);
  root->setJustify(FlexJustify::SpaceBetween);
  root->setPadding(Style::spaceLg * scale);
  m_rootLayout = root.get();

  auto focusArea = std::make_unique<InputArea>();
  focusArea->setFocusable(true);
  focusArea->setVisible(false);
  m_focusArea = static_cast<InputArea*>(root->addChild(std::move(focusArea)));

  auto topContent = std::make_unique<Flex>();
  topContent->setDirection(FlexDirection::Vertical);
  topContent->setAlign(FlexAlign::Stretch);
  topContent->setGap(Style::spaceSm * scale);

  auto title = std::make_unique<Label>();
  title->setText(i18n::tr("auth.polkit.title"));
  title->setBold(true);
  title->setFontSize(Style::fontSizeTitle * scale);
  title->setColor(colorSpecFromRole(ColorRole::Primary));
  m_titleLabel = title.get();
  topContent->addChild(std::move(title));

  auto message = std::make_unique<Label>();
  message->setFontSize(Style::fontSizeBody * scale);
  message->setColor(colorSpecFromRole(ColorRole::OnSurface));
  message->setMaxLines(6);
  m_messageLabel = message.get();
  topContent->addChild(std::move(message));
  root->addChild(std::move(topContent));

  auto bottomContent = std::make_unique<Flex>();
  bottomContent->setDirection(FlexDirection::Vertical);
  bottomContent->setAlign(FlexAlign::Stretch);
  bottomContent->setGap(Style::spaceSm * scale);

  auto prompt = std::make_unique<Label>();
  prompt->setFontSize(Style::fontSizeBody * scale);
  prompt->setColor(colorSpecFromRole(ColorRole::OnSurface));
  prompt->setMaxLines(3);
  m_promptLabel = prompt.get();
  bottomContent->addChild(std::move(prompt));

  auto input = std::make_unique<Input>();
  input->setPlaceholder(i18n::tr("auth.polkit.password-placeholder"));
  input->setPasswordMode(true);
  input->setOnSubmit([this](const std::string&) { submit(); });
  input->setOnKeyEvent(
      [this](std::uint32_t sym, std::uint32_t modifiers) { return handleInputKeyEvent(sym, modifiers); });
  m_input = input.get();
  bottomContent->addChild(std::move(input));

  auto supplementary = std::make_unique<Label>();
  supplementary->setFontSize(Style::fontSizeCaption * scale);
  supplementary->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  supplementary->setMaxLines(4);
  m_supplementaryLabel = supplementary.get();
  bottomContent->addChild(std::move(supplementary));

  auto actions = std::make_unique<Flex>();
  actions->setDirection(FlexDirection::Horizontal);
  actions->setAlign(FlexAlign::Center);
  actions->setJustify(FlexJustify::End);
  actions->setGap(Style::spaceSm * scale);

  auto cancel = std::make_unique<Button>();
  cancel->setText(i18n::tr("common.actions.cancel"));
  cancel->setVariant(ButtonVariant::Outline);
  cancel->setOnClick([]() { PanelManager::instance().close(); });
  m_cancelButton = cancel.get();
  actions->addChild(std::move(cancel));

  auto submitButton = std::make_unique<Button>();
  submitButton->setText(i18n::tr("auth.polkit.authenticate"));
  submitButton->setVariant(ButtonVariant::Accent);
  submitButton->setOnClick([this]() { submit(); });
  m_submitButton = submitButton.get();
  actions->addChild(std::move(submitButton));

  bottomContent->addChild(std::move(actions));
  root->addChild(std::move(bottomContent));
  setRoot(std::move(root));
}

void PolkitPanel::onOpen(std::string_view /*context*/) {
  if (m_input != nullptr) {
    m_input->setValue("");
  }
}

void PolkitPanel::onClose() {
  if (PolkitAgent* agent = m_agentProvider != nullptr ? m_agentProvider() : nullptr; agent != nullptr) {
    if (agent->hasPendingRequest()) {
      agent->cancelRequest();
    }
  }
  clearReleasedRoot();
}

InputArea* PolkitPanel::initialFocusArea() const { return m_input != nullptr ? m_input->inputArea() : m_focusArea; }

void PolkitPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr) {
    return;
  }
  m_rootLayout->setSize(width, height);
  const float contentWidth = std::max(0.0f, width - (Style::spaceLg * contentScale() * 2.0f));
  if (m_messageLabel != nullptr) {
    m_messageLabel->setMaxWidth(contentWidth);
  }
  if (m_promptLabel != nullptr) {
    m_promptLabel->setMaxWidth(contentWidth);
  }
  if (m_supplementaryLabel != nullptr) {
    m_supplementaryLabel->setMaxWidth(contentWidth);
  }
  m_rootLayout->layout(renderer);
}

void PolkitPanel::doUpdate(Renderer& /*renderer*/) {
  PolkitAgent* agent = m_agentProvider != nullptr ? m_agentProvider() : nullptr;
  if (agent == nullptr || m_messageLabel == nullptr || m_promptLabel == nullptr || m_supplementaryLabel == nullptr ||
      m_submitButton == nullptr || m_input == nullptr) {
    return;
  }
  const PolkitRequest request = agent->pendingRequest();
  const std::string supplementaryRaw = agent->supplementaryMessage();
  const bool supplementaryError = agent->supplementaryIsError();
  const bool isInvalidPassword = supplementaryError && supplementaryRaw == i18n::tr("auth.polkit.invalid-password");
  std::string promptText = wrapLongRuns(agent->inputPrompt());
  std::string supplementaryText = wrapLongRuns(supplementaryRaw);
  if (!supplementaryText.empty() &&
      (supplementaryError || supplementaryText == i18n::tr("auth.polkit.authenticating"))) {
    promptText = supplementaryText;
    supplementaryText.clear();
  }
  m_messageLabel->setText(wrapLongRuns(request.message.empty() ? request.actionId : request.message));
  m_promptLabel->setText(promptText);
  m_promptLabel->setColor(isInvalidPassword ? colorSpecFromRole(ColorRole::Error)
                                            : colorSpecFromRole(ColorRole::OnSurface));
  m_promptLabel->setVisible(!promptText.empty());
  m_supplementaryLabel->setText(supplementaryText);
  m_supplementaryLabel->setVisible(!supplementaryText.empty());
  m_supplementaryLabel->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_submitButton->setEnabled(agent->isResponseRequired());
}

void PolkitPanel::submit() {
  PolkitAgent* agent = m_agentProvider != nullptr ? m_agentProvider() : nullptr;
  if (agent == nullptr || m_input == nullptr) {
    return;
  }
  agent->submitResponse(m_input->value());
  m_input->setValue("");
}

bool PolkitPanel::handleInputKeyEvent(std::uint32_t sym, std::uint32_t modifiers) {
  if (m_config == nullptr) {
    return false;
  }
  if (m_config->matchesKeybind(KeybindAction::Validate, sym, modifiers)) {
    submit();
    return true;
  }
  if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter) {
    return true;
  }
  const bool shift = (modifiers & KeyMod::Shift) != 0;
  if (m_config->matchesKeybind(KeybindAction::Left, sym, modifiers)) {
    if (m_input != nullptr) {
      m_input->moveCaretLeft(shift);
    }
    return true;
  }
  if (m_config->matchesKeybind(KeybindAction::Right, sym, modifiers)) {
    if (m_input != nullptr) {
      m_input->moveCaretRight(shift);
    }
    return true;
  }
  return false;
}
