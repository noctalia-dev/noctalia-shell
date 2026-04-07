#include "shell/widget/widget_factory.h"

#include "config/config_service.h"
#include "core/log.h"
#include "dbus/tray/tray_service.h"
#include "notification/notification_manager.h"
#include "shell/widgets/battery_widget.h"
#include "shell/widgets/active_window_widget.h"
#include "shell/widgets/launcher_widget.h"
#include "shell/widgets/clock_widget.h"
#include "shell/widgets/notification_widget.h"
#include "shell/widgets/spacer_widget.h"
#include "shell/widgets/sysmon_widget.h"
#include "shell/widgets/test_widget.h"
#include "shell/widgets/tray_widget.h"
#include "shell/widgets/volume_widget.h"
#include "shell/widgets/workspaces_widget.h"
#include "system/system_monitor_service.h"
#include "wayland/wayland_connection.h"

WidgetFactory::WidgetFactory(WaylandConnection& wayland, TimeService* time, const Config& config,
                             NotificationManager* notifications, TrayService* tray, PipeWireService* audio,
                             UPowerService* upower, SystemMonitorService* sysmon)
    : m_wayland(wayland), m_time(time), m_config(config), m_notifications(notifications), m_tray(tray), m_audio(audio),
      m_upower(upower), m_sysmon(sysmon) {}

std::unique_ptr<Widget> WidgetFactory::create(const std::string& name, wl_output* output) const {
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
      logWarn("widget factory: clock requires TimeService");
      return nullptr;
    }
    std::string format = wc != nullptr ? wc->getString("format", "{:%H:%M}") : std::string("{:%H:%M}");
    std::int32_t scale = 1;
    const auto* wlOutput = m_wayland.findOutputByWl(output);
    if (wlOutput != nullptr) {
      scale = wlOutput->scale;
    }
    return std::make_unique<ClockWidget>(*m_time, output, scale, std::move(format));
  }

  if (type == "workspaces") {
    return std::make_unique<WorkspacesWidget>(m_wayland, output);
  }

  if (type == "active_window") {
    const float maxTitleWidth = static_cast<float>(wc != nullptr ? wc->getDouble("max_width", 260.0) : 260.0);
    const float iconSize = static_cast<float>(wc != nullptr ? wc->getDouble("icon_size", 16.0) : 16.0);
    return std::make_unique<ActiveWindowWidget>(m_wayland, maxTitleWidth, iconSize);
  }

  if (type == "notifications") {
    std::int32_t scale = 1;
    const auto* wlOutput = m_wayland.findOutputByWl(output);
    if (wlOutput != nullptr) {
      scale = wlOutput->scale;
    }
    return std::make_unique<NotificationWidget>(m_notifications, output, scale);
  }

  if (type == "tray") {
    return std::make_unique<TrayWidget>(m_tray);
  }

  if (type == "volume") {
    std::int32_t scale = 1;
    const auto* wlOutput = m_wayland.findOutputByWl(output);
    if (wlOutput != nullptr) {
      scale = wlOutput->scale;
    }
    return std::make_unique<VolumeWidget>(m_audio, output, scale);
  }

  if (type == "battery") {
    return std::make_unique<BatteryWidget>(m_upower);
  }

  if (type == "launcher") {
    std::int32_t scale = 1;
    const auto* wlOutput = m_wayland.findOutputByWl(output);
    if (wlOutput != nullptr) {
      scale = wlOutput->scale;
    }
    return std::make_unique<LauncherWidget>(output, scale);
  }

  if (type == "test") {
    std::int32_t scale = 1;
    const auto* wlOutput = m_wayland.findOutputByWl(output);
    if (wlOutput != nullptr) {
      scale = wlOutput->scale;
    }
    return std::make_unique<TestWidget>(output, scale);
  }

  if (type == "spacer") {
    auto width = static_cast<float>(wc != nullptr ? wc->getDouble("width", 8.0) : 8.0);
    return std::make_unique<SpacerWidget>(width);
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
    return std::make_unique<SysmonWidget>(m_sysmon, stat, std::move(path), displayMode);
  }

  logWarn("widget factory: unknown widget \"{}\"", name);
  return nullptr;
}
