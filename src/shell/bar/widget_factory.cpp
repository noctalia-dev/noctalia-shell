#include "shell/bar/widget_factory.h"

#include "config/config_service.h"
#include "core/log.h"
#include "dbus/mpris/mpris_service.h"
#include "dbus/power/power_profiles_service.h"
#include "dbus/tray/tray_service.h"
#include "idle/idle_inhibitor.h"
#include "net/http_client.h"
#include "notification/notification_manager.h"
#include "pipewire/pipewire_spectrum.h"
#include "shell/bar/widgets/active_window_widget.h"
#include "shell/bar/widgets/audio_visualizer_widget.h"
#include "shell/bar/widgets/battery_widget.h"
#include "shell/bar/widgets/bluetooth_widget.h"
#include "shell/bar/widgets/brightness_widget.h"
#include "shell/bar/widgets/clipboard_widget.h"
#include "shell/bar/widgets/clock_widget.h"
#include "shell/bar/widgets/control_center_widget.h"
#include "shell/bar/widgets/idle_inhibitor_widget.h"
#include "shell/bar/widgets/keyboard_layout_widget.h"
#include "shell/bar/widgets/launcher_widget.h"
#include "shell/bar/widgets/lock_keys_widget.h"
#include "shell/bar/widgets/media_widget.h"
#include "shell/bar/widgets/network_widget.h"
#include "shell/bar/widgets/nightlight_widget.h"
#include "shell/bar/widgets/notification_widget.h"
#include "shell/bar/widgets/power_profiles_widget.h"
#include "shell/bar/widgets/scripted_widget.h"
#include "shell/bar/widgets/session_widget.h"
#include "shell/bar/widgets/settings_widget.h"
#include "shell/bar/widgets/spacer_widget.h"
#include "shell/bar/widgets/sysmon_widget.h"
#include "shell/bar/widgets/taskbar_widget.h"
#include "shell/bar/widgets/test_widget.h"
#include "shell/bar/widgets/theme_mode_widget.h"
#include "shell/bar/widgets/tray_widget.h"
#include "shell/bar/widgets/volume_widget.h"
#include "shell/bar/widgets/wallpaper_widget.h"
#include "shell/bar/widgets/weather_widget.h"
#include "shell/bar/widgets/workspaces_widget.h"
#include "system/lock_keys_service.h"
#include "system/system_monitor_service.h"
#include "system/weather_service.h"
#include "theme/theme_service.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cstdint>
#include <functional>
#include <string>

namespace {
  constexpr Logger kLog("shell");

  ActiveWindowTitleScrollMode parseActiveWindowTitleScrollMode(std::string_view value) {
    if (value == "always") {
      return ActiveWindowTitleScrollMode::Always;
    }
    if (value == "on_hover" || value == "hover") {
      return ActiveWindowTitleScrollMode::OnHover;
    }
    return ActiveWindowTitleScrollMode::None;
  }

  MediaTitleScrollMode parseMediaTitleScrollMode(std::string_view value) {
    if (value == "always") {
      return MediaTitleScrollMode::Always;
    }
    if (value == "on_hover" || value == "hover") {
      return MediaTitleScrollMode::OnHover;
    }
    return MediaTitleScrollMode::None;
  }
} // namespace

WidgetFactory::WidgetFactory(WaylandConnection& wayland, const Config& config, NotificationManager* notifications,
                             TrayService* tray, PipeWireService* audio, UPowerService* upower,
                             SystemMonitorService* sysmon, PowerProfilesService* powerProfiles, NetworkService* network,
                             IdleInhibitor* idleInhibitor, MprisService* mpris, PipeWireSpectrum* audioSpectrum,
                             HttpClient* httpClient, WeatherService* weather, NightLightManager* nightLight,
                             noctalia::theme::ThemeService* themeService, BluetoothService* bluetooth,
                             BrightnessService* brightness, LockKeysService* lockKeys, FileWatcher* fileWatcher)
    : m_wayland(wayland), m_config(config), m_notifications(notifications), m_tray(tray), m_audio(audio),
      m_upower(upower), m_sysmon(sysmon), m_powerProfiles(powerProfiles), m_network(network),
      m_idleInhibitor(idleInhibitor), m_mpris(mpris), m_audioSpectrum(audioSpectrum), m_httpClient(httpClient),
      m_weather(weather), m_nightLight(nightLight), m_themeService(themeService), m_bluetooth(bluetooth),
      m_brightness(brightness), m_lockKeys(lockKeys), m_fileWatcher(fileWatcher) {}

WidgetFactory::~WidgetFactory() = default;

std::unique_ptr<Widget> WidgetFactory::create(const std::string& name, wl_output* output, float contentScale,
                                              const std::string& barPosition) const {
  // Resolve: if name matches a [widget.<name>] entry, use its type + settings.
  // Otherwise treat the name itself as the widget type with default settings.
  const WidgetConfig* wc = nullptr;
  std::string type = name;

  auto it = m_config.widgets.find(name);
  if (it != m_config.widgets.end()) {
    wc = &it->second;
    type = it->second.type;
  }

  if (type == "active_window") {
    const float maxWidth = static_cast<float>(wc != nullptr ? wc->getDouble("max_length", 260.0) : 260.0);
    const float minWidth = static_cast<float>(wc != nullptr ? wc->getDouble("min_length", 80.0) : 80.0);
    const float iconSize =
        static_cast<float>(wc != nullptr ? wc->getDouble("icon_size", Style::fontSizeBody) : Style::fontSizeBody);
    const std::string titleScroll = wc != nullptr ? wc->getString("title_scroll", "none") : std::string("none");
    auto widget = std::make_unique<ActiveWindowWidget>(m_wayland, maxWidth, minWidth, iconSize,
                                                       parseActiveWindowTitleScrollMode(titleScroll));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "audio_visualizer") {
    const float width = static_cast<float>(wc != nullptr ? wc->getDouble("width", 56.0) : 56.0);
    const int bands = static_cast<int>(wc != nullptr ? wc->getInt("bands", 16) : 16);
    const bool mirrored = wc != nullptr ? wc->getBool("mirrored", true) : true;
    const bool showWhenIdle = wc != nullptr ? wc->getBool("show_when_idle", false) : false;
    const ColorSpec lowColor =
        colorSpecFromConfigString(wc != nullptr ? wc->getString("low_color", "primary") : std::string("primary"));
    const ColorSpec highColor =
        colorSpecFromConfigString(wc != nullptr ? wc->getString("high_color", "primary") : std::string("primary"));
    auto widget = std::make_unique<AudioVisualizerWidget>(m_audioSpectrum, width, bands, mirrored, lowColor, highColor,
                                                          showWhenIdle);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "battery") {
    auto widget = std::make_unique<BatteryWidget>(m_upower);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "bluetooth") {
    const bool showLabel = wc != nullptr ? wc->getBool("show_label", false) : false;
    auto widget = std::make_unique<BluetoothWidget>(m_bluetooth, output, showLabel);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "brightness") {
    const bool showLabel = wc != nullptr ? wc->getBool("show_label", true) : true;
    auto widget = std::make_unique<BrightnessWidget>(m_brightness, output, showLabel);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "clock") {
    std::string format = wc != nullptr ? wc->getString("format", "{:%H:%M}") : std::string("{:%H:%M}");
    std::string verticalFormat = wc != nullptr ? wc->getString("vertical_format", "") : std::string{};
    auto widget = std::make_unique<ClockWidget>(output, std::move(format), std::move(verticalFormat));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "clipboard") {
    auto barGlyph = wc != nullptr ? wc->getString("glyph", "clipboard") : std::string{"clipboard"};
    if (barGlyph.empty()) {
      barGlyph = "clipboard";
    }
    auto widget = std::make_unique<ClipboardWidget>(output, std::move(barGlyph));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "control-center") {
    auto barGlyph = wc != nullptr ? wc->getString("glyph", "noctalia") : std::string{"noctalia"};
    if (barGlyph.empty()) {
      barGlyph = "search";
    }

    std::string logoPath = wc != nullptr ? wc->getString("custom_image", "") : std::string{};

    auto widget = std::make_unique<ControlCenterWidget>(output, std::move(barGlyph), std::move(logoPath));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "caffeine") {
    auto widget = std::make_unique<IdleInhibitorWidget>(m_idleInhibitor);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "keyboard_layout") {
    const std::string cycleCommand = wc != nullptr ? wc->getString("cycle_command", "") : std::string{};
    const std::string display = wc != nullptr ? wc->getString("display", "short") : std::string("short");
    auto widget = std::make_unique<KeyboardLayoutWidget>(m_wayland, cycleCommand,
                                                         KeyboardLayoutWidget::parseDisplayMode(display));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "launcher") {
    auto barGlyph = wc != nullptr ? wc->getString("glyph", "search") : std::string{"search"};
    if (barGlyph.empty()) {
      barGlyph = "search";
    }

    std::string logoPath = wc != nullptr ? wc->getString("custom_image", "") : std::string{};

    auto widget = std::make_unique<LauncherWidget>(output, std::move(barGlyph), std::move(logoPath));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "lock_keys") {
    if (m_lockKeys == nullptr) {
      return nullptr;
    }
    const bool showCaps = wc != nullptr ? wc->getBool("show_caps_lock", true) : true;
    const bool showNum = wc != nullptr ? wc->getBool("show_num_lock", true) : true;
    const bool showScroll = wc != nullptr ? wc->getBool("show_scroll_lock", false) : false;
    const bool hideWhenOff = wc != nullptr ? wc->getBool("hide_when_off", false) : false;
    const std::string display = wc != nullptr ? wc->getString("display", "short") : std::string("short");

    auto widget = std::make_unique<LockKeysWidget>(m_lockKeys, showCaps, showNum, showScroll, hideWhenOff,
                                                   LockKeysWidget::parseDisplayMode(display));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "media") {
    const float maxWidth = static_cast<float>(wc != nullptr ? wc->getDouble("max_length", 220.0) : 220.0);
    const float minWidth = static_cast<float>(wc != nullptr ? wc->getDouble("min_length", 80.0) : 80.0);
    const float artSize = static_cast<float>(wc != nullptr ? wc->getDouble("art_size", 16.0) : 16.0);
    const std::string titleScroll = wc != nullptr ? wc->getString("title_scroll", "none") : std::string("none");
    auto widget = std::make_unique<MediaWidget>(m_mpris, m_httpClient, output, maxWidth, minWidth, artSize,
                                                parseMediaTitleScrollMode(titleScroll));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "network") {
    const bool showLabel = wc != nullptr ? wc->getBool("show_label", true) : true;
    auto widget = std::make_unique<NetworkWidget>(m_network, output, showLabel);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "nightlight") {
    auto widget = std::make_unique<NightLightWidget>(m_nightLight);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "notifications") {
    const bool hideWhenNoUnread = wc != nullptr ? wc->getBool("hide_when_no_unread", false) : false;
    auto widget = std::make_unique<NotificationWidget>(m_notifications, output, hideWhenNoUnread);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "power_profiles") {
    auto widget = std::make_unique<PowerProfilesWidget>(m_powerProfiles);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "scripted") {
    std::string script = wc != nullptr ? wc->getString("script", "") : std::string();
    auto widget = std::make_unique<ScriptedWidget>(std::move(script), wc, m_fileWatcher);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "session") {
    auto barGlyph = wc != nullptr ? wc->getString("glyph", "shutdown") : std::string{"shutdown"};
    if (barGlyph.empty()) {
      barGlyph = "shutdown";
    }
    auto widget = std::make_unique<SessionWidget>(output, std::move(barGlyph));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "settings") {
    auto barGlyph = wc != nullptr ? wc->getString("glyph", "settings") : std::string{"settings"};
    if (barGlyph.empty()) {
      barGlyph = "search";
    }
    auto widget = std::make_unique<SettingsWidget>(output, std::move(barGlyph));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "spacer") {
    const auto length = static_cast<float>(wc != nullptr ? wc->getDouble("length", 8.0) : 8.0);
    auto widget = std::make_unique<SpacerWidget>(length);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "sysmon") {
    std::string statStr = wc != nullptr ? wc->getString("stat", "cpu_usage") : std::string("cpu_usage");
    std::string path = wc != nullptr ? wc->getString("path", "/") : std::string("/");
    SysmonStat stat = SysmonStat::CpuUsage;
    if (statStr == "cpu_temp") {
      stat = SysmonStat::CpuTemp;
    } else if (statStr == "ram_used") {
      stat = SysmonStat::RamUsed;
    } else if (statStr == "ram_pct") {
      stat = SysmonStat::RamPct;
    } else if (statStr == "swap_pct") {
      stat = SysmonStat::SwapPct;
    } else if (statStr == "disk_pct") {
      stat = SysmonStat::DiskPct;
    }
    const std::string display = wc != nullptr ? wc->getString("display", "gauge") : std::string("gauge");
    SysmonDisplayMode displayMode = SysmonDisplayMode::Gauge;
    if (display == "text")
      displayMode = SysmonDisplayMode::Text;
    else if (display == "graph")
      displayMode = SysmonDisplayMode::Graph;
    const bool showLabel = wc != nullptr ? wc->getBool("show_label", true) : true;
    auto widget = std::make_unique<SysmonWidget>(m_sysmon, output, stat, std::move(path), displayMode, showLabel);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "test") {
    auto widget = std::make_unique<TestWidget>(output);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "taskbar") {
    const bool groupByWorkspace = wc != nullptr ? wc->getBool("group_by_workspace", false) : false;
    auto widget = std::make_unique<TaskbarWidget>(m_wayland, output, groupByWorkspace, barPosition);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "theme_mode") {
    auto widget = std::make_unique<ThemeModeWidget>(m_themeService);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "tray") {
    const auto hiddenItems = wc != nullptr ? wc->getStringList("hidden") : std::vector<std::string>{};
    const auto pinnedItems = wc != nullptr ? wc->getStringList("pinned") : std::vector<std::string>{};
    const bool drawer = wc != nullptr ? wc->getBool("drawer", false) : false;
    const std::size_t drawerColumns =
        static_cast<std::size_t>(std::clamp<std::int64_t>(wc != nullptr ? wc->getInt("drawer_columns", 3) : 3, 1, 5));
    auto widget = std::make_unique<TrayWidget>(m_tray, hiddenItems, pinnedItems, drawer, std::function<void()>{},
                                               barPosition, false, drawerColumns);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "volume") {
    const bool showLabel = wc != nullptr ? wc->getBool("show_label", true) : true;
    auto widget = std::make_unique<VolumeWidget>(m_audio, output, showLabel);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "wallpaper") {
    auto barGlyph = wc != nullptr ? wc->getString("glyph", "wallpaper-selector") : std::string{"wallpaper-selector"};
    if (barGlyph.empty()) {
      barGlyph = "wallpaper-selector";
    }
    auto widget = std::make_unique<WallpaperWidget>(output, std::move(barGlyph));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "weather") {
    const float maxWidth = static_cast<float>(wc != nullptr ? wc->getDouble("max_length", 160.0) : 160.0);
    const bool showCondition = wc != nullptr ? wc->getBool("show_condition", true) : true;
    auto widget = std::make_unique<WeatherWidget>(m_weather, output, maxWidth, showCondition);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "workspaces") {
    const std::string display = wc != nullptr ? wc->getString("display", "id") : std::string("id");
    const ColorSpec focusedColor =
        colorSpecFromConfigString(wc != nullptr ? wc->getString("focused_color", "primary") : std::string("primary"));
    const ColorSpec occupiedColor = colorSpecFromConfigString(
        wc != nullptr ? wc->getString("occupied_color", "secondary") : std::string("secondary"));
    const ColorSpec emptyColor =
        colorSpecFromConfigString(wc != nullptr ? wc->getString("empty_color", "secondary") : std::string("secondary"));
    WorkspacesWidget::DisplayMode displayMode = WorkspacesWidget::DisplayMode::Id;
    if (display == "id") {
      displayMode = WorkspacesWidget::DisplayMode::Id;
    } else if (display == "name") {
      displayMode = WorkspacesWidget::DisplayMode::Name;
    } else if (display == "none") {
      displayMode = WorkspacesWidget::DisplayMode::None;
    }
    auto widget =
        std::make_unique<WorkspacesWidget>(m_wayland, output, displayMode, focusedColor, occupiedColor, emptyColor);
    widget->setContentScale(contentScale);
    return widget;
  }

  kLog.warn("widget factory: unknown widget \"{}\"", name);
  return nullptr;
}
