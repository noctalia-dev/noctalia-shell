#pragma once

#include "config/config_types.h"
#include "scripting/plugin_manager.h"
#include "scripting/plugin_manifest.h"

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
    bool pluginsLoading = false;

    std::function<void(std::string id, bool enable)> setEnabled;
    std::function<void()> addSource;
    std::function<void(PluginSourceConfig source, bool autoUpdate)> setSourceAutoUpdate;
    std::function<void(std::string source)> updateSource;
    std::function<void(std::string source)> removeSource;
    std::function<void()> refresh;

    // Used to derive current toggle state while async discovery refreshes.
    const Config* config = nullptr;
    std::function<void(std::string id)> onConfigure;
  };

  // Render the Plugins section into `content` when ctx.selectedSection == "plugins".
  void addSettingsPlugins(Flex& content, SettingsPluginsContext ctx);

  void buildPluginSettingsEditor(
      Flex& body, const Config& cfg, SettingsControlFactory& factory, const std::string& pluginId,
      const scripting::PluginManifest& manifest, bool showAdvanced, float scale
  );

} // namespace settings
