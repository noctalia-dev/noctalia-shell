#include "ui/WidgetFactory.hpp"

#include "config/ConfigService.hpp"
#include "core/Log.hpp"
#include "ui/widgets/ClockWidget.hpp"
#include "ui/widgets/SpacerWidget.hpp"
#include "ui/widgets/WorkspacesWidget.hpp"

WidgetFactory::WidgetFactory(const WaylandConnection& wayland, TimeService* time, const Config& config)
    : m_wayland(wayland)
    , m_time(time)
    , m_config(config) {}

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

    if (name == "spacer") {
        return std::make_unique<SpacerWidget>(8.0f);
    }

    logWarn("widget factory: unknown widget \"{}\"", name);
    return nullptr;
}
