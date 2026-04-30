#include "shell/control_center/shortcut_registry.h"

#include "compositors/keyboard_backend.h"
#include "config/config_service.h"
#include "dbus/bluetooth/bluetooth_service.h"
#include "dbus/mpris/mpris_service.h"
#include "dbus/network/network_service.h"
#include "dbus/power/power_profiles_service.h"
#include "idle/idle_inhibitor.h"
#include "notification/notification_manager.h"
#include "pipewire/pipewire_service.h"
#include "shell/bar/widgets/keyboard_layout_widget.h"
#include "shell/control_center/shortcut_services.h"
#include "shell/panel/panel_manager.h"
#include "system/night_light_manager.h"
#include "system/weather_service.h"
#include "theme/theme_service.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cmath>
#include <format>
#include <vector>

namespace {

  void openTab(std::string_view tab) {
    PanelManager::instance().togglePanel("control-center", nullptr, 0.0f, 0.0f, tab);
  }

  // ── Toggle shortcuts ────────────────────────────────────────────────────────

  class WifiShortcut final : public Shortcut {
  public:
    explicit WifiShortcut(NetworkService* svc) : m_svc(svc) {}
    std::string_view id() const override { return "wifi"; }
    std::string_view defaultLabel() const override { return "Wi-Fi"; }
    std::string displayLabel() const override {
      if (m_svc != nullptr) {
        const NetworkState& state = m_svc->state();
        if (state.kind == NetworkConnectivity::Wireless && state.connected && !state.ssid.empty()) {
          return state.ssid;
        }
      }
      return std::string(defaultLabel());
    }
    std::string_view iconOn() const override { return "wifi"; }
    std::string_view iconOff() const override { return "wifi-off"; }
    bool isToggle() const override { return true; }
    bool active() const override { return m_svc != nullptr && m_svc->state().wirelessEnabled; }
    void onClick() override {
      if (m_svc != nullptr) {
        m_svc->setWirelessEnabled(!m_svc->state().wirelessEnabled);
      }
    }
    void onRightClick() override { openTab("network"); }

  private:
    NetworkService* m_svc;
  };

  class BluetoothShortcut final : public Shortcut {
  public:
    explicit BluetoothShortcut(BluetoothService* svc) : m_svc(svc) {}
    std::string_view id() const override { return "bluetooth"; }
    std::string_view defaultLabel() const override { return "Bluetooth"; }
    std::string_view iconOn() const override { return "bluetooth"; }
    std::string_view iconOff() const override { return "bluetooth-off"; }
    bool isToggle() const override { return true; }
    bool active() const override { return m_svc != nullptr && m_svc->state().powered; }
    void onClick() override {
      if (m_svc != nullptr) {
        m_svc->setPowered(!m_svc->state().powered);
      }
    }
    void onRightClick() override { openTab("bluetooth"); }

  private:
    BluetoothService* m_svc;
  };

  class NightlightShortcut final : public Shortcut {
  public:
    explicit NightlightShortcut(NightLightManager* svc) : m_svc(svc) {}
    std::string_view id() const override { return "nightlight"; }
    std::string_view defaultLabel() const override { return "Night Light"; }
    std::string_view iconOn() const override {
      return m_svc != nullptr && m_svc->forceEnabled() ? "nightlight-forced" : "nightlight-on";
    }
    std::string_view iconOff() const override { return "nightlight-off"; }
    bool isToggle() const override { return true; }
    bool active() const override { return m_svc != nullptr && (m_svc->forceEnabled() || m_svc->active()); }
    void onClick() override {
      if (m_svc != nullptr) {
        if (m_svc->forceEnabled()) {
          m_svc->setEnabled(false);
          m_svc->setForceEnabled(false);
        } else {
          m_svc->toggleEnabled();
        }
      }
    }

  private:
    NightLightManager* m_svc;
  };

  class NotificationShortcut final : public Shortcut {
  public:
    explicit NotificationShortcut(NotificationManager* svc) : m_svc(svc) {}
    std::string_view id() const override { return "notification"; }
    std::string_view defaultLabel() const override { return "DND"; }
    std::string_view iconOn() const override { return "bell-off"; }
    std::string_view iconOff() const override { return "bell"; }
    bool isToggle() const override { return true; }
    bool active() const override { return m_svc != nullptr && m_svc->doNotDisturb(); }
    void onClick() override {
      if (m_svc != nullptr) {
        (void)m_svc->toggleDoNotDisturb();
      }
    }
    void onRightClick() override { openTab("notifications"); }

  private:
    NotificationManager* m_svc;
  };

  class DarkModeShortcut final : public Shortcut {
  public:
    explicit DarkModeShortcut(noctalia::theme::ThemeService* svc) : m_svc(svc) {}
    std::string_view id() const override { return "dark_mode"; }
    std::string_view defaultLabel() const override { return "Dark Mode"; }
    std::string displayLabel() const override {
      if (m_svc == nullptr) {
        return std::string(defaultLabel());
      }
      switch (m_svc->configuredMode()) {
      case ThemeMode::Dark:
        return "Dark Mode";
      case ThemeMode::Light:
        return "Light Mode";
      case ThemeMode::Auto:
        return "Auto Mode";
      }
      return std::string(defaultLabel());
    }
    std::string_view iconOn() const override {
      return m_svc != nullptr && m_svc->configuredMode() == ThemeMode::Auto ? "theme-mode" : "weather-moon-stars";
    }
    std::string_view iconOff() const override { return "weather-sun"; }
    bool isToggle() const override { return true; }
    bool active() const override { return m_svc != nullptr && m_svc->configuredMode() != ThemeMode::Light; }
    void onClick() override {
      if (m_svc != nullptr) {
        m_svc->cycleMode();
      }
    }

  private:
    noctalia::theme::ThemeService* m_svc;
  };

  class IdleInhibitorShortcut final : public Shortcut {
  public:
    explicit IdleInhibitorShortcut(IdleInhibitor* svc) : m_svc(svc) {}
    std::string_view id() const override { return "idle_inhibitor"; }
    std::string_view defaultLabel() const override { return "Idle Inhibitor"; }
    std::string_view iconOn() const override { return "idle-inhibitor-on"; }
    std::string_view iconOff() const override { return "idle-inhibitor-off"; }
    bool isToggle() const override { return true; }
    bool active() const override { return m_svc != nullptr && m_svc->enabled(); }
    void onClick() override {
      if (m_svc != nullptr) {
        m_svc->toggle();
      }
    }

  private:
    IdleInhibitor* m_svc;
  };

  class AudioShortcut final : public Shortcut {
  public:
    explicit AudioShortcut(PipeWireService* svc) : m_svc(svc) {}
    std::string_view id() const override { return "audio"; }
    std::string_view defaultLabel() const override { return "Audio"; }
    std::string_view iconOn() const override { return "volume-x"; }
    std::string_view iconOff() const override { return "volume-high"; }
    bool isToggle() const override { return true; }
    bool active() const override {
      if (m_svc == nullptr) {
        return false;
      }
      const AudioNode* sink = m_svc->defaultSink();
      return sink != nullptr && sink->muted;
    }
    void onClick() override {
      if (m_svc != nullptr) {
        if (const AudioNode* sink = m_svc->defaultSink(); sink != nullptr) {
          m_svc->setMuted(!sink->muted);
        }
      }
    }
    void onRightClick() override { openTab("audio"); }

  private:
    PipeWireService* m_svc;
  };

  class MicMuteShortcut final : public Shortcut {
  public:
    explicit MicMuteShortcut(PipeWireService* svc) : m_svc(svc) {}
    std::string_view id() const override { return "mic_mute"; }
    std::string_view defaultLabel() const override { return "Microphone"; }
    std::string_view iconOn() const override { return "microphone-mute"; }
    std::string_view iconOff() const override { return "microphone"; }
    bool isToggle() const override { return true; }
    bool active() const override {
      if (m_svc == nullptr) {
        return false;
      }
      const AudioNode* source = m_svc->defaultSource();
      return source != nullptr && source->muted;
    }
    void onClick() override {
      if (m_svc != nullptr) {
        if (const AudioNode* source = m_svc->defaultSource(); source != nullptr) {
          m_svc->setMicMuted(!source->muted);
        }
      }
    }
    void onRightClick() override { openTab("audio"); }

  private:
    PipeWireService* m_svc;
  };

  const char* powerProfileIcon(std::string_view profile) {
    if (profile == "performance") {
      return "performance";
    }
    if (profile == "power-saver") {
      return "powersaver";
    }
    return "balanced";
  }

  const WidgetConfig* findKeyboardLayoutWidgetConfig(const Config& config) {
    auto resolve = [&config](const std::string& name) -> const WidgetConfig* {
      const auto it = config.widgets.find(name);
      if (it == config.widgets.end() || it->second.type != "keyboard_layout") {
        return nullptr;
      }
      return &it->second;
    };

    auto search = [&resolve](const std::vector<std::string>& widgets) -> const WidgetConfig* {
      for (const std::string& name : widgets) {
        if (const WidgetConfig* wc = resolve(name); wc != nullptr) {
          return wc;
        }
      }
      return nullptr;
    };

    for (const BarConfig& bar : config.bars) {
      if (const WidgetConfig* wc = search(bar.startWidgets); wc != nullptr) {
        return wc;
      }
      if (const WidgetConfig* wc = search(bar.centerWidgets); wc != nullptr) {
        return wc;
      }
      if (const WidgetConfig* wc = search(bar.endWidgets); wc != nullptr) {
        return wc;
      }
    }

    return resolve("keyboard_layout");
  }

  KeyboardLayoutWidget::DisplayMode keyboardLayoutDisplayMode(const ConfigService* config) {
    if (config == nullptr) {
      return KeyboardLayoutWidget::DisplayMode::Short;
    }
    const WidgetConfig* wc = findKeyboardLayoutWidgetConfig(config->config());
    const std::string display = wc != nullptr ? wc->getString("display", "short") : std::string("short");
    return KeyboardLayoutWidget::parseDisplayMode(display);
  }

  class PowerProfileShortcut final : public Shortcut {
  public:
    explicit PowerProfileShortcut(PowerProfilesService* svc) : m_svc(svc) {}
    std::string_view id() const override { return "power_profile"; }
    std::string_view defaultLabel() const override { return "Power"; }
    std::string displayLabel() const override {
      if (m_svc != nullptr && !m_svc->activeProfile().empty()) {
        return profileLabel(m_svc->activeProfile());
      }
      return std::string(defaultLabel());
    }
    std::string_view iconOn() const override {
      return powerProfileIcon(m_svc != nullptr ? m_svc->activeProfile() : "");
    }
    std::string_view iconOff() const override { return "balanced"; }
    bool isToggle() const override { return true; }
    bool active() const override {
      return m_svc != nullptr && !m_svc->activeProfile().empty() && m_svc->activeProfile() != "balanced";
    }
    void onClick() override {
      if (m_svc == nullptr) {
        return;
      }
      const auto& profiles = m_svc->profiles();
      if (profiles.empty()) {
        return;
      }
      const auto& current = m_svc->activeProfile();
      auto it = std::find(profiles.begin(), profiles.end(), current);
      std::size_t nextIdx = 0;
      if (it != profiles.end()) {
        nextIdx = (static_cast<std::size_t>(std::distance(profiles.begin(), it)) + 1) % profiles.size();
      }
      (void)m_svc->setActiveProfile(profiles[nextIdx]);
    }
    void onRightClick() override { openTab("system"); }

  private:
    PowerProfilesService* m_svc;
  };

  class WeatherShortcut final : public Shortcut {
  public:
    explicit WeatherShortcut(WeatherService* svc) : m_svc(svc) {}
    std::string_view id() const override { return "weather"; }
    std::string_view defaultLabel() const override { return "Weather"; }
    std::string displayLabel() const override {
      if (m_svc != nullptr && m_svc->enabled() && m_svc->hasData()) {
        const auto& snapshot = m_svc->snapshot();
        const int temp = static_cast<int>(std::lround(m_svc->displayTemperature(snapshot.current.temperatureC)));
        return std::format("{}{}", temp, m_svc->displayTemperatureUnit());
      }
      return std::string(defaultLabel());
    }
    std::string displayIcon() const override {
      if (m_svc == nullptr || !m_svc->enabled()) {
        return "weather-cloud-off";
      }
      if (m_svc->hasData()) {
        const auto& snapshot = m_svc->snapshot();
        return WeatherService::glyphForCode(snapshot.current.weatherCode, snapshot.current.isDay);
      }
      return "weather-cloud";
    }
    std::string_view iconOn() const override { return "weather-cloud-sun"; }
    std::string_view iconOff() const override { return "weather-cloud-sun"; }
    void onClick() override { openTab("weather"); }
    void onRightClick() override { openTab("weather"); }

  private:
    WeatherService* m_svc;
  };

  class KeyboardLayoutShortcut final : public Shortcut {
  public:
    KeyboardLayoutShortcut(WaylandConnection* wayland, ConfigService* config) : m_wayland(wayland), m_config(config) {}
    std::string_view id() const override { return "keyboard_layout"; }
    std::string_view defaultLabel() const override { return "Layout"; }
    std::string displayLabel() const override {
      return KeyboardLayoutWidget::formatLayoutLabel(resolvedLayoutName(), keyboardLayoutDisplayMode(m_config));
    }
    std::string_view iconOn() const override { return "keyboard"; }
    std::string_view iconOff() const override { return "keyboard"; }
    void onClick() override {
      (void)m_backend.cycleLayout();
      PanelManager::instance().refresh();
    }

  private:
    [[nodiscard]] std::string resolvedLayoutName() const {
      const auto state = m_backend.layoutState();
      if (state.has_value() && state->currentIndex >= 0 &&
          state->currentIndex < static_cast<int>(state->names.size())) {
        return state->names[static_cast<std::size_t>(state->currentIndex)];
      }

      if (auto backendName = m_backend.currentLayoutName(); backendName.has_value() && !backendName->empty()) {
        return *backendName;
      }

      return m_wayland != nullptr ? m_wayland->currentKeyboardLayoutName() : std::string{};
    }

    KeyboardBackend m_backend;
    WaylandConnection* m_wayland = nullptr;
    ConfigService* m_config = nullptr;
  };

  // ── Action-only shortcuts ────��──────────────────────────────────────────────

  class MediaShortcut final : public Shortcut {
  public:
    explicit MediaShortcut(MprisService* svc) : m_svc(svc) {}
    std::string_view id() const override { return "media"; }
    std::string_view defaultLabel() const override { return "Media"; }
    std::string_view iconOn() const override { return "media-pause"; }
    std::string_view iconOff() const override { return "media-play"; }
    bool isToggle() const override { return true; }
    bool active() const override {
      if (m_svc == nullptr) {
        return false;
      }
      const auto active = m_svc->activePlayer();
      return active.has_value() && active->playbackStatus == "Playing";
    }
    void onClick() override {
      if (m_svc != nullptr) {
        (void)m_svc->playPauseActive();
      }
    }
    void onRightClick() override { openTab("media"); }

  private:
    MprisService* m_svc;
  };

  class SysmonShortcut final : public Shortcut {
  public:
    std::string_view id() const override { return "sysmon"; }
    std::string_view defaultLabel() const override { return "System"; }
    std::string_view iconOn() const override { return "activity"; }
    std::string_view iconOff() const override { return "activity"; }
    void onClick() override { openTab("system"); }
    void onRightClick() override { openTab("system"); }
  };

  class WallpaperShortcut final : public Shortcut {
  public:
    std::string_view id() const override { return "wallpaper"; }
    std::string_view defaultLabel() const override { return "Wallpaper"; }
    std::string_view iconOn() const override { return "wallpaper-selector"; }
    std::string_view iconOff() const override { return "wallpaper-selector"; }
    void onClick() override { PanelManager::instance().togglePanel("wallpaper"); }
  };

  class SessionShortcut final : public Shortcut {
  public:
    std::string_view id() const override { return "session"; }
    std::string_view defaultLabel() const override { return "Session"; }
    std::string_view iconOn() const override { return "shutdown"; }
    std::string_view iconOff() const override { return "shutdown"; }
    void onClick() override { PanelManager::instance().togglePanel("session"); }
  };

  class ClipboardShortcut final : public Shortcut {
  public:
    std::string_view id() const override { return "clipboard"; }
    std::string_view defaultLabel() const override { return "Clipboard"; }
    std::string_view iconOn() const override { return "clipboard"; }
    std::string_view iconOff() const override { return "clipboard"; }
    void onClick() override { PanelManager::instance().togglePanel("clipboard"); }
  };

} // namespace

std::unique_ptr<Shortcut> ShortcutRegistry::create(std::string_view type, const ShortcutServices& s) {
  if (type == "wifi")
    return std::make_unique<WifiShortcut>(s.network);
  if (type == "bluetooth")
    return std::make_unique<BluetoothShortcut>(s.bluetooth);
  if (type == "nightlight")
    return std::make_unique<NightlightShortcut>(s.nightLight);
  if (type == "notification")
    return std::make_unique<NotificationShortcut>(s.notifications);
  if (type == "dark_mode")
    return std::make_unique<DarkModeShortcut>(s.theme);
  if (type == "idle_inhibitor")
    return std::make_unique<IdleInhibitorShortcut>(s.idleInhibitor);
  if (type == "audio")
    return std::make_unique<AudioShortcut>(s.audio);
  if (type == "mic_mute")
    return std::make_unique<MicMuteShortcut>(s.audio);
  if (type == "power_profile")
    return std::make_unique<PowerProfileShortcut>(s.powerProfiles);
  if (type == "media")
    return std::make_unique<MediaShortcut>(s.mpris);
  if (type == "weather")
    return std::make_unique<WeatherShortcut>(s.weather);
  if (type == "sysmon")
    return std::make_unique<SysmonShortcut>();
  if (type == "keyboard_layout")
    return std::make_unique<KeyboardLayoutShortcut>(s.wayland, s.config);
  if (type == "wallpaper")
    return std::make_unique<WallpaperShortcut>();
  if (type == "session")
    return std::make_unique<SessionShortcut>();
  if (type == "clipboard")
    return std::make_unique<ClipboardShortcut>();
  return nullptr;
}
