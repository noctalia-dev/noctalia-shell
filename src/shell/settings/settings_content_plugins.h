#pragma once

#include "config/config_types.h"
#include "scripting/plugin_manager.h"

#include <functional>
#include <string>
#include <string_view>
#include <vector>

class Flex;

namespace settings {

  class SettingsControlFactory;

  // Data + actions for the Plugins settings section. Populated by SettingsWindow
  // from the PluginManager; the section is fully custom (no registry entries).
  struct SettingsPluginsContext {
    float scale = 1.0f;
    std::string_view selectedSection;
    std::vector<scripting::PluginStatus> plugins;
    std::vector<PluginSourceConfig> sources;

    std::function<void(std::string id, bool enable)> setEnabled;
    std::function<void(std::string source)> updateSource;
    std::function<void(std::string source)> removeSource;
    std::function<void()> refresh;

    // Per-plugin settings editor (plugin-level [[setting]] block). Rendered inline
    // for the plugin whose id == configurePluginId, using controlFactory to build
    // override-backed controls writing to {"plugin_settings", id, key}.
    const Config* config = nullptr;
    SettingsControlFactory* controlFactory = nullptr;
    std::string configurePluginId;
    bool showAdvanced = false;
    std::function<void(std::string id)> onConfigure; // toggle the editor for a plugin id
  };

  // Render the Plugins section into `content` when ctx.selectedSection == "plugins".
  void addSettingsPlugins(Flex& content, SettingsPluginsContext ctx);

} // namespace settings
