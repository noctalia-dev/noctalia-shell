#pragma once

#include "shell/BarInstance.h"
#include "shell/WidgetFactory.h"

#include <memory>
#include <unordered_map>
#include <vector>

class ConfigService;
class TimeService;
class WaylandConnection;
struct PointerEvent;
struct wl_surface;

class Bar {
public:
    Bar();

    bool initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService);
    void reload();
    void closeAllInstances();
    void onOutputChange();
    void onWorkspaceChange();
    void onPointerEvent(const PointerEvent& event);
    [[nodiscard]] bool isRunning() const noexcept;

private:
    void syncInstances();
    void createInstance(const WaylandOutput& output, const BarConfig& barConfig);
    void destroyInstance(std::uint32_t outputName);
    void populateWidgets(BarInstance& instance);
    void buildScene(BarInstance& instance, std::uint32_t width, std::uint32_t height);
    void updateWidgets(BarInstance& instance);
    Widget* findWidgetAtPosition(BarInstance& instance, float x, float y);

    WaylandConnection* m_wayland = nullptr;
    ConfigService* m_config = nullptr;
    TimeService* m_time = nullptr;
    std::unique_ptr<WidgetFactory> m_widgetFactory;
    std::vector<std::unique_ptr<BarInstance>> m_instances;

    // Pointer state
    std::unordered_map<wl_surface*, BarInstance*> m_surfaceMap;
    BarInstance* m_hoveredInstance = nullptr;
    Widget* m_hoveredWidget = nullptr;
    std::uint32_t m_lastPointerSerial = 0;
};
