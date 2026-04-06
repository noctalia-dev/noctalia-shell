#include "shell/widget/widget_factory.h"

#include "config/config_service.h"
#include "core/log.h"
#include "dbus/tray/tray_service.h"
#include "notification/notification_manager.h"
#include "shell/widgets/clock_widget.h"
#include "shell/widgets/notification_widget.h"
#include "shell/widgets/spacer_widget.h"
#include "shell/widgets/test_widget.h"
#include "shell/widgets/tray_widget.h"
#include "shell/widgets/battery_widget.h"
#include "shell/widgets/volume_widget.h"
#include "shell/widgets/workspaces_widget.h"
#include "wayland/wayland_connection.h"

WidgetFactory::WidgetFactory(WaylandConnection& wayland, TimeService* time, const Config& config,
                             NotificationManager* notifications, TrayService* tray, PipeWireService* audio,
                             UPowerService* upower)
    : m_wayland(wayland), m_time(time), m_config(config), m_notifications(notifications), m_tray(tray),
      m_audio(audio), m_upower(upower) {}

std::unique_ptr<Widget> WidgetFactory::create(const std::string& name, wl_output* output) const {
  if (name == "clock") {
    if (m_time == nullptr) {
      logWarn("widget factory: clock requires TimeService");
      return nullptr;
    }
    return std::make_unique<ClockWidget>(*m_time, m_config.clock.format);
  }

  if (name == "workspaces") {
    return std::make_unique<WorkspacesWidget>(m_wayland, output);
  }

  if (name == "notifications") {
    return std::make_unique<NotificationWidget>(m_notifications);
  }

  if (name == "tray") {
    return std::make_unique<TrayWidget>(m_tray);
  }

  if (name == "volume") {
    return std::make_unique<VolumeWidget>(m_audio);
  }

  if (name == "battery") {
    return std::make_unique<BatteryWidget>(m_upower);
  }

  if (name == "test") {
    std::int32_t scale = 1;
    const auto* wlOutput = m_wayland.findOutputByWl(output);
    if (wlOutput != nullptr) {
      scale = wlOutput->scale;
    }
    return std::make_unique<TestWidget>(output, scale);
  }

  if (name == "spacer") {
    return std::make_unique<SpacerWidget>(8.0f);
  }

  logWarn("widget factory: unknown widget \"{}\"", name);
  return nullptr;
}
