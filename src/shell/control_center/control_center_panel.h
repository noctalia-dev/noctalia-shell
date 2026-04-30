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
class IdleInhibitor;
class InputArea;
class Label;
class MprisService;
class NetworkSecretAgent;
class NetworkService;
class NightLightManager;
class NotificationManager;
class PipeWireService;
class PipeWireSpectrum;
class PowerProfilesService;
class SystemMonitorService;
class UPowerService;
class Wallpaper;
class WeatherService;
class WaylandConnection;

namespace noctalia::theme {
  class ThemeService;
}

class ControlCenterPanel : public Panel {
public:
  ControlCenterPanel(NotificationManager* notifications, PipeWireService* audio, MprisService* mpris,
                     ConfigService* config = nullptr, HttpClient* httpClient = nullptr,
                     WeatherService* weather = nullptr, PipeWireSpectrum* spectrum = nullptr,
                     UPowerService* upower = nullptr, PowerProfilesService* powerProfiles = nullptr,
                     NetworkService* network = nullptr, NetworkSecretAgent* networkSecrets = nullptr,
                     BluetoothService* bluetooth = nullptr, BluetoothAgent* bluetoothAgent = nullptr,
                     BrightnessService* brightness = nullptr, SystemMonitorService* sysmon = nullptr,
                     NightLightManager* nightLight = nullptr, noctalia::theme::ThemeService* theme = nullptr,
                     IdleInhibitor* idleInhibitor = nullptr, WaylandConnection* wayland = nullptr,
                     Wallpaper* wallpaper = nullptr);

  void create() override;
  void onFrameTick(float deltaMs) override;
  void onOpen(std::string_view context) override;
  void onClose() override;
  [[nodiscard]] bool dismissTransientUi();
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
  // Inner content area, sized for the tallest tab. Outer chrome adds panelPadding on each side.
  static constexpr float kPreferredPanelContentHeight = 540.0f;
  static constexpr float kPreferredPanelHeight = kPreferredPanelContentHeight + 2.0f * Style::panelPadding;

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
    const char* titleKey;
    const char* glyph;
  };

  static constexpr std::size_t kTabCount = static_cast<std::size_t>(TabId::Count);
  static constexpr std::array<TabMeta, kTabCount> kTabs{{
      {TabId::Overview, "overview", "control-center.tabs.overview", "person"},
      {TabId::Media, "media", "control-center.tabs.media", "disc"},
      {TabId::Audio, "audio", "control-center.tabs.audio", "device-speaker"},
      {TabId::Display, "display", "control-center.tabs.display", "device-desktop"},
      {TabId::System, "system", "control-center.tabs.system", "activity"},
      {TabId::Network, "network", "control-center.tabs.network", "wifi"},
      {TabId::Bluetooth, "bluetooth", "control-center.tabs.bluetooth", "bluetooth"},
      {TabId::Weather, "weather", "control-center.tabs.weather", "weather-cloud-sun"},
      {TabId::Calendar, "calendar", "control-center.tabs.calendar", "calendar"},
      {TabId::Notifications, "notifications", "control-center.tabs.notifications", "bell"},
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
  InputArea* m_contentDismissArea = nullptr;
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
