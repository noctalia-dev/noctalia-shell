#include "shell/control_center/network_tab.h"

#include "core/ui_phase.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
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
      return s.interfaceName.empty() ? std::string("Wired connection") : s.interfaceName;
    }
    return "Not connected";
  }

  std::string currentDetail(const NetworkState& s) {
    if (!s.connected) {
      return s.wirelessEnabled ? "Wi-Fi is on" : "Wi-Fi is off";
    }
    std::string out;
    if (!s.interfaceName.empty()) {
      out = s.interfaceName;
    }
    if (!s.ipv4.empty()) {
      if (!out.empty()) {
        out += "  •  ";
      }
      out += s.ipv4;
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
    AccessPointRow(AccessPointInfo ap, bool saved, std::function<void(const AccessPointInfo&)> onActivate,
                   std::function<void(const AccessPointInfo&)> onForget)
        : m_ap(std::move(ap)), m_onActivate(std::move(onActivate)), m_onForget(std::move(onForget)) {
      setDirection(FlexDirection::Horizontal);
      setAlign(FlexAlign::Center);
      setGap(Style::spaceSm);
      setPadding(Style::spaceSm, Style::spaceMd);
      setMinHeight(kRowMinHeight);
      setRadius(Style::radiusMd);
      setBackground(roleColor(ColorRole::Surface));
      setBorderWidth(0.0f);

      auto signalGlyph = std::make_unique<Glyph>();
      signalGlyph->setGlyph(NetworkTab_rowGlyph(m_ap));
      signalGlyph->setGlyphSize(Style::fontSizeBody);
      signalGlyph->setColor(roleColor(ColorRole::OnSurface));
      addChild(std::move(signalGlyph));

      auto ssid = std::make_unique<Label>();
      ssid->setText(m_ap.ssid);
      ssid->setBold(m_ap.active);
      ssid->setFontSize(Style::fontSizeBody);
      ssid->setColor(roleColor(ColorRole::OnSurface));
      ssid->setFlexGrow(1.0f);
      m_title = ssid.get();
      addChild(std::move(ssid));

      if (m_ap.secured) {
        auto lock = std::make_unique<Glyph>();
        lock->setGlyph("lock");
        lock->setGlyphSize(Style::fontSizeCaption);
        lock->setColor(roleColor(ColorRole::OnSurfaceVariant));
        addChild(std::move(lock));
      }

      auto strength = std::make_unique<Label>();
      strength->setText(std::to_string(static_cast<int>(m_ap.strength)) + "%");
      strength->setCaptionStyle();
      strength->setFontSize(Style::fontSizeCaption);
      strength->setColor(roleColor(ColorRole::OnSurfaceVariant));
      addChild(std::move(strength));

      if (saved) {
        auto forget = std::make_unique<Button>();
        forget->setVariant(ButtonVariant::Ghost);
        forget->setText("Forget");
        forget->setOnClick([this]() {
          if (m_onForget) {
            m_onForget(m_ap);
          }
        });
        m_forgetButton = static_cast<Button*>(addChild(std::move(forget)));
      }

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
      // Carve out the forget button so its own InputArea gets clicks first.
      if (m_forgetButton != nullptr) {
        const float areaWidth = std::max(0.0f, m_forgetButton->x() - gap());
        m_inputArea->setSize(areaWidth, height());
      }
      applyState();
    }

    static const char* NetworkTab_rowGlyph(const AccessPointInfo& ap) {
      if (ap.strength >= 67) {
        return "wifi-2";
      }
      if (ap.strength >= 34) {
        return "wifi-1";
      }
      return "wifi-0";
    }

  private:
    void applyState() {
      const bool hov = m_inputArea != nullptr && m_inputArea->hovered();
      const bool pressed = m_inputArea != nullptr && m_inputArea->pressed();
      if (pressed) {
        setBackground(roleColor(ColorRole::Primary));
        setBorderColor(roleColor(ColorRole::Primary));
        setBorderWidth(Style::borderWidth);
        if (m_title != nullptr) {
          m_title->setColor(roleColor(ColorRole::OnPrimary));
        }
        return;
      }
      setBackground(roleColor(m_ap.active ? ColorRole::Secondary : ColorRole::Surface, m_ap.active ? 0.25f : 1.0f));
      setBorderColor(roleColor(hov ? ColorRole::Primary : ColorRole::Surface));
      setBorderWidth(hov ? Style::borderWidth : 0.0f);
      if (m_title != nullptr) {
        m_title->setColor(roleColor(ColorRole::OnSurface));
      }
    }

    AccessPointInfo m_ap;
    std::function<void(const AccessPointInfo&)> m_onActivate;
    std::function<void(const AccessPointInfo&)> m_onForget;
    Label* m_title = nullptr;
    InputArea* m_inputArea = nullptr;
    Button* m_forgetButton = nullptr;
    Signal<>::ScopedConnection m_paletteConn;
  };

} // namespace

NetworkTab::NetworkTab(NetworkService* network, NetworkSecretAgent* secrets) : m_network(network), m_secrets(secrets) {
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
  applyOutlinedCard(*currentCard, scale);
  m_currentCard = currentCard.get();
  addTitle(*currentCard, "Current connection", scale);

  auto detailRow = std::make_unique<Flex>();
  detailRow->setDirection(FlexDirection::Horizontal);
  detailRow->setAlign(FlexAlign::Center);
  detailRow->setGap(Style::spaceSm * scale);

  auto title = std::make_unique<Label>();
  title->setBold(true);
  title->setFontSize(Style::fontSizeBody * scale);
  title->setColor(roleColor(ColorRole::OnSurface));
  m_currentTitle = title.get();
  detailRow->addChild(std::move(title));
  currentCard->addChild(std::move(detailRow));

  auto detail = std::make_unique<Label>();
  detail->setCaptionStyle();
  detail->setFontSize(Style::fontSizeCaption * scale);
  detail->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_currentDetail = detail.get();
  currentCard->addChild(std::move(detail));

  auto disconnect = std::make_unique<Button>();
  disconnect->setVariant(ButtonVariant::Outline);
  disconnect->setText("Disconnect");
  disconnect->setOnClick([this]() {
    if (m_network != nullptr) {
      m_network->disconnect();
    }
    PanelManager::instance().refresh();
  });
  m_disconnectButton = disconnect.get();
  currentCard->addChild(std::move(disconnect));

  tab->addChild(std::move(currentCard));

  auto passwordCard = std::make_unique<Flex>();
  applyOutlinedCard(*passwordCard, scale);
  passwordCard->setVisible(false);
  m_passwordCard = passwordCard.get();

  auto passwordTitle = std::make_unique<Label>();
  passwordTitle->setBold(true);
  passwordTitle->setFontSize(Style::fontSizeBody * scale);
  passwordTitle->setColor(roleColor(ColorRole::OnSurface));
  m_passwordTitle = passwordTitle.get();
  passwordCard->addChild(std::move(passwordTitle));

  auto inputRow = std::make_unique<Flex>();
  inputRow->setDirection(FlexDirection::Horizontal);
  inputRow->setAlign(FlexAlign::Center);
  inputRow->setGap(Style::spaceSm * scale);

  auto passwordInput = std::make_unique<Input>();
  passwordInput->setPlaceholder("Password");
  passwordInput->setFlexGrow(1.0f);
  passwordInput->setOnSubmit([this](const std::string& value) {
    if (m_secrets != nullptr) {
      m_secrets->submitSecret(value);
    }
    clearPasswordPrompt();
    PanelManager::instance().refresh();
  });
  m_passwordInput = passwordInput.get();
  inputRow->addChild(std::move(passwordInput));

  auto connectButton = std::make_unique<Button>();
  connectButton->setVariant(ButtonVariant::Default);
  connectButton->setText("Connect");
  connectButton->setOnClick([this]() {
    if (m_secrets != nullptr && m_passwordInput != nullptr) {
      m_secrets->submitSecret(m_passwordInput->value());
    }
    clearPasswordPrompt();
    PanelManager::instance().refresh();
  });
  inputRow->addChild(std::move(connectButton));

  auto cancelButton = std::make_unique<Button>();
  cancelButton->setVariant(ButtonVariant::Ghost);
  cancelButton->setText("Cancel");
  cancelButton->setOnClick([this]() {
    if (m_secrets != nullptr) {
      m_secrets->cancelSecret();
    }
    clearPasswordPrompt();
    PanelManager::instance().refresh();
  });
  inputRow->addChild(std::move(cancelButton));

  passwordCard->addChild(std::move(inputRow));
  tab->addChild(std::move(passwordCard));

  auto listCard = std::make_unique<Flex>();
  applyOutlinedCard(*listCard, scale);
  listCard->setFlexGrow(1.0f);
  m_listCard = listCard.get();
  addTitle(*listCard, "Available networks", scale);

  auto listScroll = std::make_unique<ScrollView>();
  listScroll->setFlexGrow(1.0f);
  listScroll->setScrollbarVisible(true);
  listScroll->setViewportPaddingH(0.0f);
  listScroll->setViewportPaddingV(0.0f);
  listScroll->setBackgroundStyle(rgba(0, 0, 0, 0), rgba(0, 0, 0, 0), 0.0f);
  m_listScroll = listScroll.get();
  m_list = listScroll->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Stretch);
  m_list->setGap(Style::spaceXs * scale);
  listCard->addChild(std::move(listScroll));

  tab->addChild(std::move(listCard));
  return tab;
}

std::unique_ptr<Flex> NetworkTab::createHeaderActions() {
  const float scale = contentScale();
  auto row = std::make_unique<Flex>();
  row->setDirection(FlexDirection::Horizontal);
  row->setAlign(FlexAlign::Center);
  row->setGap(Style::spaceSm * scale);
  row->setMinHeight(Style::controlHeightSm * scale);

  auto wifiLabel = std::make_unique<Label>();
  wifiLabel->setText("Wi-Fi");
  wifiLabel->setFontSize(Style::fontSizeCaption * scale);
  wifiLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
  row->addChild(std::move(wifiLabel));

  auto wifiToggle = std::make_unique<Toggle>();
  wifiToggle->setToggleSize(ToggleSize::Small);
  wifiToggle->setScale(scale);
  wifiToggle->setOnChange([this](bool checked) {
    if (m_network != nullptr) {
      m_network->setWirelessEnabled(checked);
    }
  });
  m_wifiToggle = wifiToggle.get();
  row->addChild(std::move(wifiToggle));

  auto spinner = std::make_unique<Spinner>();
  spinner->setSpinnerSize(Style::fontSizeBody * scale);
  spinner->setColor(roleColor(ColorRole::Primary));
  m_scanSpinner = spinner.get();
  row->addChild(std::move(spinner));

  auto rescan = std::make_unique<Button>();
  rescan->setVariant(ButtonVariant::Default);
  rescan->setGlyph("refresh");
  rescan->setGlyphSize(Style::fontSizeBody * scale);
  rescan->setMinWidth(Style::controlHeightSm * scale);
  rescan->setMinHeight(Style::controlHeightSm * scale);
  rescan->setPadding(Style::spaceXs * scale);
  rescan->setRadius(Style::radiusMd * scale);
  rescan->setOnClick([this]() {
    if (m_network != nullptr) {
      m_network->requestScan();
    }
  });
  m_rescanButton = rescan.get();
  row->addChild(std::move(rescan));
  return row;
}

void NetworkTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr) {
    return;
  }
  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);
  syncCurrentCard();
  syncPasswordCard();
  rebuildApList(renderer);
  m_rootLayout->layout(renderer);
}

void NetworkTab::doUpdate(Renderer& renderer) {
  syncCurrentCard();
  syncPasswordCard();
  rebuildApList(renderer);
}

void NetworkTab::onClose() {
  m_rootLayout = nullptr;
  m_currentCard = nullptr;
  m_currentTitle = nullptr;
  m_currentDetail = nullptr;
  m_passwordCard = nullptr;
  m_passwordTitle = nullptr;
  m_passwordInput = nullptr;
  m_listCard = nullptr;
  m_listScroll = nullptr;
  m_list = nullptr;
  m_rescanButton = nullptr;
  m_wifiToggle = nullptr;
  m_disconnectButton = nullptr;
  m_scanSpinner = nullptr;
  m_lastListKey.clear();
  m_lastListWidth = -1.0f;
}

void NetworkTab::syncPasswordCard() {
  if (m_passwordCard == nullptr) {
    return;
  }
  m_passwordCard->setVisible(m_hasPendingSecret);
  if (m_hasPendingSecret && m_passwordTitle != nullptr) {
    m_passwordTitle->setText(m_pendingSsid.empty() ? std::string("Enter password")
                                                   : ("Enter password for " + m_pendingSsid));
  }
}

void NetworkTab::showPasswordPrompt(const NetworkSecretAgent::SecretRequest& request) {
  m_hasPendingSecret = true;
  m_pendingSsid = request.ssid;
  if (m_passwordInput != nullptr) {
    m_passwordInput->setValue("");
  }
}

void NetworkTab::clearPasswordPrompt() {
  m_hasPendingSecret = false;
  m_pendingSsid.clear();
  if (m_passwordInput != nullptr) {
    m_passwordInput->setValue("");
  }
}

void NetworkTab::syncCurrentCard() {
  if (m_currentTitle == nullptr || m_currentDetail == nullptr) {
    return;
  }
  if (m_network == nullptr) {
    m_currentTitle->setText("NetworkManager unavailable");
    m_currentDetail->setText("Install and enable NetworkManager to manage networks from here.");
    if (m_disconnectButton != nullptr) {
      m_disconnectButton->setVisible(false);
    }
    return;
  }
  const NetworkState& s = m_network->state();
  m_currentTitle->setText(currentTitle(s));
  m_currentDetail->setText(currentDetail(s));
  if (m_disconnectButton != nullptr) {
    m_disconnectButton->setVisible(s.connected);
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

std::string NetworkTab::apListKey(const std::vector<AccessPointInfo>& aps) const {
  std::string key;
  for (const auto& ap : aps) {
    key += ap.ssid;
    key.push_back(':');
    key += std::to_string(ap.strength);
    key.push_back(':');
    key += ap.secured ? '1' : '0';
    key.push_back(':');
    key += ap.active ? '1' : '0';
    key.push_back(':');
    key += (m_network != nullptr && m_network->hasSavedConnection(ap.ssid)) ? '1' : '0';
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
  const std::string nextKey = aps.empty() ? std::string("empty") : apListKey(aps);
  if (listWidth == m_lastListWidth && nextKey == m_lastListKey) {
    return;
  }
  m_lastListWidth = listWidth;
  m_lastListKey = nextKey;

  while (!m_list->children().empty()) {
    m_list->removeChild(m_list->children().front().get());
  }

  if (aps.empty()) {
    auto empty = std::make_unique<Label>();
    empty->setText(m_network != nullptr ? "No networks in range" : "NetworkManager unavailable");
    empty->setCaptionStyle();
    empty->setFontSize(Style::fontSizeCaption);
    empty->setColor(roleColor(ColorRole::OnSurfaceVariant));
    m_list->addChild(std::move(empty));
  } else {
    for (const auto& ap : aps) {
      const bool saved = m_network != nullptr && m_network->hasSavedConnection(ap.ssid);
      auto row = std::make_unique<AccessPointRow>(
          ap, saved,
          [this](const AccessPointInfo& clicked) {
            if (m_network != nullptr) {
              m_network->activateAccessPoint(clicked);
            }
          },
          [this](const AccessPointInfo& clicked) {
            if (m_network != nullptr) {
              m_network->forgetSsid(clicked.ssid);
            }
            PanelManager::instance().refresh();
          });
      m_list->addChild(std::move(row));
    }
  }
  m_list->layout(renderer);
}

const char* NetworkTab::strengthGlyph(const AccessPointInfo& ap) { return AccessPointRow::NetworkTab_rowGlyph(ap); }
