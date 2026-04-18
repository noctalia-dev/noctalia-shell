#include "shell/control_center/bluetooth_tab.h"

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
#include <cstdio>
#include <memory>
#include <string>
#include <utility>

using namespace control_center;

namespace {

  constexpr float kRowMinHeight = Style::controlHeightLg;

  const char* glyphFor(BluetoothDeviceKind kind) {
    switch (kind) {
    case BluetoothDeviceKind::Headset:
      return "bluetooth-device-headset";
    case BluetoothDeviceKind::Headphones:
      return "bluetooth-device-headphones";
    case BluetoothDeviceKind::Earbuds:
      return "bluetooth-device-earbuds";
    case BluetoothDeviceKind::Speaker:
      return "bluetooth-device-speaker";
    case BluetoothDeviceKind::Microphone:
      return "bluetooth-device-microphone";
    case BluetoothDeviceKind::Mouse:
      return "bluetooth-device-mouse";
    case BluetoothDeviceKind::Keyboard:
      return "bluetooth-device-keyboard";
    case BluetoothDeviceKind::Phone:
      return "bluetooth-device-phone";
    case BluetoothDeviceKind::Computer:
      return "settings-display";
    case BluetoothDeviceKind::Gamepad:
      return "bluetooth-device-gamepad";
    case BluetoothDeviceKind::Watch:
      return "bluetooth-device-watch";
    case BluetoothDeviceKind::Tv:
      return "bluetooth-device-tv";
    case BluetoothDeviceKind::Unknown:
    default:
      return "bluetooth-device-generic";
    }
  }

  enum class DeviceBucket : std::uint8_t {
    Connected,
    Paired,
    Available,
  };

  DeviceBucket bucketFor(const BluetoothDeviceInfo& d) {
    if (d.connected) {
      return DeviceBucket::Connected;
    }
    if (d.paired) {
      return DeviceBucket::Paired;
    }
    return DeviceBucket::Available;
  }

  class BluetoothDeviceRow : public Flex {
  public:
    BluetoothDeviceRow(BluetoothDeviceInfo device, BluetoothService* service, float scale)
        : m_device(std::move(device)), m_service(service) {
      setDirection(FlexDirection::Horizontal);
      setAlign(FlexAlign::Center);
      setGap(Style::spaceSm * scale);
      setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
      setMinHeight(kRowMinHeight * scale);
      setRadius(Style::radiusMd * scale);
      setBackground(roleColor(ColorRole::Surface));
      setBorderWidth(0.0f);

      auto icon = std::make_unique<Glyph>();
      icon->setGlyph(glyphFor(m_device.kind));
      icon->setGlyphSize(Style::fontSizeBody * scale);
      icon->setColor(roleColor(ColorRole::OnSurface));
      addChild(std::move(icon));

      auto alias = std::make_unique<Label>();
      alias->setText(m_device.alias);
      alias->setBold(m_device.connected);
      alias->setFontSize(Style::fontSizeBody * scale);
      alias->setColor(roleColor(ColorRole::OnSurface));
      alias->setFlexGrow(1.0f);
      m_title = alias.get();
      addChild(std::move(alias));

      if (m_device.hasBattery) {
        auto battery = std::make_unique<Label>();
        battery->setText(std::to_string(static_cast<int>(m_device.batteryPercent)) + "%");
        battery->setCaptionStyle();
        battery->setFontSize(Style::fontSizeCaption * scale);
        battery->setColor(roleColor(ColorRole::OnSurfaceVariant));
        addChild(std::move(battery));
      } else if (m_device.hasRssi && bucketFor(m_device) == DeviceBucket::Available) {
        auto rssi = std::make_unique<Label>();
        rssi->setText(std::to_string(static_cast<int>(m_device.rssi)) + " dBm");
        rssi->setCaptionStyle();
        rssi->setFontSize(Style::fontSizeCaption * scale);
        rssi->setColor(roleColor(ColorRole::OnSurfaceVariant));
        addChild(std::move(rssi));
      }

      if (m_device.paired) {
        auto trust = std::make_unique<Toggle>();
        trust->setToggleSize(ToggleSize::Small);
        trust->setScale(scale);
        trust->setChecked(m_device.trusted);
        trust->setOnChange([this](bool checked) {
          if (m_service != nullptr) {
            m_service->setTrusted(m_device.path, checked);
          }
        });
        addChild(std::move(trust));
      }

      auto primary = std::make_unique<Button>();
      primary->setVariant(ButtonVariant::Default);
      switch (bucketFor(m_device)) {
      case DeviceBucket::Connected:
        primary->setText("Disconnect");
        primary->setVariant(ButtonVariant::Outline);
        break;
      case DeviceBucket::Paired:
        primary->setText(m_device.connecting ? "Connecting…" : "Connect");
        break;
      case DeviceBucket::Available:
        primary->setText(m_device.connecting ? "Pairing…" : "Pair");
        break;
      }
      primary->setOnClick([this]() {
        if (m_service == nullptr) {
          return;
        }
        switch (bucketFor(m_device)) {
        case DeviceBucket::Connected:
          m_service->disconnectDevice(m_device.path);
          break;
        case DeviceBucket::Paired:
          m_service->connect(m_device.path);
          break;
        case DeviceBucket::Available:
          m_service->pair(m_device.path);
          break;
        }
        PanelManager::instance().refresh();
      });
      m_primaryButton = static_cast<Button*>(addChild(std::move(primary)));

      if (m_device.paired) {
        auto forget = std::make_unique<Button>();
        forget->setVariant(ButtonVariant::Ghost);
        forget->setText("Forget");
        forget->setOnClick([this]() {
          if (m_service != nullptr) {
            m_service->forget(m_device.path);
          }
          PanelManager::instance().refresh();
        });
        m_forgetButton = static_cast<Button*>(addChild(std::move(forget)));
      }
    }

  private:
    BluetoothDeviceInfo m_device;
    BluetoothService* m_service = nullptr;
    Label* m_title = nullptr;
    Button* m_primaryButton = nullptr;
    Button* m_forgetButton = nullptr;
  };

} // namespace

BluetoothTab::BluetoothTab(BluetoothService* service, BluetoothAgent* agent) : m_service(service), m_agent(agent) {}

BluetoothTab::~BluetoothTab() = default;

std::unique_ptr<Flex> BluetoothTab::create() {
  const float scale = contentScale();

  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  auto pairingCard = std::make_unique<Flex>();
  applyOutlinedCard(*pairingCard, scale);
  pairingCard->setVisible(false);
  m_pairingCard = pairingCard.get();

  auto pairingTitle = std::make_unique<Label>();
  pairingTitle->setBold(true);
  pairingTitle->setFontSize(Style::fontSizeBody * scale);
  pairingTitle->setColor(roleColor(ColorRole::OnSurface));
  m_pairingTitle = pairingTitle.get();
  pairingCard->addChild(std::move(pairingTitle));

  auto pairingDetail = std::make_unique<Label>();
  pairingDetail->setCaptionStyle();
  pairingDetail->setFontSize(Style::fontSizeCaption * scale);
  pairingDetail->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_pairingDetail = pairingDetail.get();
  pairingCard->addChild(std::move(pairingDetail));

  auto pairingCode = std::make_unique<Label>();
  pairingCode->setBold(true);
  pairingCode->setFontSize(Style::fontSizeTitle * scale);
  pairingCode->setColor(roleColor(ColorRole::Primary));
  m_pairingCode = pairingCode.get();
  pairingCard->addChild(std::move(pairingCode));

  auto pairingInputRow = std::make_unique<Flex>();
  pairingInputRow->setDirection(FlexDirection::Horizontal);
  pairingInputRow->setAlign(FlexAlign::Center);
  pairingInputRow->setGap(Style::spaceSm * scale);
  pairingInputRow->setVisible(false);
  m_pairingInputRow = pairingInputRow.get();

  auto pairingInput = std::make_unique<Input>();
  pairingInput->setPlaceholder("Enter code");
  pairingInput->setFlexGrow(1.0f);
  pairingInput->setOnSubmit([this](const std::string& value) {
    if (m_agent == nullptr) {
      return;
    }
    const auto req = m_agent->pendingRequest();
    if (req.kind == BluetoothPairingKind::PinCode) {
      m_agent->submitPin(value);
    } else if (req.kind == BluetoothPairingKind::Passkey) {
      try {
        m_agent->submitPasskey(static_cast<std::uint32_t>(std::stoul(value)));
      } catch (...) {
        m_agent->cancelPending();
      }
    }
    PanelManager::instance().refresh();
  });
  m_pairingInput = pairingInput.get();
  pairingInputRow->addChild(std::move(pairingInput));
  pairingCard->addChild(std::move(pairingInputRow));

  auto pairingButtonRow = std::make_unique<Flex>();
  pairingButtonRow->setDirection(FlexDirection::Horizontal);
  pairingButtonRow->setAlign(FlexAlign::Center);
  pairingButtonRow->setGap(Style::spaceSm * scale);
  m_pairingButtonRow = pairingButtonRow.get();

  auto accept = std::make_unique<Button>();
  accept->setVariant(ButtonVariant::Default);
  accept->setText("Accept");
  accept->setOnClick([this]() {
    if (m_agent == nullptr) {
      return;
    }
    const auto req = m_agent->pendingRequest();
    switch (req.kind) {
    case BluetoothPairingKind::Confirm:
    case BluetoothPairingKind::Authorize:
    case BluetoothPairingKind::AuthorizeService:
    case BluetoothPairingKind::DisplayPinCode:
      m_agent->acceptConfirm();
      break;
    case BluetoothPairingKind::PinCode:
      if (m_pairingInput != nullptr) {
        m_agent->submitPin(m_pairingInput->value());
      }
      break;
    case BluetoothPairingKind::Passkey:
      if (m_pairingInput != nullptr) {
        try {
          m_agent->submitPasskey(static_cast<std::uint32_t>(std::stoul(m_pairingInput->value())));
        } catch (...) {
          m_agent->cancelPending();
        }
      }
      break;
    default:
      m_agent->cancelPending();
      break;
    }
    PanelManager::instance().refresh();
  });
  m_pairingAccept = accept.get();
  pairingButtonRow->addChild(std::move(accept));

  auto reject = std::make_unique<Button>();
  reject->setVariant(ButtonVariant::Ghost);
  reject->setText("Reject");
  reject->setOnClick([this]() {
    if (m_agent != nullptr) {
      m_agent->rejectConfirm();
    }
    PanelManager::instance().refresh();
  });
  m_pairingReject = reject.get();
  pairingButtonRow->addChild(std::move(reject));
  pairingCard->addChild(std::move(pairingButtonRow));

  tab->addChild(std::move(pairingCard));

  auto listCard = std::make_unique<Flex>();
  applyOutlinedCard(*listCard, scale);
  listCard->setFlexGrow(1.0f);
  m_listCard = listCard.get();
  addTitle(*listCard, "Devices", scale);

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

std::unique_ptr<Flex> BluetoothTab::createHeaderActions() {
  const float scale = contentScale();
  auto row = std::make_unique<Flex>();
  row->setDirection(FlexDirection::Horizontal);
  row->setAlign(FlexAlign::Center);
  row->setGap(Style::spaceSm * scale);
  row->setMinHeight(Style::controlHeightSm * scale);

  auto powerLabel = std::make_unique<Label>();
  powerLabel->setText("Bluetooth");
  powerLabel->setFontSize(Style::fontSizeCaption * scale);
  powerLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
  row->addChild(std::move(powerLabel));

  auto powerToggle = std::make_unique<Toggle>();
  powerToggle->setToggleSize(ToggleSize::Small);
  powerToggle->setScale(scale);
  powerToggle->setOnChange([this](bool checked) {
    if (m_service != nullptr) {
      m_service->setPowered(checked);
    }
  });
  m_powerToggle = powerToggle.get();
  row->addChild(std::move(powerToggle));

  auto discoverLabel = std::make_unique<Label>();
  discoverLabel->setText("Visible");
  discoverLabel->setFontSize(Style::fontSizeCaption * scale);
  discoverLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
  row->addChild(std::move(discoverLabel));

  auto discoverToggle = std::make_unique<Toggle>();
  discoverToggle->setToggleSize(ToggleSize::Small);
  discoverToggle->setScale(scale);
  discoverToggle->setOnChange([this](bool checked) {
    if (m_service != nullptr) {
      m_service->setDiscoverable(checked);
    }
  });
  m_discoverableToggle = discoverToggle.get();
  row->addChild(std::move(discoverToggle));

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
    if (m_service == nullptr) {
      return;
    }
    // Always stop-then-start: reconciles any stale local "discovering" state
    // with BlueZ (e.g. if a signal was missed after an adapter hiccup) and
    // genuinely restarts the scan in one click.
    m_service->stopDiscovery();
    m_service->startDiscovery();
  });
  m_rescanButton = rescan.get();
  row->addChild(std::move(rescan));
  return row;
}

void BluetoothTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr) {
    return;
  }
  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);
  syncHeader();
  syncPairingCard();
  rebuildDeviceList(renderer);
  m_rootLayout->layout(renderer);
}

void BluetoothTab::doUpdate(Renderer& renderer) {
  syncHeader();
  syncPairingCard();
  rebuildDeviceList(renderer);
}

void BluetoothTab::setActive(bool active) {
  if (!active && m_service != nullptr && m_service->state().discovering) {
    m_service->stopDiscovery();
  }
}

void BluetoothTab::onClose() {
  m_rootLayout = nullptr;
  m_pairingCard = nullptr;
  m_pairingTitle = nullptr;
  m_pairingDetail = nullptr;
  m_pairingCode = nullptr;
  m_pairingInputRow = nullptr;
  m_pairingInput = nullptr;
  m_pairingButtonRow = nullptr;
  m_pairingAccept = nullptr;
  m_pairingReject = nullptr;
  m_listCard = nullptr;
  m_listScroll = nullptr;
  m_list = nullptr;
  m_powerToggle = nullptr;
  m_discoverableToggle = nullptr;
  m_rescanButton = nullptr;
  m_scanSpinner = nullptr;
  m_lastListKey.clear();
  m_lastListWidth = -1.0f;
}

void BluetoothTab::syncHeader() {
  if (m_service == nullptr) {
    return;
  }
  const BluetoothState& s = m_service->state();
  if (m_powerToggle != nullptr) {
    m_powerToggle->setChecked(s.powered);
    m_powerToggle->setEnabled(s.adapterPresent);
  }
  if (m_discoverableToggle != nullptr) {
    m_discoverableToggle->setChecked(s.discoverable);
    m_discoverableToggle->setEnabled(s.adapterPresent && s.powered);
  }
  if (m_scanSpinner != nullptr) {
    m_scanSpinner->setVisible(s.discovering);
    if (s.discovering && !m_scanSpinner->spinning()) {
      m_scanSpinner->start();
    } else if (!s.discovering && m_scanSpinner->spinning()) {
      m_scanSpinner->stop();
    }
  }
}

void BluetoothTab::syncPairingCard() {
  if (m_pairingCard == nullptr) {
    return;
  }
  const bool hasPending = m_agent != nullptr && m_agent->hasPendingRequest();
  m_pairingCard->setVisible(hasPending);
  if (!hasPending) {
    return;
  }
  const auto req = m_agent->pendingRequest();
  std::string alias = req.devicePath;
  if (m_service != nullptr) {
    for (const auto& d : m_service->devices()) {
      if (d.path == req.devicePath && !d.alias.empty()) {
        alias = d.alias;
        break;
      }
    }
  }

  if (m_pairingTitle != nullptr) {
    m_pairingTitle->setText("Pair " + alias);
  }
  const bool needsInput = req.kind == BluetoothPairingKind::PinCode || req.kind == BluetoothPairingKind::Passkey;
  const bool showsCode = req.kind == BluetoothPairingKind::Confirm ||
                         req.kind == BluetoothPairingKind::DisplayPasskey ||
                         req.kind == BluetoothPairingKind::DisplayPinCode;

  if (m_pairingDetail != nullptr) {
    switch (req.kind) {
    case BluetoothPairingKind::Confirm:
      m_pairingDetail->setText("Confirm that this code matches the one shown on the device:");
      break;
    case BluetoothPairingKind::Authorize:
      m_pairingDetail->setText("Accept the incoming pairing request?");
      break;
    case BluetoothPairingKind::AuthorizeService:
      m_pairingDetail->setText("Allow access to service " + req.uuid + "?");
      break;
    case BluetoothPairingKind::DisplayPinCode:
      m_pairingDetail->setText("Enter this PIN on the device:");
      break;
    case BluetoothPairingKind::DisplayPasskey:
      m_pairingDetail->setText("Enter this code on the device:");
      break;
    case BluetoothPairingKind::PinCode:
      m_pairingDetail->setText("Enter the PIN shown on the device:");
      break;
    case BluetoothPairingKind::Passkey:
      m_pairingDetail->setText("Enter the passkey shown on the device:");
      break;
    case BluetoothPairingKind::None:
      break;
    }
  }
  if (m_pairingCode != nullptr) {
    m_pairingCode->setVisible(showsCode);
    if (showsCode) {
      if (req.kind == BluetoothPairingKind::DisplayPinCode) {
        m_pairingCode->setText(req.pin);
      } else {
        char buf[16];
        std::snprintf(buf, sizeof(buf), "%06u", req.passkey);
        m_pairingCode->setText(buf);
      }
    }
  }
  if (m_pairingInputRow != nullptr) {
    m_pairingInputRow->setVisible(needsInput);
  }
}

std::string BluetoothTab::listKey() const {
  if (m_service == nullptr) {
    return "empty";
  }
  const auto& s = m_service->state();
  std::string key;
  key += s.adapterPresent ? '1' : '0';
  key += s.powered ? '1' : '0';
  key += s.discovering ? '1' : '0';
  key.push_back('|');
  for (const auto& d : m_service->devices()) {
    key += d.path;
    key.push_back(':');
    key += d.alias;
    key.push_back(':');
    key += std::to_string(static_cast<int>(d.kind));
    key.push_back(':');
    key += d.paired ? '1' : '0';
    key += d.trusted ? '1' : '0';
    key += d.connected ? '1' : '0';
    key += d.connecting ? '1' : '0';
    key += d.hasBattery ? '1' : '0';
    key.push_back(':');
    key += std::to_string(static_cast<int>(d.batteryPercent));
    key.push_back(':');
    key += std::to_string(static_cast<int>(d.rssi));
    key.push_back('\n');
  }
  return key;
}

void BluetoothTab::rebuildDeviceList(Renderer& renderer) {
  uiAssertNotRendering("BluetoothTab::rebuildDeviceList");
  if (m_list == nullptr || m_listScroll == nullptr) {
    return;
  }
  const float listWidth = m_listScroll->contentViewportWidth();
  if (listWidth <= 0.0f) {
    return;
  }
  const std::string nextKey = listKey();
  if (listWidth == m_lastListWidth && nextKey == m_lastListKey) {
    return;
  }
  m_lastListWidth = listWidth;
  m_lastListKey = nextKey;

  while (!m_list->children().empty()) {
    m_list->removeChild(m_list->children().front().get());
  }

  if (m_service == nullptr) {
    auto empty = std::make_unique<Label>();
    empty->setText("Bluetooth service unavailable");
    empty->setCaptionStyle();
    empty->setFontSize(Style::fontSizeCaption);
    empty->setColor(roleColor(ColorRole::OnSurfaceVariant));
    m_list->addChild(std::move(empty));
    m_list->layout(renderer);
    return;
  }

  auto devices = m_service->devices();
  std::ranges::sort(devices, [](const BluetoothDeviceInfo& a, const BluetoothDeviceInfo& b) {
    const auto ba = bucketFor(a);
    const auto bb = bucketFor(b);
    if (ba != bb) {
      return static_cast<int>(ba) < static_cast<int>(bb);
    }
    if (ba == DeviceBucket::Available) {
      // Stronger signal first (RSSI is negative; closer to zero is stronger).
      if (a.hasRssi != b.hasRssi) {
        return a.hasRssi;
      }
      return a.rssi > b.rssi;
    }
    return a.alias < b.alias;
  });

  if (devices.empty()) {
    auto empty = std::make_unique<Label>();
    empty->setText(m_service->state().powered ? "No devices found. Start scanning to discover nearby Bluetooth devices."
                                              : "Bluetooth is off");
    empty->setCaptionStyle();
    empty->setFontSize(Style::fontSizeCaption);
    empty->setColor(roleColor(ColorRole::OnSurfaceVariant));
    m_list->addChild(std::move(empty));
    m_list->layout(renderer);
    return;
  }

  DeviceBucket currentBucket = DeviceBucket::Connected;
  bool first = true;
  for (const auto& device : devices) {
    const auto bucket = bucketFor(device);
    if (first || bucket != currentBucket) {
      const char* sectionText = "";
      switch (bucket) {
      case DeviceBucket::Connected:
        sectionText = "Connected";
        break;
      case DeviceBucket::Paired:
        sectionText = "Paired";
        break;
      case DeviceBucket::Available:
        sectionText = "Available";
        break;
      }
      auto header = std::make_unique<Label>();
      header->setText(sectionText);
      header->setCaptionStyle();
      header->setBold(true);
      header->setFontSize(Style::fontSizeCaption);
      header->setColor(roleColor(ColorRole::OnSurfaceVariant));
      m_list->addChild(std::move(header));
      currentBucket = bucket;
      first = false;
    }
    auto row = std::make_unique<BluetoothDeviceRow>(device, m_service, contentScale());
    m_list->addChild(std::move(row));
  }
  m_list->layout(renderer);
}
