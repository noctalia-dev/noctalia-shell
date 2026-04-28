#pragma once

#include "shell/control_center/audio_tab.h"
#include "shell/control_center/bluetooth_tab.h"
#include "shell/control_center/calendar_tab.h"
#include "shell/control_center/display_tab.h"
#include "shell/control_center/media_tab.h"
#include "shell/control_center/network_tab.h"
#include "shell/control_center/notifications_tab.h"
#include "shell/control_center/overview_tab.h"
#include "shell/control_center/system_tab.h"
#include "shell/control_center/tab.h"
#include "shell/control_center/weather_tab.h"
#include "shell/panel/panel.h"

#include <array>
#include <cstdint>
#include <memory>
#include <string_view>

class BluetoothAgent;
class BluetoothService;
class BrightnessService;
class Button;
class ConfigService;
class Flex;
class HttpClient;
class Label;
class MprisService;
class NetworkSecretAgent;
class NetworkService;
class NotificationManager;
class PipeWireService;
class PipeWireSpectrum;
class PowerProfilesService;
class SystemMonitorService;
class UPowerService;
class WeatherService;

class ControlCenterPanel : public Panel {
public:
  ControlCenterPanel(NotificationManager* notifications, PipeWireService* audio, MprisService* mpris,
                     ConfigService* config = nullptr, HttpClient* httpClient = nullptr,
                     WeatherService* weather = nullptr, PipeWireSpectrum* spectrum = nullptr,
                     UPowerService* upower = nullptr, PowerProfilesService* powerProfiles = nullptr,
                     NetworkService* network = nullptr, NetworkSecretAgent* networkSecrets = nullptr,
                     BluetoothService* bluetooth = nullptr, BluetoothAgent* bluetoothAgent = nullptr,
                     BrightnessService* brightness = nullptr, SystemMonitorService* sysmon = nullptr);

  void create() override;
  void onFrameTick(float deltaMs) override;
  void onOpen(std::string_view context) override;
  void onClose() override;
  [[nodiscard]] bool isContextActive(std::string_view context) const override;
  [[nodiscard]] bool deferExternalRefresh() const override;
  [[nodiscard]] bool deferPointerRelayout() const override;

  [[nodiscard]] float preferredWidth() const override { return scaled(kPreferredPanelWidth); }
  [[nodiscard]] float preferredHeight() const override { return scaled(kPreferredPanelHeight); }
  [[nodiscard]] bool centeredHorizontally() const override { return true; }
  [[nodiscard]] bool centeredVertically() const override { return true; }
  [[nodiscard]] bool prefersAttachedToBar() const noexcept override { return true; }

private:
  void doLayout(Renderer& renderer, float width, float height) override;
  void doUpdate(Renderer& renderer) override;
  static constexpr float kPreferredPanelWidth = 932.0f;
  static constexpr float kPreferredPanelHeight = Style::controlHeightLg * 15 + Style::spaceLg + Style::spaceSm;

  enum class TabId : std::uint8_t {
    Overview,
    Media,
    Audio,
    Display,
    System,
    Network,
    Bluetooth,
    Weather,
    Calendar,
    Notifications,
    Count,
  };

  struct TabMeta {
    TabId id;
    const char* key;
    const char* title;
    const char* glyph;
  };

  static constexpr std::size_t kTabCount = static_cast<std::size_t>(TabId::Count);
  static constexpr std::array<TabMeta, kTabCount> kTabs{{
      {TabId::Overview, "overview", "Overview", "person"},
      {TabId::Media, "media", "Media", "disc"},
      {TabId::Audio, "audio", "Audio", "device-speaker"},
      {TabId::Display, "display", "Display", "device-desktop"},
      {TabId::System, "system", "System", "activity"},
      {TabId::Network, "network", "Network", "wifi"},
      {TabId::Bluetooth, "bluetooth", "Bluetooth", "bluetooth"},
      {TabId::Weather, "weather", "Weather", "weather-cloud-sun"},
      {TabId::Calendar, "calendar", "Calendar", "calendar"},
      {TabId::Notifications, "notifications", "Notifications", "bell"},
  }};

  void selectTab(TabId tab);
  [[nodiscard]] static TabId tabFromContext(std::string_view context);
  [[nodiscard]] static std::size_t tabIndex(TabId id);

  // Tab instances (long-lived, survive panel open/close cycles)
  std::array<std::unique_ptr<Tab>, kTabCount> m_tabs;

  // Panel UI structure (rebuilt each create(), nulled in onClose())
  Flex* m_rootLayout = nullptr;
  Flex* m_sidebar = nullptr;
  Flex* m_content = nullptr;
  Flex* m_contentHeader = nullptr;
  Flex* m_contentHeaderActions = nullptr;
  Label* m_contentTitle = nullptr;
  Button* m_closeButton = nullptr;
  Flex* m_tabBodies = nullptr;
  std::array<Button*, kTabCount> m_tabButtons{};
  std::array<Flex*, kTabCount> m_tabContainers{};
  std::array<Flex*, kTabCount> m_tabHeaderActions{};
  TabId m_activeTab = TabId::Overview;
};
