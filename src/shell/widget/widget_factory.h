#pragma once

#include "shell/widget/widget.h"

#include <memory>
#include <string>

struct Config;
class NotificationManager;
class PipeWireService;
class TrayService;
struct wl_output;
class TimeService;
class WaylandConnection;

class WidgetFactory {
public:
  WidgetFactory(WaylandConnection& wayland, TimeService* time, const Config& config, NotificationManager* notifications,
                TrayService* tray, PipeWireService* audio);

  [[nodiscard]] std::unique_ptr<Widget> create(const std::string& name, wl_output* output) const;

private:
  WaylandConnection& m_wayland;
  TimeService* m_time;
  const Config& m_config;
  NotificationManager* m_notifications;
  TrayService* m_tray;
  PipeWireService* m_audio;
};
