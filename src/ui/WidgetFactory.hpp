#pragma once

#include "ui/Widget.hpp"

#include <memory>
#include <string>

struct Config;
struct wl_output;
class TimeService;
class WaylandConnection;

class WidgetFactory {
public:
    WidgetFactory(const WaylandConnection& wayland, TimeService* time, const Config& config);

    [[nodiscard]] std::unique_ptr<Widget> create(const std::string& name, wl_output* output) const;

private:
    const WaylandConnection& m_wayland;
    TimeService* m_time;
    const Config& m_config;
};
