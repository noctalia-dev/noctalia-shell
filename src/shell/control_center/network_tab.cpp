#include "shell/control_center/network_tab.h"

#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/separator.h"
#include "ui/controls/spinner.h"
#include "ui/controls/toggle.h"
#include "ui/palette.h"

#include <algorithm>
#include <memory>
#include <string>
#include <utility>

using namespace control_center;

namespace {

  constexpr float kRowMinHeight = Style::controlHeightLg;

  std::string currentTitle(const NetworkState& s) {
    if (s.kind == NetworkConnectivity::Wireless && s.connected && !s.ssid.empty()) {
      return s.ssid;
    }
    if (s.kind == NetworkConnectivity::Wired && s.connected) {
      return s.interfaceName.empty() ? i18n::tr("control-center.network.wired-connection") : s.interfaceName;
    }
    return i18n::tr("control-center.network.not-connected");
  }

  std::string currentDetail(const NetworkState& s) {
    if (!s.connected) {
      return s.wirelessEnabled ? i18n::tr("control-center.network.wifi-on")
                               : i18n::tr("control-center.network.wifi-off");
    }
    std::string out;
    if (!s.ipv4.empty()) {
      out = s.ipv4;
    }
    if (s.kind == NetworkConnectivity::Wireless && s.signalStrength > 0) {
      if (!out.empty()) {
        out += "  •  ";
      }
      out += std::to_string(static_cast<int>(s.signalStrength)) + "%";
    }
    return out;
  }

  class AccessPointRow : public Flex {
  public:
    AccessPointRow(float scale, AccessPointInfo ap, bool saved, std::function<void(const AccessPointInfo&)> onActivate,
                   std::function<void(const AccessPointInfo&)> onForget)
        : m_ap(std::move(ap)), m_onActivate(std::move(onActivate)), m_onForget(std::move(onForget)) {
      setDirection(FlexDirection::Horizontal);
      setAlign(FlexAlign::Center);
      setGap(Style::spaceSm * scale);
      setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      setMinHeight(kRowMinHeight * scale);
      setRadius(Style::scaledRadiusMd(scale));
      setFill(colorSpecFromRole(ColorRole::Surface));
      clearBorder();

      auto signalGlyph = std::make_unique<Glyph>();
      signalGlyph->setGlyph(NetworkService::wifiGlyphForSignal(m_ap.strength));
      signalGlyph->setGlyphSize(Style::fontSizeBody * scale);
      signalGlyph->setColor(colorSpecFromRole(ColorRole::OnSurface));
      addChild(std::move(signalGlyph));

      auto ssid = std::make_unique<Label>();
      ssid->setText(m_ap.ssid);
      ssid->setBold(m_ap.active);
      ssid->setFontSize(Style::fontSizeBody * scale);
      ssid->setColor(colorSpecFromRole(ColorRole::OnSurface));
      ssid->setFlexGrow(1.0f);
      m_title = ssid.get();
      addChild(std::move(ssid));

      if (m_ap.secured) {
        auto lock = std::make_unique<Glyph>();
        lock->setGlyph("lock");
        lock->setGlyphSize(Style::fontSizeCaption * scale);
        lock->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
        addChild(std::move(lock));
      }

      auto strength = std::make_unique<Label>();
      strength->setText(std::to_string(static_cast<int>(m_ap.strength)) + "%");
      strength->setCaptionStyle();
      strength->setFontSize(Style::fontSizeCaption * scale);
      strength->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      addChild(std::move(strength));

      auto action = std::make_unique<Button>();
      action->setVariant(ButtonVariant::Ghost);
      action->setGlyphSize(Style::fontSizeBody * scale);
      action->setPadding(Style::spaceXs * scale);
      action->setRadius(Style::scaledRadiusSm(scale));
      if (m_ap.active) {
        action->setGlyph("check");
      } else if (saved) {
        action->setGlyph("trash");
        action->setOnClick([this]() {
          if (m_onForget) {
            m_onForget(m_ap);
          }
        });
      } else {
        action->setOpacity(0.0f);
      }
      m_actionButton = action.get();
      addChild(std::move(action));

      auto area = std::make_unique<InputArea>();
      area->setPropagateEvents(true);
      area->setOnEnter([this](const InputArea::PointerData& /*data*/) { applyState(); });
      area->setOnLeave([this]() { applyState(); });
      area->setOnPress([this](const InputArea::PointerData& /*data*/) { applyState(); });
      area->setOnClick([this](const InputArea::PointerData& /*data*/) {
        if (m_onActivate) {
          m_onActivate(m_ap);
        }
      });
      m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));

      applyState();
      m_paletteConn = paletteChanged().connect([this] { applyState(); });
    }

    void doLayout(Renderer& renderer) override {
      if (m_inputArea == nullptr) {
        return;
      }
      m_inputArea->setVisible(false);
      Flex::doLayout(renderer);
      m_inputArea->setVisible(true);
      m_inputArea->setPosition(0.0f, 0.0f);
      m_inputArea->setSize(width(), height());
      if (m_actionButton != nullptr) {
        const float areaWidth = std::max(0.0f, m_actionButton->x() - gap());
        m_inputArea->setSize(areaWidth, height());
      }
      applyState();
    }

    LayoutSize doMeasure(Renderer& renderer, const LayoutConstraints& constraints) override {
      return measureByLayout(renderer, constraints);
    }

    void doArrange(Renderer& renderer, const LayoutRect& rect) override { arrangeByLayout(renderer, rect); }

  private:
    void applyState() {
      const bool hov = m_inputArea != nullptr && m_inputArea->hovered();
      const bool pressed = m_inputArea != nullptr && m_inputArea->pressed();
      if (pressed) {
        setFill(colorSpecFromRole(ColorRole::Primary));
        setBorder(colorSpecFromRole(ColorRole::Primary), Style::borderWidth);
        if (m_title != nullptr) {
          m_title->setColor(colorSpecFromRole(ColorRole::OnPrimary));
        }
      } else {
        setFill(colorSpecFromRole(ColorRole::Surface));
        if (hov) {
          setBorder(colorSpecFromRole(ColorRole::Hover), Style::borderWidth);
        } else {
          clearBorder();
        }
        if (m_title != nullptr) {
          m_title->setColor(colorSpecFromRole(ColorRole::OnSurface));
        }
      }
    }

    AccessPointInfo m_ap;
    std::function<void(const AccessPointInfo&)> m_onActivate;
    std::function<void(const AccessPointInfo&)> m_onForget;
    Label* m_title = nullptr;
    Button* m_actionButton = nullptr;
    InputArea* m_inputArea = nullptr;
    Signal<>::ScopedConnection m_paletteConn;
  };

  class VpnConnectionRow : public Flex {
  public:
    VpnConnectionRow(float scale, VpnConnectionInfo vpn, std::function<void(const VpnConnectionInfo&)> onActivate,
                     std::function<void(const VpnConnectionInfo&)> onDeactivate)
        : m_vpn(std::move(vpn)), m_onActivate(std::move(onActivate)), m_onDeactivate(std::move(onDeactivate)) {
      setDirection(FlexDirection::Horizontal);
      setAlign(FlexAlign::Center);
      setGap(Style::spaceSm * scale);
      setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      setMinHeight(kRowMinHeight * scale);
      setRadius(Style::scaledRadiusMd(scale));
      setFill(colorSpecFromRole(ColorRole::Surface));
      clearBorder();

      auto name = std::make_unique<Label>();
      name->setText(m_vpn.name);
      name->setBold(m_vpn.active);
      name->setFontSize(Style::fontSizeBody * scale);
      name->setColor(colorSpecFromRole(ColorRole::OnSurface));
      name->setFlexGrow(1.0f);
      m_title = name.get();
      addChild(std::move(name));

      auto check = std::make_unique<Button>();
      check->setVariant(ButtonVariant::Ghost);
      check->setGlyph("check");
      check->setGlyphSize(Style::fontSizeBody * scale);
      check->setPadding(Style::spaceXs * scale);
      check->setRadius(Style::scaledRadiusSm(scale));
      check->setOpacity(m_vpn.active ? 1.0f : 0.0f);
      m_checkButton = check.get();
      addChild(std::move(check));

      auto action = std::make_unique<Button>();
      action->setVariant(m_vpn.active ? ButtonVariant::Destructive : ButtonVariant::Default);
      action->setGlyph(m_vpn.active ? "plug-off" : "plug");
      action->setGlyphSize(Style::fontSizeBody * scale);
      action->setPadding(Style::spaceXs * scale);
      action->setRadius(Style::scaledRadiusSm(scale));
      action->setOnClick([this]() { triggerAction(); });
      m_actionButton = static_cast<Button*>(addChild(std::move(action)));

      auto area = std::make_unique<InputArea>();
      area->setPropagateEvents(true);
      area->setOnEnter([this](const InputArea::PointerData& /*data*/) { applyState(); });
      area->setOnLeave([this]() { applyState(); });
      area->setOnPress([this](const InputArea::PointerData& /*data*/) { applyState(); });
      area->setOnClick([this](const InputArea::PointerData& /*data*/) { triggerAction(); });
      m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));

      applyState();
      m_paletteConn = paletteChanged().connect([this] { applyState(); });
    }

    void doLayout(Renderer& renderer) override {
      if (m_inputArea == nullptr) {
        return;
      }
      m_inputArea->setVisible(false);
      Flex::doLayout(renderer);
      m_inputArea->setVisible(true);
      m_inputArea->setPosition(0.0f, 0.0f);
      m_inputArea->setSize(width(), height());
      if (m_actionButton != nullptr) {
        const float areaWidth = std::max(0.0f, m_actionButton->x() - gap());
        m_inputArea->setSize(areaWidth, height());
      }
      applyState();
    }

    LayoutSize doMeasure(Renderer& renderer, const LayoutConstraints& constraints) override {
      return measureByLayout(renderer, constraints);
    }

    void doArrange(Renderer& renderer, const LayoutRect& rect) override { arrangeByLayout(renderer, rect); }

  private:
    void triggerAction() {
      if (m_vpn.active) {
        if (m_onDeactivate) {
          m_onDeactivate(m_vpn);
        }
      } else {
        if (m_onActivate) {
          m_onActivate(m_vpn);
        }
      }
    }

    void applyState() {
      const bool hov = m_inputArea != nullptr && m_inputArea->hovered();
      const bool pressed = m_inputArea != nullptr && m_inputArea->pressed();
      if (pressed) {
        setFill(colorSpecFromRole(ColorRole::Primary));
        setBorder(colorSpecFromRole(ColorRole::Primary), Style::borderWidth);
        if (m_title != nullptr) {
          m_title->setColor(colorSpecFromRole(ColorRole::OnPrimary));
        }
        return;
      }
      setFill(colorSpecFromRole(ColorRole::Surface));
      if (hov) {
        setBorder(colorSpecFromRole(ColorRole::Hover), Style::borderWidth);
      } else {
        clearBorder();
      }
      if (m_title != nullptr) {
        m_title->setColor(colorSpecFromRole(ColorRole::OnSurface));
      }
    }

    VpnConnectionInfo m_vpn;
    std::function<void(const VpnConnectionInfo&)> m_onActivate;
    std::function<void(const VpnConnectionInfo&)> m_onDeactivate;
    Label* m_title = nullptr;
    Button* m_checkButton = nullptr;
    Button* m_actionButton = nullptr;
    InputArea* m_inputArea = nullptr;
    Signal<>::ScopedConnection m_paletteConn;
  };

} // namespace

NetworkTab::NetworkTab(INetworkService* network, NetworkSecretAgent* secrets) : m_network(network), m_secrets(secrets) {
  if (m_secrets != nullptr) {
    m_secrets->setRequestCallback([this](const NetworkSecretAgent::SecretRequest& request) {
      showPasswordPrompt(request);
      PanelManager::instance().refresh();
    });
  }
}

NetworkTab::~NetworkTab() {
  if (m_secrets != nullptr) {
    m_secrets->setRequestCallback(nullptr);
    m_secrets->cancelSecret();
  }
}

std::unique_ptr<Flex> NetworkTab::create() {
  const float scale = contentScale();

  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  auto currentCard = std::make_unique<Flex>();
  applySectionCardStyle(*currentCard, scale, panelCardOpacity());
  m_currentCard = currentCard.get();
  addTitle(*currentCard, i18n::tr("control-center.network.current-connection"), scale);

  auto connRow = std::make_unique<Flex>();
  connRow->setDirection(FlexDirection::Horizontal);
  connRow->setAlign(FlexAlign::Center);
  connRow->setGap(Style::spaceSm * scale);
  m_disconnectRow = connRow.get();

  auto title = std::make_unique<Label>();
  title->setBold(true);
  title->setFontSize(Style::fontSizeBody * scale);
  title->setColor(colorSpecFromRole(ColorRole::OnSurface));
  m_currentTitle = title.get();
  connRow->addChild(std::move(title));

  auto detail = std::make_unique<Label>();
  detail->setCaptionStyle();
  detail->setFontSize(Style::fontSizeCaption * scale);
  detail->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  detail->setFlexGrow(1.0f);
  m_currentDetail = detail.get();
  connRow->addChild(std::move(detail));

  auto disconnect = std::make_unique<Button>();
  disconnect->setVariant(ButtonVariant::Destructive);
  disconnect->setGlyph("plug-off");
  disconnect->setGlyphSize(Style::fontSizeBody * scale);
  disconnect->setPadding(Style::spaceXs * scale);
  disconnect->setRadius(Style::scaledRadiusSm(scale));
  disconnect->setOnClick([this]() {
    if (m_network != nullptr) {
      m_network->disconnect();
    }
    PanelManager::instance().refresh();
  });
  m_disconnectButton = disconnect.get();
  connRow->addChild(std::move(disconnect));
  currentCard->addChild(std::move(connRow));

  tab->addChild(std::move(currentCard));

  auto passwordCard = std::make_unique<Flex>();
  applySectionCardStyle(*passwordCard, scale, panelCardOpacity());
  passwordCard->setVisible(false);
  m_passwordCard = passwordCard.get();

  auto passwordTitle = std::make_unique<Label>();
  passwordTitle->setBold(true);
  passwordTitle->setFontSize(Style::fontSizeBody * scale);
  passwordTitle->setColor(colorSpecFromRole(ColorRole::OnSurface));
  m_passwordTitle = passwordTitle.get();
  passwordCard->addChild(std::move(passwordTitle));

  auto inputRow = std::make_unique<Flex>();
  inputRow->setDirection(FlexDirection::Horizontal);
  inputRow->setAlign(FlexAlign::Center);
  inputRow->setGap(Style::spaceSm * scale);

  auto passwordInput = std::make_unique<Input>();
  passwordInput->setPlaceholder(i18n::tr("control-center.network.password"));
  passwordInput->setFlexGrow(1.0f);
  passwordInput->setPasswordMode(true);
  passwordInput->setOnSubmit([this](const std::string& value) { submitPasswordPrompt(value); });
  m_passwordInput = passwordInput.get();
  inputRow->addChild(std::move(passwordInput));

  auto revealButton = std::make_unique<Button>();
  revealButton->setVariant(ButtonVariant::Ghost);
  revealButton->setGlyph("eye");
  revealButton->setGlyphSize(Style::fontSizeBody * scale);
  revealButton->setMinWidth(Style::controlHeightSm * scale);
  revealButton->setMinHeight(Style::controlHeightSm * scale);
  revealButton->setPadding(Style::spaceXs * scale);
  revealButton->setRadius(Style::scaledRadiusMd(scale));
  revealButton->setOnClick([this]() {
    if (m_passwordInput == nullptr) {
      return;
    }
    m_passwordRevealed = !m_passwordRevealed;
    m_passwordInput->setPasswordMode(!m_passwordRevealed);
    if (m_passwordRevealButton != nullptr) {
      m_passwordRevealButton->setGlyph(m_passwordRevealed ? "eye-off" : "eye");
    }
  });
  m_passwordRevealButton = revealButton.get();
  inputRow->addChild(std::move(revealButton));

  auto connectButton = std::make_unique<Button>();
  connectButton->setVariant(ButtonVariant::Default);
  connectButton->setText(i18n::tr("control-center.network.connect"));
  connectButton->setOnClick(
      [this]() { submitPasswordPrompt(m_passwordInput != nullptr ? m_passwordInput->value() : std::string{}); });
  inputRow->addChild(std::move(connectButton));

  auto cancelButton = std::make_unique<Button>();
  cancelButton->setVariant(ButtonVariant::Ghost);
  cancelButton->setText(i18n::tr("common.actions.cancel"));
  cancelButton->setOnClick([this]() { cancelPasswordPrompt(); });
  inputRow->addChild(std::move(cancelButton));

  passwordCard->addChild(std::move(inputRow));
  tab->addChild(std::move(passwordCard));

  auto listCard = std::make_unique<Flex>();
  applySectionCardStyle(*listCard, scale, panelCardOpacity());
  listCard->setFlexGrow(1.0f);
  m_listCard = listCard.get();
  addTitle(*listCard, i18n::tr("control-center.network.available-networks"), scale);

  auto listScroll = std::make_unique<ScrollView>();
  listScroll->setFlexGrow(1.0f);
  listScroll->setScrollbarVisible(true);
  listScroll->setViewportPaddingH(0.0f);
  listScroll->setViewportPaddingV(0.0f);
  listScroll->clearFill();
  listScroll->clearBorder();
  m_listScroll = listScroll.get();
  m_list = listScroll->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Stretch);
  m_list->setGap(Style::spaceXs * scale);
  listCard->addChild(std::move(listScroll));

  tab->addChild(std::move(listCard));
  return tab;
}

std::unique_ptr<Flex> NetworkTab::createHeaderActions() { return nullptr; }

void NetworkTab::setActive(bool active) {
  if (m_active == active) {
    return;
  }
  m_active = active;
  if (m_active && m_network != nullptr) {
    m_network->requestScan();
  }
}

void NetworkTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr) {
    return;
  }
  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);
  syncPasswordCard();
  rebuildApList(renderer);
  syncCurrentCard();
  m_rootLayout->layout(renderer);
}

void NetworkTab::doUpdate(Renderer& renderer) {
  syncPasswordCard();
  rebuildApList(renderer);
  syncCurrentCard();
}

void NetworkTab::onClose() {
  m_rootLayout = nullptr;
  m_currentCard = nullptr;
  m_currentTitle = nullptr;
  m_currentDetail = nullptr;
  m_passwordCard = nullptr;
  m_passwordTitle = nullptr;
  m_passwordInput = nullptr;
  m_passwordRevealButton = nullptr;
  m_passwordRevealed = false;
  m_listCard = nullptr;
  m_listScroll = nullptr;
  m_list = nullptr;
  m_rescanButton = nullptr;
  m_wifiToggle = nullptr;
  m_scanSpinner = nullptr;
  m_disconnectRow = nullptr;
  m_disconnectButton = nullptr;
  m_vpnSection = nullptr;
  m_apRows = nullptr;
  m_lastStructureKey.clear();
  m_lastApRowsKey.clear();
  m_lastListWidth = -1.0f;
  m_pendingAccessPoint.reset();
  m_active = false;
}

void NetworkTab::syncPasswordCard() {
  if (m_passwordCard == nullptr) {
    return;
  }
  m_passwordCard->setVisible(m_hasPendingSecret);
  if (m_hasPendingSecret && m_passwordTitle != nullptr) {
    m_passwordTitle->setText(m_pendingSsid.empty()
                                 ? i18n::tr("control-center.network.password-prompt")
                                 : i18n::tr("control-center.network.password-prompt-for", "ssid", m_pendingSsid));
  }
}

void NetworkTab::showPasswordPrompt(const NetworkSecretAgent::SecretRequest& request) {
  m_hasPendingSecret = true;
  m_pendingSsid = request.ssid;
  m_pendingAccessPoint.reset();
  m_passwordRevealed = false;
  if (m_passwordInput != nullptr) {
    m_passwordInput->setValue("");
    m_passwordInput->setPasswordMode(true);
  }
  if (m_passwordRevealButton != nullptr) {
    m_passwordRevealButton->setGlyph("eye");
  }
}

void NetworkTab::showPasswordPrompt(const AccessPointInfo& ap) {
  m_hasPendingSecret = true;
  m_pendingSsid = ap.ssid;
  m_pendingAccessPoint = ap;
  m_passwordRevealed = false;
  if (m_passwordInput != nullptr) {
    m_passwordInput->setValue("");
    m_passwordInput->setPasswordMode(true);
  }
  if (m_passwordRevealButton != nullptr) {
    m_passwordRevealButton->setGlyph("eye");
  }
}

void NetworkTab::submitPasswordPrompt(const std::string& value) {
  if (m_pendingAccessPoint.has_value()) {
    if (value.empty()) {
      return;
    }
    if (m_network != nullptr) {
      m_network->activateAccessPoint(*m_pendingAccessPoint, value);
    }
  } else if (m_secrets != nullptr) {
    m_secrets->submitSecret(value);
  }
  clearPasswordPrompt();
  PanelManager::instance().refresh();
}

void NetworkTab::cancelPasswordPrompt() {
  if (!m_pendingAccessPoint.has_value() && m_secrets != nullptr) {
    m_secrets->cancelSecret();
  }
  clearPasswordPrompt();
  PanelManager::instance().refresh();
}

void NetworkTab::clearPasswordPrompt() {
  m_hasPendingSecret = false;
  m_pendingSsid.clear();
  m_pendingAccessPoint.reset();
  m_passwordRevealed = false;
  if (m_passwordInput != nullptr) {
    m_passwordInput->setValue("");
    m_passwordInput->setPasswordMode(true);
  }
  if (m_passwordRevealButton != nullptr) {
    m_passwordRevealButton->setGlyph("eye");
  }
}

void NetworkTab::syncCurrentCard() {
  if (m_currentTitle == nullptr || m_currentDetail == nullptr) {
    return;
  }
  if (m_network == nullptr) {
    m_currentTitle->setText(i18n::tr("control-center.network.unavailable-title"));
    m_currentDetail->setText(i18n::tr("control-center.network.unavailable-detail"));
    if (m_disconnectRow != nullptr) {
      m_disconnectRow->setVisible(false);
    }
    return;
  }
  const NetworkState& s = m_network->state();
  m_currentTitle->setText(currentTitle(s));
  m_currentDetail->setText(currentDetail(s));
  if (m_disconnectRow != nullptr) {
    m_disconnectRow->setVisible(s.connected);
  }
  if (m_wifiToggle != nullptr) {
    m_wifiToggle->setChecked(s.wirelessEnabled);
  }
  if (m_scanSpinner != nullptr) {
    m_scanSpinner->setVisible(s.scanning);
    if (s.scanning && !m_scanSpinner->spinning()) {
      m_scanSpinner->start();
    } else if (!s.scanning && m_scanSpinner->spinning()) {
      m_scanSpinner->stop();
    }
  }
}

std::string NetworkTab::structureKey(const std::vector<AccessPointInfo>& aps,
                                     const std::vector<VpnConnectionInfo>& vpns) const {
  std::string key;
  for (const auto& ap : aps) {
    key += ap.ssid;
    key.push_back(':');
    key += ap.secured ? '1' : '0';
    key.push_back(':');
    key += ap.active ? '1' : '0';
    key.push_back(':');
    key += (m_network != nullptr && m_network->hasSavedConnection(ap.ssid)) ? '1' : '0';
    key.push_back('\n');
  }
  key += "---\n";
  for (const auto& vpn : vpns) {
    key += vpn.path;
    key.push_back(':');
    key += vpn.name;
    key.push_back(':');
    key += vpn.active ? '1' : '0';
    key.push_back('\n');
  }
  const bool wirelessEnabled = m_network != nullptr && m_network->state().wirelessEnabled;
  const bool scanning = m_network != nullptr && m_network->state().scanning;
  key += "vis:";
  key += m_vpnVisible ? '1' : '0';
  key += "\nwifi:";
  key += wirelessEnabled ? '1' : '0';
  key += "\nscan:";
  key += scanning ? '1' : '0';
  return key;
}

std::string NetworkTab::apRowsKey(const std::vector<AccessPointInfo>& aps) const {
  std::string key;
  for (const auto& ap : aps) {
    key += ap.ssid;
    key.push_back(':');
    key += std::to_string(ap.strength);
    key.push_back('\n');
  }
  return key;
}

void NetworkTab::rebuildApList(Renderer& renderer) {
  uiAssertNotRendering("NetworkTab::rebuildApList");
  if (m_list == nullptr || m_listScroll == nullptr) {
    return;
  }
  const float listWidth = m_listScroll->contentViewportWidth();
  if (listWidth <= 0.0f) {
    return;
  }

  const auto& aps = m_network != nullptr ? m_network->accessPoints() : std::vector<AccessPointInfo>{};
  const auto& vpns = m_network != nullptr ? m_network->vpnConnections() : std::vector<VpnConnectionInfo>{};
  const std::string nextStructure = structureKey(aps, vpns);
  const std::string nextApRows = apRowsKey(aps);
  const bool structureChanged = listWidth != m_lastListWidth || nextStructure != m_lastStructureKey;
  const bool apRowsChanged = nextApRows != m_lastApRowsKey;

  if (!structureChanged && !apRowsChanged) {
    return;
  }
  m_lastListWidth = listWidth;
  m_lastStructureKey = nextStructure;
  m_lastApRowsKey = nextApRows;
  const float scale = contentScale();

  auto buildApRows = [&]() {
    auto container = std::make_unique<Flex>();
    container->setDirection(FlexDirection::Vertical);
    container->setAlign(FlexAlign::Stretch);
    container->setGap(Style::spaceXs * scale);
    if (aps.empty()) {
      auto empty = std::make_unique<Label>();
      empty->setText(i18n::tr("control-center.network.no-networks"));
      empty->setCaptionStyle();
      empty->setFontSize(Style::fontSizeCaption * scale);
      empty->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      container->addChild(std::move(empty));
    } else {
      for (const auto& ap : aps) {
        const bool saved = m_network != nullptr && m_network->hasSavedConnection(ap.ssid);
        auto row = std::make_unique<AccessPointRow>(
            scale, ap, saved,
            [this](const AccessPointInfo& clicked) {
              if (clicked.active || m_network == nullptr) {
                return;
              }
              if (clicked.secured && !m_network->hasSavedConnection(clicked.ssid)) {
                showPasswordPrompt(clicked);
                PanelManager::instance().refresh();
                return;
              }
              m_network->activateAccessPoint(clicked);
            },
            [this](const AccessPointInfo& clicked) {
              if (m_network != nullptr) {
                m_network->forgetSsid(clicked.ssid);
              }
              PanelManager::instance().refresh();
            });
        container->addChild(std::move(row));
      }
    }
    return container;
  };

  if (!structureChanged) {
    if (m_apRows != nullptr) {
      const auto& siblings = m_list->children();
      std::size_t idx = 0;
      for (; idx < siblings.size(); ++idx) {
        if (siblings[idx].get() == m_apRows) {
          break;
        }
      }
      m_list->removeChild(m_apRows);
      auto newRows = buildApRows();
      m_apRows = newRows.get();
      m_list->insertChildAt(idx, std::move(newRows));
    }
    m_list->layout(renderer);
    return;
  }

  m_wifiToggle = nullptr;
  m_scanSpinner = nullptr;
  m_rescanButton = nullptr;
  m_vpnSection = nullptr;
  m_apRows = nullptr;

  while (!m_list->children().empty()) {
    m_list->removeChild(m_list->children().front().get());
  }

  if (m_network == nullptr) {
    auto empty = std::make_unique<Label>();
    empty->setText(i18n::tr("control-center.network.unavailable-title"));
    empty->setCaptionStyle();
    empty->setFontSize(Style::fontSizeCaption * scale);
    empty->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    m_list->addChild(std::move(empty));
  } else {
    if (!vpns.empty()) {
      auto vpnSection = std::make_unique<Flex>();
      vpnSection->setDirection(FlexDirection::Vertical);
      vpnSection->setAlign(FlexAlign::Stretch);
      vpnSection->setGap(Style::spaceXs * scale);

      auto vpnHeader = std::make_unique<Flex>();
      vpnHeader->setDirection(FlexDirection::Horizontal);
      vpnHeader->setAlign(FlexAlign::Center);
      vpnHeader->setGap(Style::spaceSm * scale);
      vpnHeader->setMinHeight(Style::controlHeightSm * scale);

      auto vpnLabel = std::make_unique<Label>();
      vpnLabel->setText(i18n::tr("control-center.network.vpns"));
      vpnLabel->setCaptionStyle();
      vpnLabel->setFontSize(Style::fontSizeCaption * scale);
      vpnLabel->setColor(colorSpecFromRole(ColorRole::Secondary));
      vpnLabel->setFlexGrow(1.0f);
      vpnHeader->addChild(std::move(vpnLabel));

      auto vpnToggle = std::make_unique<Toggle>();
      vpnToggle->setToggleSize(ToggleSize::Small);
      vpnToggle->setScale(scale);
      vpnToggle->setCheckedImmediate(m_vpnVisible);
      vpnToggle->setOnChange([this](bool checked) {
        m_vpnVisible = checked;
        PanelManager::instance().refresh();
      });
      vpnHeader->addChild(std::move(vpnToggle));
      vpnSection->addChild(std::move(vpnHeader));

      if (m_vpnVisible) {
        for (const auto& vpn : vpns) {
          auto row = std::make_unique<VpnConnectionRow>(
              scale, vpn,
              [this](const VpnConnectionInfo& clicked) {
                if (m_network != nullptr) {
                  m_network->activateVpnConnection(clicked);
                }
                PanelManager::instance().refresh();
              },
              [this](const VpnConnectionInfo& clicked) {
                if (m_network != nullptr) {
                  m_network->deactivateVpnConnection(clicked);
                }
                PanelManager::instance().refresh();
              });
          vpnSection->addChild(std::move(row));
        }
      }

      m_vpnSection = vpnSection.get();
      m_list->addChild(std::move(vpnSection));
      m_list->addChild(std::make_unique<Separator>());
    }

    {
      auto wifiHeader = std::make_unique<Flex>();
      wifiHeader->setDirection(FlexDirection::Horizontal);
      wifiHeader->setAlign(FlexAlign::Center);
      wifiHeader->setGap(Style::spaceSm * scale);
      wifiHeader->setMinHeight(Style::controlHeightSm * scale);
      wifiHeader->setMaxHeight(Style::controlHeightSm * scale);

      auto wifiLabel = std::make_unique<Label>();
      wifiLabel->setText(i18n::tr("control-center.network.wireless"));
      wifiLabel->setCaptionStyle();
      wifiLabel->setFontSize(Style::fontSizeCaption * scale);
      wifiLabel->setColor(colorSpecFromRole(ColorRole::Secondary));
      wifiLabel->setFlexGrow(1.0f);
      wifiHeader->addChild(std::move(wifiLabel));

      auto spinner = std::make_unique<Spinner>();
      spinner->setSpinnerSize(Style::fontSizeCaption * scale);
      spinner->setColor(colorSpecFromRole(ColorRole::Primary));
      m_scanSpinner = spinner.get();
      wifiHeader->addChild(std::move(spinner));

      auto rescan = std::make_unique<Button>();
      rescan->setVariant(ButtonVariant::Ghost);
      rescan->setGlyph("refresh");
      rescan->setGlyphSize(Style::fontSizeCaption * scale);
      rescan->setPadding(Style::spaceXs * scale);
      rescan->setRadius(Style::scaledRadiusSm(scale));
      rescan->setOnClick([this]() {
        if (m_network != nullptr) {
          m_network->requestScan();
        }
      });
      m_rescanButton = rescan.get();
      wifiHeader->addChild(std::move(rescan));

      auto wifiToggle = std::make_unique<Toggle>();
      wifiToggle->setToggleSize(ToggleSize::Small);
      wifiToggle->setScale(scale);
      wifiToggle->setOnChange([this](bool checked) {
        if (m_network != nullptr) {
          m_network->setWirelessEnabled(checked);
        }
      });
      m_wifiToggle = wifiToggle.get();
      wifiHeader->addChild(std::move(wifiToggle));
      m_list->addChild(std::move(wifiHeader));

      const auto& s = m_network->state();
      m_wifiToggle->setCheckedImmediate(s.wirelessEnabled);
      m_scanSpinner->setVisible(s.scanning);
      if (s.scanning) {
        m_scanSpinner->start();
      }
    }

    auto apRows = buildApRows();
    m_apRows = apRows.get();
    m_list->addChild(std::move(apRows));
  }
  m_list->layout(renderer);
}
