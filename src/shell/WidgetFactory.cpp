#include "shell/WidgetFactory.h"

#include "config/ConfigService.h"
#include "core/Log.h"
#include "dbus/tray/TrayService.h"
#include "notification/NotificationManager.h"
#include "shell/widgets/ClockWidget.h"
#include "shell/widgets/NotificationWidget.h"
#include "shell/widgets/SpacerWidget.h"
#include "shell/widgets/TrayWidget.h"
#include "shell/widgets/WorkspacesWidget.h"

WidgetFactory::WidgetFactory(WaylandConnection& wayland, TimeService* time, const Config& config,
               NotificationManager* notifications, TrayService* tray)
  : m_wayland(wayland), m_time(time), m_config(config), m_notifications(notifications), m_tray(tray) {}

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

  if (name == "spacer") {
    return std::make_unique<SpacerWidget>(8.0f);
  }

  logWarn("widget factory: unknown widget \"{}\"", name);
  return nullptr;
}
