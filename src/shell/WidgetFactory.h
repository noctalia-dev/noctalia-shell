#pragma once

#include "shell/Widget.h"

#include <memory>
#include <string>

struct Config;
struct wl_output;
class TimeService;
class WaylandConnection;

class WidgetFactory {
public:
    WidgetFactory(WaylandConnection& wayland, TimeService* time, const Config& config);

    [[nodiscard]] std::unique_ptr<Widget> create(const std::string& name, wl_output* output) const;

private:
    WaylandConnection& m_wayland;
    TimeService* m_time;
    const Config& m_config;
};
