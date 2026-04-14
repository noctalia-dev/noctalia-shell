#include "shell/widget/widget_factory.h"

#include "config/config_service.h"
#include "core/log.h"
#include "dbus/power/power_profiles_service.h"
#include "dbus/mpris/mpris_service.h"
#include "dbus/tray/tray_service.h"
#include "idle/idle_inhibitor.h"
#include "net/http_client.h"
#include "notification/notification_manager.h"
#include "pipewire/pipewire_spectrum.h"
#include "shell/widgets/active_window_widget.h"
#include "shell/widgets/audio_visualizer_widget.h"
#include "shell/widgets/battery_widget.h"
#include "shell/widgets/clock_widget.h"
#include "shell/widgets/idle_inhibitor_widget.h"
#include "shell/widgets/network_widget.h"
#include "shell/widgets/nightlight_widget.h"
#include "shell/widgets/launcher_widget.h"
#include "shell/widgets/media_widget.h"
#include "shell/widgets/notification_widget.h"
#include "shell/widgets/power_profiles_widget.h"
#include "shell/widgets/scripted_widget.h"
#include "shell/widgets/session_widget.h"
#include "shell/widgets/spacer_widget.h"
#include "shell/widgets/sysmon_widget.h"
#include "shell/widgets/test_widget.h"
#include "shell/widgets/theme_mode_widget.h"
#include "shell/widgets/tray_widget.h"
#include "shell/widgets/volume_widget.h"
#include "shell/widgets/wallpaper_widget.h"
#include "shell/widgets/weather_widget.h"
#include "shell/widgets/workspaces_widget.h"
#include "theme/theme_service.h"
#include "system/system_monitor_service.h"
#include "system/weather_service.h"
#include "wayland/wayland_connection.h"

namespace {
  constexpr Logger kLog("shell");
} // namespace

WidgetFactory::WidgetFactory(WaylandConnection& wayland, TimeService* time, const Config& config,
                             NotificationManager* notifications, TrayService* tray, PipeWireService* audio,
                             UPowerService* upower, SystemMonitorService* sysmon, PowerProfilesService* powerProfiles,
                             NetworkService* network, IdleInhibitor* idleInhibitor, MprisService* mpris,
                             PipeWireSpectrum* audioSpectrum, HttpClient* httpClient, WeatherService* weather,
                             NightLightManager* nightLight, noctalia::theme::ThemeService* themeService)
    : m_wayland(wayland), m_time(time), m_config(config), m_notifications(notifications), m_tray(tray), m_audio(audio),
      m_upower(upower), m_sysmon(sysmon), m_powerProfiles(powerProfiles), m_network(network),
      m_idleInhibitor(idleInhibitor), m_mpris(mpris), m_audioSpectrum(audioSpectrum), m_httpClient(httpClient),
      m_weather(weather), m_nightLight(nightLight), m_themeService(themeService) {}

std::unique_ptr<Widget> WidgetFactory::create(const std::string& name, wl_output* output, float contentScale) const {
  // Resolve: if name matches a [widget.<name>] entry, use its type + settings.
  // Otherwise treat the name itself as the widget type with default settings.
  const WidgetConfig* wc = nullptr;
  std::string type = name;

  auto it = m_config.widgets.find(name);
  if (it != m_config.widgets.end()) {
    wc = &it->second;
    type = it->second.type;
  }

  if (type == "clock") {
    if (m_time == nullptr) {
      kLog.warn("widget factory: clock requires TimeService");
      return nullptr;
    }
    std::string format = wc != nullptr ? wc->getString("format", "{:%H:%M}") : std::string("{:%H:%M}");
    auto widget = std::make_unique<ClockWidget>(*m_time, output, std::move(format));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "workspaces") {
    const std::string display = wc != nullptr ? wc->getString("display", "id") : std::string("id");
    WorkspacesWidget::DisplayMode displayMode = WorkspacesWidget::DisplayMode::Id;
    if (display == "id") {
      displayMode = WorkspacesWidget::DisplayMode::Id;
    } else if (display == "name") {
      displayMode = WorkspacesWidget::DisplayMode::Name;
    } else if (display == "none") {
      displayMode = WorkspacesWidget::DisplayMode::None;
    }
    auto widget = std::make_unique<WorkspacesWidget>(m_wayland, output, displayMode);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "active_window") {
    const float maxTitleWidth = static_cast<float>(wc != nullptr ? wc->getDouble("max_length", 260.0) : 260.0);
    const float iconSize = static_cast<float>(wc != nullptr ? wc->getDouble("icon_size", 16.0) : 16.0);
    auto widget = std::make_unique<ActiveWindowWidget>(m_wayland, maxTitleWidth, iconSize);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "notifications") {
    auto widget = std::make_unique<NotificationWidget>(m_notifications, output);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "session") {
    auto widget = std::make_unique<SessionWidget>(output);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "tray") {
    auto widget = std::make_unique<TrayWidget>(m_tray);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "power_profiles") {
    auto widget = std::make_unique<PowerProfilesWidget>(m_powerProfiles);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "nightlight") {
    auto widget = std::make_unique<NightLightWidget>(m_nightLight);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "theme_mode") {
    auto widget = std::make_unique<ThemeModeWidget>(m_themeService);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "idle_inhibitor") {
    auto widget = std::make_unique<IdleInhibitorWidget>(m_idleInhibitor);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "volume") {
    auto widget = std::make_unique<VolumeWidget>(m_audio, output);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "audio_visualizer") {
    const float width = static_cast<float>(wc != nullptr ? wc->getDouble("width", 56.0) : 56.0);
    const float height = static_cast<float>(wc != nullptr ? wc->getDouble("height", 16.0) : 16.0);
    const int bands = static_cast<int>(wc != nullptr ? wc->getInt("bands", 16) : 16);
    auto widget = std::make_unique<AudioVisualizerWidget>(m_audioSpectrum, width, height, bands);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "media") {
    const float maxWidth = static_cast<float>(wc != nullptr ? wc->getDouble("max_length", 220.0) : 220.0);
    const float artSize = static_cast<float>(wc != nullptr ? wc->getDouble("art_size", 24.0) : 24.0);
    auto widget = std::make_unique<MediaWidget>(m_mpris, m_httpClient, maxWidth, artSize);
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

  if (type == "battery") {
    auto widget = std::make_unique<BatteryWidget>(m_upower);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "network") {
    const bool showLabel = wc != nullptr ? wc->getBool("show_label", true) : true;
    auto widget = std::make_unique<NetworkWidget>(m_network, showLabel);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "launcher") {
    auto widget = std::make_unique<LauncherWidget>(output);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "wallpaper") {
    auto widget = std::make_unique<WallpaperWidget>(output);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "test") {
    auto widget = std::make_unique<TestWidget>(output);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "scripted") {
    std::string script = wc != nullptr ? wc->getString("script", "") : std::string();
    auto widget = std::make_unique<ScriptedWidget>(std::move(script));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "spacer") {
    const auto length = static_cast<float>(wc != nullptr ? wc->getDouble("length", wc->getDouble("width", 8.0))
                                                         : 8.0);
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
    auto widget = std::make_unique<SysmonWidget>(m_sysmon, stat, std::move(path), displayMode);
    widget->setContentScale(contentScale);
    return widget;
  }

  kLog.warn("widget factory: unknown widget \"{}\"", name);
  return nullptr;
}
