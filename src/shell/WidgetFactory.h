#pragma once

#include "shell/Widget.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

struct Config;
class NotificationManager;
class TrayService;
struct wl_output;
class TimeService;
class WaylandConnection;

class WidgetFactory {
public:
  using PanelRequestCallback =
      std::function<void(const std::string& panelId, wl_output* output, std::int32_t scale, float anchorX)>;

  WidgetFactory(WaylandConnection& wayland, TimeService* time, const Config& config, NotificationManager* notifications,
                TrayService* tray, PanelRequestCallback panelCallback = {});

  [[nodiscard]] std::unique_ptr<Widget> create(const std::string& name, wl_output* output) const;

private:
  WaylandConnection& m_wayland;
  TimeService* m_time;
  const Config& m_config;
  NotificationManager* m_notifications;
  TrayService* m_tray;
  PanelRequestCallback m_panelCallback;
};
