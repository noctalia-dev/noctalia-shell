#pragma once

#include "shell/WallpaperInstance.h"

#include <memory>
#include <vector>

class ConfigService;
class StateService;
class WaylandConnection;
struct WaylandOutput;

class Wallpaper {
public:
    Wallpaper();

    bool initialize(WaylandConnection& wayland, ConfigService* config, StateService* state);
    void onOutputChange();
    void onStateChange();
    [[nodiscard]] bool hasInstances() const noexcept;

private:
    void syncInstances();
    void createInstance(const WaylandOutput& output);
    void loadWallpaper(WallpaperInstance& instance, const std::string& path);
    void startTransition(WallpaperInstance& instance);
    void updateRendererState(WallpaperInstance& instance);

    WaylandConnection* m_wayland = nullptr;
    ConfigService* m_config = nullptr;
    StateService* m_state = nullptr;
    std::vector<std::unique_ptr<WallpaperInstance>> m_instances;
};
