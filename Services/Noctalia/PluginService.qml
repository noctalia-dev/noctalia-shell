pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.Noctalia
import qs.Services.UI

Singleton {
  id: root

  signal pluginLoaded(string pluginId)
  signal pluginUnloaded(string pluginId)
  signal pluginEnabled(string pluginId)
  signal pluginDisabled(string pluginId)
  signal pluginReloaded(string pluginId)
  signal availablePluginsUpdated
  signal allPluginsLoaded

  // When available plugins are updated, check if we should perform update check
  onAvailablePluginsUpdated: {
    if (shouldCheckUpdatesAfterFetch && Object.keys(activeFetches).length === 0) {
      Logger.d("PluginService", "All registry fetches complete, performing update check");
      performUpdateCheck();
    }
  }

  // Loaded plugin instances
  property var loadedPlugins: ({}) // { pluginId: { component, instance, api } }

  // Available plugins from all sources (fetched from registries)
  property var availablePlugins: ([]) // Array of plugin metadata from all sources

  // Plugin updates available: { pluginId: { currentVersion, availableVersion } }
  property var pluginUpdates: ({})

  // Plugin updates that require a newer Noctalia version: { pluginId: { currentVersion, availableVersion, minNoctaliaVersion } }
  property var pluginUpdatesPending: ({})

  // Plugin load errors: { pluginId: { error: string, entryPoint: string, timestamp: date } }
  property var pluginErrors: ({})
  signal pluginLoadError(string pluginId, string entryPoint, string error)

  // Track currently installing plugins: { pluginId: true }
  property var installingPlugins: ({})

  // Hot reload: file watchers for plugin directories
  property var pluginFileWatchers: ({}) // { pluginId: FileView }
  property list<string> pluginHotReloadEnabled: [] // List of pluginIds that have hot reload enabled

  // Track active fetches
  property var activeFetches: ({})

  property bool initialized: false
  property bool pluginsFullyLoaded: false

  // Plugin container from shell.qml (for placing Main instances in graphics scene)
  property var pluginContainer: null

  // Screen detector from shell.qml (for withCurrentScreen in plugin API)
  property var screenDetector: null

  // Track if we need to initialize once container is ready
  property bool needsInit: false

  // Watch for pluginContainer to be set
  onPluginContainerChanged: {
    if (root.pluginContainer && root.needsInit) {
      Logger.d("PluginService", "Plugin container now available, initializing plugins");
      root.needsInit = false;
      root.init();
    }
  }

  // Listen for PluginRegistry to finish loading
  Connections {
    target: PluginRegistry

    function onPluginsChanged() {
      if (!root.initialized) {
        if (root.pluginContainer) {
          // Container already available, init now
          root.init();
        } else {
          // Container not ready, wait for it
          Logger.d("PluginService", "Deferring plugin init until container is ready");
          root.needsInit = true;
        }
      }
    }
  }

  // When debug mode is disabled, tear down all hot reload watchers
  Connections {
    target: Settings

    function onIsDebugChanged() {
      if (!Settings.isDebug && root.pluginHotReloadEnabled.length > 0) {
        Logger.i("PluginService", "Debug mode disabled, removing all hot reload watchers");
        // Remove watchers for all hot-reload-enabled plugins
        var plugins = root.pluginHotReloadEnabled.slice(); // copy since we mutate
        for (var i = 0; i < plugins.length; i++) {
          removePluginFileWatcher(plugins[i]);
        }
        root.pluginHotReloadEnabled = [];
      }
    }
  }

  // Listen for language changes to reload plugin translations
  Connections {
    target: I18n

    function onLanguageChanged() {
      Logger.d("PluginService", "Language changed to:", I18n.langCode, "- reloading plugin translations");

      // Reload translations for all loaded plugins
      for (var pluginId in root.loadedPlugins) {
        // Use IIFE to capture current loop values (avoid closure bug)
        (function (id, plugin) {
          if (plugin && plugin.api && plugin.manifest) {
            // Update current language
            plugin.api.currentLanguage = I18n.langCode;

            // Reload translations
            loadPluginTranslationsAsync(id, plugin.manifest, I18n.langCode, function (translations) {
              plugin.api.pluginTranslations = translations;

              // Reload English fallback for non-English languages
              if (I18n.langCode !== "en") {
                loadPluginTranslationsAsync(id, plugin.manifest, "en", function (fallbackTranslations) {
                  plugin.api.pluginFallbackTranslations = fallbackTranslations;
                  plugin.api.translationVersion++;
                  Logger.d("PluginService", "Reloaded translations for plugin:", id);
                });
              } else {
                plugin.api.pluginFallbackTranslations = {};
                plugin.api.translationVersion++;
                Logger.d("PluginService", "Reloaded translations for plugin:", id);
              }
            });
          }
        })(pluginId, root.loadedPlugins[pluginId]);
      }

      // Update translation file watchers to watch the new language's files
      if (root.pluginHotReloadEnabled.length > 0) {
        updateTranslationWatchers();
      }
    }
  }

  // Track pending plugin loads for init completion
  property int _pendingPluginLoads: 0

  function init() {
    if (root.initialized) {
      Logger.d("PluginService", "Already initialized, skipping");
      return;
    }

    Logger.i("PluginService", "Initializing plugin system");
    root.initialized = true;

    // Debug: Check what's in PluginRegistry
    var allInstalled = PluginRegistry.getAllInstalledPluginIds();
    Logger.d("PluginService", "All installed plugins:", JSON.stringify(allInstalled));
    Logger.d("PluginService", "Plugin states:", JSON.stringify(PluginRegistry.pluginStates));

    // Load all enabled plugins
    var enabledIds = PluginRegistry.getEnabledPluginIds();
    Logger.i("PluginService", "Found", enabledIds.length, "enabled plugins:", JSON.stringify(enabledIds));

    // Count plugins that need to be loaded
    var pluginsToLoad = [];
    for (var i = 0; i < enabledIds.length; i++) {
      var manifest = PluginRegistry.getPluginManifest(enabledIds[i]);
      if (manifest) {
        pluginsToLoad.push(enabledIds[i]);
      } else {
        Logger.w("PluginService", "Plugin", enabledIds[i], "is enabled but not found on disk - install");
        var sourceUrl = PluginRegistry.getPluginSourceUrl(enabledIds[i]);
        root.installPlugin({
                             id: enabledIds[i],
                             source: {
                               url: sourceUrl
                             }
                           }, false, function (success, error, registeredKey) {
                             if (success) {
                               ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.install-success", {
                                                                                                  "plugin": registeredKey
                                                                                                }));
                               // Load the plugin since it was already enabled (state persisted but files were missing)
                               loadPlugin(registeredKey);

                               // Add plugin widget to bar if it provides one
                               var manifest = PluginRegistry.getPluginManifest(registeredKey);
                               if (manifest && manifest.entryPoints && manifest.entryPoints.barWidget) {
                                 var widgetId = "plugin:" + registeredKey;
                                 addWidgetToBar(widgetId, "right");
                               }
                             } else {
                               ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.install-error", {
                                                                                                 "error": error || "Unknown error"
                                                                                               }));
                             }
                           });
      }
    }

    // If no plugins to load, mark as complete immediately
    if (pluginsToLoad.length === 0) {
      root.pluginsFullyLoaded = true;
      Logger.i("PluginService", "No plugins to load");
      root.allPluginsLoaded();
      root._isStartupCheck = true;
      refreshAvailablePlugins();
      return;
    }

    // Track pending loads
    root._pendingPluginLoads = pluginsToLoad.length;

    // Load all plugins (async - they will call _onPluginLoadComplete when done)
    for (var j = 0; j < pluginsToLoad.length; j++) {
      Logger.d("PluginService", "Attempting to load plugin:", pluginsToLoad[j]);
      loadPlugin(pluginsToLoad[j]);
    }
  }

  // Called when a plugin finishes loading (success or failure)
  function _onPluginLoadComplete() {
    root._pendingPluginLoads--;

    if (root._pendingPluginLoads <= 0) {
      // All plugins finished loading
      root.pluginsFullyLoaded = true;
      Logger.i("PluginService", "All plugins loaded");
      root.allPluginsLoaded();

      // Fetch available plugins from all sources
      root._isStartupCheck = true;
      refreshAvailablePlugins();
    }
  }

  // Refresh available plugins from all sources
  function refreshAvailablePlugins() {
    // If fetches are already in progress, don't start new ones
    if (Object.keys(activeFetches).length > 0) {
      Logger.d("PluginService", "Refresh already in progress, skipping duplicate refresh");
      return;
    }

    Logger.i("PluginService", "Refreshing available plugins");
    root.availablePlugins = [];

    // Signal that we want to check for updates after refresh completes
    shouldCheckUpdatesAfterFetch = true;

    var enabledSources = PluginRegistry.getEnabledSources();
    Logger.d("PluginService", "Fetching from", enabledSources.length, "enabled sources");
    for (var i = 0; i < enabledSources.length; i++) {
      fetchPluginRegistry(enabledSources[i]);
    }
  }

  // Fetch plugin registry from a source using git sparse-checkout
  function fetchPluginRegistry(source) {
    var repoUrl = source.url;

    Logger.d("PluginService", "Fetching registry from:", repoUrl);

    // Use git sparse-checkout to fetch only registry.json (--no-cone for single file)
    // GIT_TERMINAL_PROMPT=0 prevents hanging on private repos that need auth
    var fetchCmd = "temp_dir=$(mktemp -d) && GIT_TERMINAL_PROMPT=0 git clone --filter=blob:none --sparse --depth=1 --quiet '" + repoUrl + "' \"$temp_dir\" 2>/dev/null && cd \"$temp_dir\" && git sparse-checkout set --no-cone /registry.json 2>/dev/null && cat \"$temp_dir/registry.json\"; rm -rf \"$temp_dir\"";

    var fetchProcess = Qt.createQmlObject('import QtQuick; import Quickshell.Io; Process { command: ["sh", "-c", "' + fetchCmd.replace(/"/g, '\\"') + '"]; stdout: StdioCollector {} }', root, "FetchRegistry_" + Date.now());

    activeFetches[source.url] = fetchProcess;

    fetchProcess.stdout.onStreamFinished.connect(function () {
      var response = fetchProcess.stdout.text;

      // Debug: log the raw response
      Logger.d("PluginService", "Registry response length:", response ? response.length : 0);

      if (!response || response.trim() === "") {
        Logger.e("PluginService", "Empty response from", source.name);
        delete activeFetches[source.url];
        fetchProcess.destroy();
        return;
      }

      try {
        var registry = JSON.parse(response);

        if (registry && registry.plugins && Array.isArray(registry.plugins)) {
          // Add source info to each plugin
          for (var i = 0; i < registry.plugins.length; i++) {
            var plugin = registry.plugins[i];
            plugin.source = source;

            // Check if already downloaded - use composite key
            var compositeKey = PluginRegistry.generateCompositeKey(plugin.id, source.url);
            plugin.downloaded = PluginRegistry.isPluginDownloaded(compositeKey);
            plugin.enabled = PluginRegistry.isPluginEnabled(compositeKey);

            root.availablePlugins.push(plugin);
          }

          Logger.i("PluginService", `Parsed ${registry.plugins.length} plugins manifest from '${source.name}'`);

          // Remove from active fetches BEFORE emitting signal so handler sees correct count
          delete activeFetches[source.url];
          fetchProcess.destroy();

          root.availablePluginsUpdated();
          return;
        }
      } catch (e) {
        Logger.e("PluginService", "Failed to parse registry from", source.name, ":", e);
        Logger.e("PluginService", "Response was:", response ? response.substring(0, 200) : "null");
      }

      // Clean up on error or empty response
      delete activeFetches[source.url];
      fetchProcess.destroy();
    });

    fetchProcess.exited.connect(function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("PluginService", "Failed to fetch registry from", source.name, "- exit code:", exitCode);
        delete activeFetches[source.url];
        fetchProcess.destroy();
      }
    });

    fetchProcess.running = true;
  }

  // Check for plugin ID collision before installation
  function checkPluginCollision(pluginMetadata) {
    var sourceUrl = pluginMetadata.source.url;
    var compositeKey = PluginRegistry.generateCompositeKey(pluginMetadata.id, sourceUrl);

    // Check if this exact composite key already exists
    if (PluginRegistry.isPluginDownloaded(compositeKey)) {
      return {
        collision: true,
        reason: "already_installed",
        existingKey: compositeKey,
        message: I18n.tr("panels.plugins.collision-already-installed")
      };
    }

    // For official plugins, also check if any custom version with same base ID exists
    if (PluginRegistry.isMainSource(sourceUrl)) {
      var allInstalled = PluginRegistry.getAllInstalledPluginIds();
      for (var i = 0; i < allInstalled.length; i++) {
        var parsed = PluginRegistry.parseCompositeKey(allInstalled[i]);
        if (parsed.pluginId === pluginMetadata.id && !parsed.isOfficial) {
          var sourceName = PluginRegistry.getSourceNameByHash(parsed.sourceHash) || I18n.tr("panels.plugins.source-custom");
          return {
            collision: true,
            reason: "custom_version_exists",
            existingKey: allInstalled[i],
            message: I18n.tr("panels.plugins.collision-custom-version-exists", {
                               source: sourceName
                             })
          };
        }
      }
    }

    // For custom plugins, check if official version exists
    if (!PluginRegistry.isMainSource(sourceUrl)) {
      if (PluginRegistry.isPluginDownloaded(pluginMetadata.id)) {
        return {
          collision: true,
          reason: "official_version_exists",
          existingKey: pluginMetadata.id,
          message: I18n.tr("panels.plugins.collision-official-version-exists")
        };
      }
    }

    return {
      collision: false
    };
  }

  // Download and install a plugin using git sparse-checkout
  // skipCollisionCheck: set to true when updating an existing plugin
  function installPlugin(pluginMetadata, skipCollisionCheck, callback) {
    var pluginId = pluginMetadata.id;
    // Do not include hash for 3rd party plugins
    var pluginIdRegex = /^[a-f0-9]{6}:/;
    if (pluginIdRegex.test(pluginId)) {
      pluginId = pluginId.substring(7);
    }

    var source = pluginMetadata.source;

    // Check for collision first (skip when updating)
    if (!skipCollisionCheck) {
      var collision = checkPluginCollision(pluginMetadata);
      if (collision.collision) {
        Logger.w("PluginService", "Plugin collision detected:", collision.message);
        ToastService.showError(I18n.tr("panels.plugins.title"), collision.message);
        if (callback)
          callback(false, collision.message);
        return;
      }

      // Check Noctalia version compatibility (skip when updating - that's handled in performUpdateCheck)
      if (pluginMetadata.minNoctaliaVersion) {
        var noctaliaVersion = UpdateService.baseVersion;
        if (compareVersions(pluginMetadata.minNoctaliaVersion, noctaliaVersion) > 0) {
          var incompatibleMsg = I18n.tr("panels.plugins.install-incompatible", {
                                          "plugin": pluginMetadata.name,
                                          "version": pluginMetadata.minNoctaliaVersion
                                        });
          Logger.w("PluginService", "Plugin incompatible:", incompatibleMsg);
          if (callback)
            callback(false, incompatibleMsg);
          return;
        }
      }
    }

    // Generate composite key for the plugin folder
    var compositeKey = PluginRegistry.generateCompositeKey(pluginId, source.url);
    Logger.i("PluginService", "Installing plugin:", compositeKey, "from", source.name);

    var pluginDir = PluginRegistry.getPluginDir(compositeKey);
    var repoUrl = source.url;

    // Use git sparse-checkout to clone only the plugin subfolder
    // GIT_TERMINAL_PROMPT=0 prevents hanging on private repos that need auth
    // Note: We download from the original pluginId folder in the repo, but save to compositeKey folder
    var downloadCmd = "temp_dir=$(mktemp -d) && GIT_TERMINAL_PROMPT=0 git clone --filter=blob:none --sparse --depth=1 --quiet '" + repoUrl + "' \"$temp_dir\" 2>/dev/null && cd \"$temp_dir\" && git sparse-checkout set '" + pluginId + "' 2>/dev/null && mkdir -p '" + pluginDir + "' && cp -r \"$temp_dir/" + pluginId + "/.\" '" + pluginDir
        + "/'; exit_code=$?; rm -rf \"$temp_dir\"; exit $exit_code";

    // Mark as installing
    var newInstalling = Object.assign({}, root.installingPlugins);
    newInstalling[pluginId] = true;
    root.installingPlugins = newInstalling;

    var downloadProcess = Qt.createQmlObject('import QtQuick; import Quickshell.Io; Process { command: ["sh", "-c", "' + downloadCmd.replace(/"/g, '\\"') + '"] }', root, "DownloadPlugin_" + pluginId);

    downloadProcess.exited.connect(function (exitCode) {
      // Mark as finished (remove from installing)
      var currentInstalling = Object.assign({}, root.installingPlugins);
      delete currentInstalling[pluginId];
      root.installingPlugins = currentInstalling;

      if (exitCode === 0) {
        Logger.i("PluginService", "Downloaded plugin:", compositeKey);

        // Load and validate manifest
        var manifestPath = pluginDir + "/manifest.json";
        loadManifest(manifestPath, function (success, manifest) {
          if (success) {
            var validation = PluginRegistry.validateManifest(manifest);
            if (validation.valid) {
              // Register plugin with source URL
              var registeredKey = PluginRegistry.registerPlugin(manifest, source.url);
              Logger.i("PluginService", "Installed plugin:", registeredKey);

              // Update available plugins list
              updatePluginInAvailable(pluginId, {
                                        downloaded: true
                                      });

              if (callback)
                callback(true, null, registeredKey);
            } else {
              Logger.e("PluginService", "Invalid manifest:", validation.error);
              if (callback)
                callback(false, "Invalid manifest: " + validation.error);
            }
          } else {
            Logger.e("PluginService", "Failed to load manifest for:", compositeKey);
            if (callback)
              callback(false, "Failed to load manifest");
          }
        });
      } else {
        Logger.e("PluginService", "Failed to download plugin:", compositeKey);
        if (callback)
          callback(false, "Download failed");
      }

      downloadProcess.destroy();
    });

    downloadProcess.running = true;
  }

  // Uninstall a plugin (compositeKey is the full key like "abc123:my-plugin" or plain "my-plugin")
  function uninstallPlugin(compositeKey, callback) {
    Logger.i("PluginService", "Uninstalling plugin:", compositeKey);

    // Disable and unload first
    if (PluginRegistry.isPluginEnabled(compositeKey)) {
      disablePlugin(compositeKey);
    }

    var pluginDir = PluginRegistry.getPluginDir(compositeKey);

    var removeProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["rm", "-rf", "${pluginDir}"]
      }
    `, root, "RemovePlugin_" + compositeKey);

    removeProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        PluginRegistry.unregisterPlugin(compositeKey);
        Logger.i("PluginService", "Uninstalled plugin:", compositeKey);

        // Update available plugins list (use plain ID to match against availablePlugins)
        var parsed = PluginRegistry.parseCompositeKey(compositeKey);
        updatePluginInAvailable(parsed.pluginId, {
                                  downloaded: false,
                                  enabled: false
                                });

        if (callback)
          callback(true, null);
      } else {
        Logger.e("PluginService", "Failed to uninstall plugin:", pluginId);
        if (callback)
          callback(false, "Failed to remove plugin files");
      }

      removeProcess.destroy();
    });

    removeProcess.running = true;
  }

  // Enable a plugin (compositeKey is the full key like "abc123:my-plugin" or plain "my-plugin")
  function enablePlugin(compositeKey, skipAddToBar) {
    if (PluginRegistry.isPluginEnabled(compositeKey)) {
      Logger.w("PluginService", "Plugin already enabled:", compositeKey);
      return true;
    }

    if (!PluginRegistry.isPluginDownloaded(compositeKey)) {
      Logger.e("PluginService", "Cannot enable: plugin not downloaded:", compositeKey);
      return false;
    }

    PluginRegistry.setPluginEnabled(compositeKey, true);
    loadPlugin(compositeKey);

    // Add plugin widget to bar if it provides one (unless we're restoring from backup)
    if (!skipAddToBar) {
      var manifest = PluginRegistry.getPluginManifest(compositeKey);
      if (manifest && manifest.entryPoints && manifest.entryPoints.barWidget) {
        var widgetId = "plugin:" + compositeKey;
        addWidgetToBar(widgetId, "right");
      }
    }

    // Update available plugins list (use plain ID to match against availablePlugins)
    var parsed = PluginRegistry.parseCompositeKey(compositeKey);
    updatePluginInAvailable(parsed.pluginId, {
                              enabled: true
                            });
    root.pluginEnabled(compositeKey);

    return true;
  }

  // Helper function to add a widget to the bar (global + all screen overrides)
  function addWidgetToBar(widgetId, section) {
    section = section || "right"; // Default to right section

    // Check if widget already exists in any section (global)
    var sections = ["left", "center", "right"];
    for (var s = 0; s < sections.length; s++) {
      var widgets = Settings.data.bar.widgets[sections[s]] || [];
      for (var i = 0; i < widgets.length; i++) {
        if (widgets[i].id === widgetId) {
          Logger.d("PluginService", "Widget already in bar:", widgetId);
          return false;
        }
      }
    }

    // Add to global
    var globalWidgets = Settings.data.bar.widgets[section] || [];
    globalWidgets.push({
                         id: widgetId
                       });
    Settings.data.bar.widgets[section] = globalWidgets;

    // Also add to any screen overrides that have widget configurations
    var overrides = Settings.data.bar.screenOverrides || [];
    for (var o = 0; o < overrides.length; o++) {
      if (overrides[o] && overrides[o].widgets) {
        var overrideWidgets = overrides[o].widgets;
        var sectionWidgets = overrideWidgets[section] || [];
        // Check if widget already exists in this override
        var alreadyExists = false;
        for (var j = 0; j < sections.length; j++) {
          var owSec = overrideWidgets[sections[j]] || [];
          for (var k = 0; k < owSec.length; k++) {
            if (owSec[k].id === widgetId) {
              alreadyExists = true;
              break;
            }
          }
          if (alreadyExists)
            break;
        }
        if (!alreadyExists) {
          sectionWidgets.push({
                                id: widgetId
                              });
          overrideWidgets[section] = sectionWidgets;
          Settings.setScreenOverride(overrides[o].name, "widgets", overrideWidgets);
        }
      }
    }

    Logger.i("PluginService", "Added widget", widgetId, "to bar section:", section);
    return true;
  }

  // Disable a plugin (compositeKey is the full key like "abc123:my-plugin" or plain "my-plugin")
  function disablePlugin(compositeKey) {
    if (!PluginRegistry.isPluginEnabled(compositeKey)) {
      Logger.w("PluginService", "Plugin already disabled:", compositeKey);
      return true;
    }

    // Remove plugin widget from bar before unloading
    var widgetId = "plugin:" + compositeKey;
    removeWidgetFromBar(widgetId);

    PluginRegistry.setPluginEnabled(compositeKey, false);
    unloadPlugin(compositeKey);

    // Update available plugins list (use plain ID to match against availablePlugins)
    var parsed = PluginRegistry.parseCompositeKey(compositeKey);
    updatePluginInAvailable(parsed.pluginId, {
                              enabled: false
                            });
    root.pluginDisabled(compositeKey);
    return true;
  }

  // Helper function to remove a widget from all bar sections (global + screen overrides)
  function removeWidgetFromBar(widgetId) {
    var sections = ["left", "center", "right"];
    var changed = false;

    // Remove from global
    for (var s = 0; s < sections.length; s++) {
      var section = sections[s];
      var widgets = Settings.data.bar.widgets[section] || [];
      var newWidgets = [];

      for (var i = 0; i < widgets.length; i++) {
        if (widgets[i].id !== widgetId) {
          newWidgets.push(widgets[i]);
        } else {
          changed = true;
          Logger.i("PluginService", "Removed widget", widgetId, "from bar section:", section);
        }
      }

      if (changed) {
        Settings.data.bar.widgets[section] = newWidgets;
      }
    }

    // Also remove from any screen overrides that have widget configurations
    var overrides = Settings.data.bar.screenOverrides || [];
    for (var o = 0; o < overrides.length; o++) {
      if (overrides[o] && overrides[o].widgets) {
        var overrideWidgets = overrides[o].widgets;
        var overrideChanged = false;
        for (var s2 = 0; s2 < sections.length; s2++) {
          var sec = sections[s2];
          var owWidgets = overrideWidgets[sec] || [];
          var owNew = [];
          for (var j = 0; j < owWidgets.length; j++) {
            if (owWidgets[j].id !== widgetId) {
              owNew.push(owWidgets[j]);
            } else {
              overrideChanged = true;
              changed = true;
              Logger.i("PluginService", "Removed widget", widgetId, "from screen override:", overrides[o].name, "section:", sec);
            }
          }
          if (overrideChanged) {
            overrideWidgets[sec] = owNew;
          }
        }
        if (overrideChanged) {
          Settings.setScreenOverride(overrides[o].name, "widgets", overrideWidgets);
        }
      }
    }

    // Signal the bar to refresh if widgets were removed
    if (changed) {
      BarService.widgetsRevision++;
    }

    return changed;
  }

  // Remove plugin desktop widgets from all monitors' saved settings
  function removePluginDesktopWidgetsFromSettings(pluginId) {
    var widgetId = "plugin:" + pluginId;
    var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
    var changed = false;

    for (var m = 0; m < monitorWidgets.length; m++) {
      var monitor = monitorWidgets[m];
      var widgets = monitor.widgets || [];
      var newWidgets = [];

      for (var i = 0; i < widgets.length; i++) {
        if (widgets[i].id !== widgetId) {
          newWidgets.push(widgets[i]);
        } else {
          changed = true;
          Logger.i("PluginService", "Removed desktop widget", widgetId, "from monitor:", monitor.name);
        }
      }

      if (newWidgets.length !== widgets.length) {
        monitorWidgets[m].widgets = newWidgets;
      }
    }

    if (changed) {
      Settings.data.desktopWidgets.monitorWidgets = monitorWidgets;
    }

    return changed;
  }

  // Load plugin settings and translations before instantiating components
  // This ensures pluginApi is fully populated before being passed to createObject()
  function loadPluginData(pluginId, manifest, callback) {
    // Load settings first
    loadPluginSettings(pluginId, function (settings) {
      // Then load translations
      loadPluginTranslationsAsync(pluginId, manifest, I18n.langCode, function (translations) {
        // Load English fallback for non-English languages
        if (I18n.langCode !== "en") {
          loadPluginTranslationsAsync(pluginId, manifest, "en", function (fallbackTranslations) {
            callback(settings, translations, fallbackTranslations);
          });
        } else {
          callback(settings, translations, {});
        }
      });
    });
  }

  // Load a plugin
  function loadPlugin(pluginId) {
    if (root.loadedPlugins[pluginId]) {
      Logger.w("PluginService", "Plugin already loaded:", pluginId);
      return;
    }

    var manifest = PluginRegistry.getPluginManifest(pluginId);
    if (!manifest) {
      Logger.e("PluginService", "Cannot load: manifest not found for:", pluginId);
      return;
    }

    var pluginDir = PluginRegistry.getPluginDir(pluginId);

    Logger.i("PluginService", "Loading plugin:", pluginId);

    // Load settings and translations FIRST, then create API and instantiate components
    loadPluginData(pluginId, manifest, function (settings, translations, fallbackTranslations) {
      // Create plugin API object with pre-loaded data
      var pluginApi = createPluginAPI(pluginId, manifest, settings, translations, fallbackTranslations);

      // Initialize plugin entry with API and manifest
      root.loadedPlugins[pluginId] = {
        barWidget: null,
        desktopWidget: null,
        launcherProvider: null,
        mainInstance: null,
        api: pluginApi,
        manifest: manifest
      };

      // Clear any previous errors for this plugin
      root.clearPluginError(pluginId);

      // Load Main.qml entry point if it exists
      if (manifest.entryPoints && manifest.entryPoints.main) {
        var mainPath = pluginDir + "/" + manifest.entryPoints.main;
        var loadVersion = PluginRegistry.pluginLoadVersions[pluginId] || 0;
        var mainComponent = Qt.createComponent("file://" + mainPath + "?v=" + loadVersion);

        if (mainComponent.status === Component.Ready) {
          // Get the plugin container from shell.qml (must be in graphics scene)
          if (!root.pluginContainer) {
            Logger.e("PluginService", "Plugin container not set. Shell must set PluginService.pluginContainer.");
            return;
          }

          // Instantiate Main.qml with pluginApi passed directly in createObject
          var mainInstance = mainComponent.createObject(root.pluginContainer, {
                                                          pluginApi: pluginApi
                                                        });

          if (mainInstance) {
            root.loadedPlugins[pluginId].mainInstance = mainInstance;
            pluginApi.mainInstance = mainInstance;
            Logger.i("PluginService", "Loaded Main.qml for plugin:", pluginId);
          } else {
            root.recordPluginError(pluginId, "main", "Failed to instantiate Main.qml");
          }
        } else if (mainComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "main", mainComponent.errorString());
        }
      }

      // Load bar widget component if provided (don't instantiate - BarWidgetRegistry will do that)
      if (manifest.entryPoints && manifest.entryPoints.barWidget) {
        var widgetPath = pluginDir + "/" + manifest.entryPoints.barWidget;
        var widgetLoadVersion = PluginRegistry.pluginLoadVersions[pluginId] || 0;
        var widgetComponent = Qt.createComponent("file://" + widgetPath + "?v=" + widgetLoadVersion);

        if (widgetComponent.status === Component.Ready) {
          root.loadedPlugins[pluginId].barWidget = widgetComponent;
          pluginApi.barWidget = widgetComponent;

          // Register with BarWidgetRegistry
          BarWidgetRegistry.registerPluginWidget(pluginId, widgetComponent, manifest.metadata);
          Logger.i("PluginService", "Loaded bar widget for plugin:", pluginId);

          // Now that the widget is registered, bump widgetsRevision so the bar can render it
          BarService.widgetsRevision++;
        } else if (widgetComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "barWidget", widgetComponent.errorString());
        }
      }

      // Load desktop widget component if provided (don't instantiate - DesktopWidgetRegistry will do that)
      if (manifest.entryPoints && manifest.entryPoints.desktopWidget) {
        var desktopWidgetPath = pluginDir + "/" + manifest.entryPoints.desktopWidget;
        var desktopWidgetLoadVersion = PluginRegistry.pluginLoadVersions[pluginId] || 0;
        var desktopWidgetComponent = Qt.createComponent("file://" + desktopWidgetPath + "?v=" + desktopWidgetLoadVersion);

        if (desktopWidgetComponent.status === Component.Ready) {
          root.loadedPlugins[pluginId].desktopWidget = desktopWidgetComponent;
          pluginApi.desktopWidget = desktopWidgetComponent;

          // Register with DesktopWidgetRegistry
          DesktopWidgetRegistry.registerPluginWidget(pluginId, desktopWidgetComponent, manifest.metadata);
          Logger.i("PluginService", "Loaded desktop widget for plugin:", pluginId);
        } else if (desktopWidgetComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "desktopWidget", desktopWidgetComponent.errorString());
        }
      }

      // Load launcher provider component if provided (don't instantiate - Launcher will do that)
      if (manifest.entryPoints && manifest.entryPoints.launcherProvider) {
        var launcherProviderPath = pluginDir + "/" + manifest.entryPoints.launcherProvider;
        var launcherProviderLoadVersion = PluginRegistry.pluginLoadVersions[pluginId] || 0;
        var launcherProviderComponent = Qt.createComponent("file://" + launcherProviderPath + "?v=" + launcherProviderLoadVersion);

        if (launcherProviderComponent.status === Component.Ready) {
          root.loadedPlugins[pluginId].launcherProvider = launcherProviderComponent;
          pluginApi.launcherProvider = launcherProviderComponent;

          // Register with LauncherProviderRegistry
          LauncherProviderRegistry.registerPluginProvider(pluginId, launcherProviderComponent, manifest.metadata);
          Logger.i("PluginService", "Loaded launcher provider for plugin:", pluginId);
        } else if (launcherProviderComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "launcherProvider", launcherProviderComponent.errorString());
        }
      }

      // Load control center widget component if provided
      if (manifest.entryPoints && manifest.entryPoints.controlCenterWidget) {
        var ccWidgetPath = pluginDir + "/" + manifest.entryPoints.controlCenterWidget;
        var ccWidgetLoadVersion = PluginRegistry.pluginLoadVersions[pluginId] || 0;
        var ccWidgetComponent = Qt.createComponent("file://" + ccWidgetPath + "?v=" + ccWidgetLoadVersion);

        if (ccWidgetComponent.status === Component.Ready) {
          root.loadedPlugins[pluginId].controlCenterWidget = ccWidgetComponent;
          pluginApi.controlCenterWidget = ccWidgetComponent;

          // Register with ControlCenterWidgetRegistry
          ControlCenterWidgetRegistry.registerPluginWidget(pluginId, ccWidgetComponent, manifest.metadata);
          Logger.i("PluginService", "Loaded control center widget for plugin:", pluginId);
        } else if (ccWidgetComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "controlCenterWidget", ccWidgetComponent.errorString());
        }
      }

      Logger.i("PluginService", "Plugin loaded:", pluginId);
      root.pluginLoaded(pluginId);

      // Set up hot reload watcher if enabled
      setupPluginFileWatcher(pluginId);

      // Notify that this plugin finished loading (for init tracking)
      root._onPluginLoadComplete();
    });
  }

  // Unload a plugin
  // preserveSettings: if true, don't remove desktop widget settings (used for hot reload)
  function unloadPlugin(pluginId, preserveSettings) {
    var plugin = root.loadedPlugins[pluginId];
    if (!plugin) {
      Logger.w("PluginService", "Plugin not loaded:", pluginId);
      return;
    }

    Logger.i("PluginService", "Unloading plugin:", pluginId);

    // Remove hot reload watcher
    removePluginFileWatcher(pluginId);

    // Unregister from BarWidgetRegistry
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.barWidget) {
      BarWidgetRegistry.unregisterPluginWidget(pluginId);
    }

    // Unregister from DesktopWidgetRegistry
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.desktopWidget) {
      // Only remove settings when uninstalling, not during hot reload
      if (!preserveSettings) {
        removePluginDesktopWidgetsFromSettings(pluginId);
      }
      DesktopWidgetRegistry.unregisterPluginWidget(pluginId);
    }

    // Unregister from LauncherProviderRegistry
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.launcherProvider) {
      LauncherProviderRegistry.unregisterPluginProvider(pluginId);
    }

    // Unregister from ControlCenterWidgetRegistry
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.controlCenterWidget) {
      ControlCenterWidgetRegistry.unregisterPluginWidget(pluginId);
    }

    // Destroy Main instance if any
    if (plugin.mainInstance) {
      plugin.mainInstance.destroy();
    }

    delete root.loadedPlugins[pluginId];
    root.pluginUnloaded(pluginId);
    Logger.i("PluginService", "Unloaded plugin:", pluginId);
  }

  // Create plugin API object with pre-loaded settings and translations
  function createPluginAPI(pluginId, manifest, settings, translations, fallbackTranslations) {
    var pluginDir = PluginRegistry.getPluginDir(pluginId);

    var api = Qt.createQmlObject(`
      import QtQuick

      QtObject {
        // Plugin-specific
        readonly property string pluginId: "${pluginId}"
        readonly property string pluginDir: "${pluginDir}"
        property var pluginSettings: ({})
        property var manifest: ({})

        // Instance references (set after loading)
        property var mainInstance: null
        property var barWidget: null
        property var desktopWidget: null
        property var launcherProvider: null
        property var controlCenterWidget: null

        // Panel state: which screen the plugin's panel is currently open on (null if closed)
        property var panelOpenScreen: null

        // IPC handlers storage
        property var ipcHandlers: ({})

        // Translation storage
        property var pluginTranslations: ({})
        property var pluginFallbackTranslations: ({})  // English fallback for missing keys
        property string currentLanguage: ""
        property int translationVersion: 0  // Increments when translations change - plugins should depend on this

        // Functions will be bound below
        property var saveSettings: null
        property var openPanel: null
        property var closePanel: null
        property var togglePanel: null
        property var openLauncher: null
        property var closeLauncher: null
        property var toggleLauncher: null
        property var withCurrentScreen: null
        property var tr: null
        property var trp: null
        property var hasTranslation: null
      }
    `, root, "PluginAPI_" + pluginId);

    // Set manifest
    api.manifest = manifest;

    // Set current language (can't use binding in Qt.createQmlObject string)
    api.currentLanguage = I18n.langCode;

    // Set pre-loaded settings and translations (available immediately!)
    api.pluginSettings = settings || {};
    api.pluginTranslations = translations || {};
    api.pluginFallbackTranslations = fallbackTranslations || {};

    // ----------------------------------------
    // Helper function to get nested property by dot notation
    var getNestedProperty = function (obj, path) {
      var keys = path.split('.');
      var current = obj;
      for (var i = 0; i < keys.length; i++) {
        if (current === undefined || current === null) {
          return undefined;
        }
        current = current[keys[i]];
      }
      return current;
    };

    // ----------------------------------------
    // Bind functions
    // ----------------------------------------
    api.saveSettings = function () {
      savePluginSettings(pluginId, api.pluginSettings);

      // Replace the entire pluginSettings object to trigger QML property bindings
      // Make a shallow copy so bindings detect the change
      api.pluginSettings = Object.assign({}, api.pluginSettings);
    };

    // ----------------------------------------
    api.togglePanel = function (screen, buttonItem) {
      // Toggle this plugin's panel on the specified screen
      // buttonItem: optional, if provided the panel will position near this button
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for toggling panel");
        return false;
      }
      return togglePluginPanel(pluginId, screen, buttonItem);
    };

    // ----------------------------------------
    api.openPanel = function (screen, buttonItem) {
      // Open this plugin's panel on the specified screen
      // buttonItem: optional, if provided the panel will position near this button
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for opening panel");
        return false;
      }
      return openPluginPanel(pluginId, screen, buttonItem);
    };

    // ----------------------------------------
    api.closePanel = function (screen) {
      // Close this plugin's panel (find which slot it's in and close it)
      for (var slotNum = 1; slotNum <= 2; slotNum++) {
        var panelName = "pluginPanel" + slotNum;
        var panel = PanelService.getPanel(panelName, screen);
        if (panel && panel.currentPluginId === pluginId) {
          panel.close();
          return true;
        }
      }
      return false;
    };

    // ----------------------------------------
    // Launcher provider methods
    // ----------------------------------------

    // Get the search prefix for this plugin's launcher provider
    var getSearchPrefix = function () {
      var metadata = LauncherProviderRegistry.getProviderMetadata("plugin:" + pluginId);
      var prefix = (metadata && metadata.commandPrefix) ? metadata.commandPrefix : pluginId;
      return ">" + prefix + " ";
    };

    api.openLauncher = function (screen) {
      // Open the launcher with this plugin's provider active
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for opening launcher");
        return;
      }
      PanelService.openLauncherWithSearch(screen, getSearchPrefix());
    };

    api.closeLauncher = function (screen) {
      // Close the launcher
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for closing launcher");
        return;
      }
      PanelService.closeLauncher(screen);
    };

    api.toggleLauncher = function (screen) {
      // Toggle the launcher with this plugin's provider active
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for toggling launcher");
        return;
      }
      var searchPrefix = getSearchPrefix();
      var searchText = PanelService.getLauncherSearchText(screen);
      var isInThisMode = searchText.startsWith(searchPrefix);
      if (!PanelService.isLauncherOpen(screen)) {
        PanelService.openLauncherWithSearch(screen, searchPrefix);
      } else if (isInThisMode) {
        PanelService.closeLauncher(screen);
      } else {
        PanelService.setLauncherSearchText(screen, searchPrefix);
      }
    };

    // ----------------------------------------
    api.withCurrentScreen = function (callback) {
      // Detect which screen the cursor is on and call callback with that screen
      if (!root.screenDetector) {
        Logger.w("PluginAPI", "Screen detector not available, using primary screen");
        callback(Quickshell.screens[0]);
        return;
      }
      root.screenDetector.withCurrentScreen(callback);
    };

    // ----------------------------------------
    // Translation function
    api.tr = function (key, interpolations) {
      if (typeof interpolations === 'undefined') {
        interpolations = {};
      }

      var translation = getNestedProperty(api.pluginTranslations, key);

      // Fallback to English if not found in current language
      if (translation === undefined || translation === null || typeof translation !== 'string') {
        translation = getNestedProperty(api.pluginFallbackTranslations, key);
      }

      // Return formatted key if translation not found in any language
      if (translation === undefined || translation === null) {
        return `!!${key}!!`;
      }

      // Ensure translation is a string
      if (typeof translation !== 'string') {
        return `!!${key}!!`;
      }

      // Handle interpolations (e.g., "Hello {name}!")
      var result = translation;
      for (var placeholder in interpolations) {
        var regex = new RegExp('\\{' + placeholder + '\\}', 'g');
        result = result.replace(regex, interpolations[placeholder]);
      }

      return result;
    };

    // ----------------------------------------
    // Plural translation function
    api.trp = function (key, count, interpolations) {
      if (typeof interpolations === 'undefined') {
        interpolations = {};
      }

      // Use key for singular, key-plural for plural
      const realKey = count === 1 ? key : `${key}-plural`;

      // Merge interpolations with count
      var finalInterpolations = {
        'count': count
      };
      for (var prop in interpolations) {
        finalInterpolations[prop] = interpolations[prop];
      }

      // Use tr() to look up the translation
      return api.tr(realKey, finalInterpolations);
    };

    // ----------------------------------------
    // Check if translation exists
    api.hasTranslation = function (key) {
      return getNestedProperty(api.pluginTranslations, key) !== undefined || getNestedProperty(api.pluginFallbackTranslations, key) !== undefined;
    };

    return api;
  }

  // Load plugin translations asynchronously
  function loadPluginTranslationsAsync(pluginId, manifest, language, callback) {
    var pluginDir = PluginRegistry.getPluginDir(pluginId);
    var translationFile = pluginDir + "/i18n/" + language + ".json";

    var readProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${translationFile}"]
        stdout: StdioCollector {}
      }
    `, root, "ReadTranslation_" + pluginId + "_" + language);

    readProcess.exited.connect(function (exitCode) {
      var translations = {};

      if (exitCode === 0) {
        try {
          translations = JSON.parse(readProcess.stdout.text);
          Logger.d("PluginService", "Loaded translations for", pluginId, "language:", language);
        } catch (e) {
          Logger.w("PluginService", "Failed to parse translations for", pluginId, "language:", language);
        }
      } else {
        Logger.d("PluginService", "No translation file for", pluginId, "language:", language);
      }

      if (callback) {
        callback(translations);
      }

      readProcess.destroy();
    });

    readProcess.running = true;
  }

  // Load plugin settings
  function loadPluginSettings(pluginId, callback) {
    var settingsFile = PluginRegistry.getPluginSettingsFile(pluginId);

    var readProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${settingsFile}"]
        stdout: StdioCollector {}
      }
    `, root, "ReadSettings_" + pluginId);

    readProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        try {
          var settings = JSON.parse(readProcess.stdout.text);
          callback(settings);
        } catch (e) {
          Logger.w("PluginService", "Failed to parse settings for", pluginId, "- using defaults");
          callback({});
        }
      } else {
        // File doesn't exist - use defaults
        callback({});
      }

      readProcess.destroy();
    });

    readProcess.running = true;
  }

  // Save plugin settings
  function savePluginSettings(pluginId, settings) {
    var settingsFile = PluginRegistry.getPluginSettingsFile(pluginId);
    var settingsJson = JSON.stringify(settings, null, 2);

    // Use heredoc delimiter pattern to avoid all escaping issues
    var delimiter = "PLUGIN_SETTINGS_EOF_" + Math.random().toString(36).substr(2, 9);
    var fileEsc = settingsFile.replace(/'/g, "'\\''");

    // Get parent directory and ensure it exists
    var settingsDir = settingsFile.substring(0, settingsFile.lastIndexOf('/'));
    var dirEsc = settingsDir.replace(/'/g, "'\\''");

    // Build the shell command with heredoc (create dir first)
    var writeCmd = "mkdir -p '" + dirEsc + "' && cat > '" + fileEsc + "' << '" + delimiter + "'\n" + settingsJson + "\n" + delimiter + "\n";

    Logger.d("PluginService", "Saving settings to:", settingsFile);

    // Use Quickshell.execDetached to execute the command (use array syntax)
    var pid = Quickshell.execDetached(["sh", "-c", writeCmd]);
    Logger.d("PluginService", "Write process started, PID:", pid);
  }

  // Load manifest from file
  function loadManifest(manifestPath, callback) {
    var readProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${manifestPath}"]
        stdout: StdioCollector {}
      }
    `, root, "ReadManifest_" + Date.now());

    readProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        try {
          var manifest = JSON.parse(readProcess.stdout.text);
          callback(true, manifest);
        } catch (e) {
          Logger.e("PluginService", "Failed to parse manifest:", e);
          callback(false, null);
        }
      } else {
        Logger.e("PluginService", "Failed to read manifest at:", manifestPath);
        callback(false, null);
      }

      readProcess.destroy();
    });

    readProcess.running = true;
  }

  // Update plugin metadata in available plugins list
  function updatePluginInAvailable(pluginId, updates) {
    for (var i = 0; i < root.availablePlugins.length; i++) {
      if (root.availablePlugins[i].id === pluginId) {
        for (var key in updates) {
          root.availablePlugins[i][key] = updates[key];
        }
        root.availablePluginsUpdated();
        break;
      }
    }
  }

  // Find available plugin by ID
  function findAvailablePlugin(compositeKeyOrId) {
    var parsed = PluginRegistry.parseCompositeKey(compositeKeyOrId);
    var pluginId = parsed.pluginId;
    var sourceUrl = PluginRegistry.getPluginSourceUrl(compositeKeyOrId);

    for (var i = 0; i < root.availablePlugins.length; i++) {
      if (root.availablePlugins[i].id === pluginId && root.availablePlugins[i].source.url === sourceUrl) {
        return root.availablePlugins[i];
      }
    }
    return null;
  }

  // Internal flag to track if we should check for updates after registry fetch
  property bool shouldCheckUpdatesAfterFetch: false

  // Flag to track if this is the initial startup update check (for auto-update)
  property bool _isStartupCheck: false

  // Check for plugin updates (call this after availablePlugins are loaded)
  function checkForUpdates() {
    Logger.i("PluginService", "Checking for plugin updates");

    // If we have available plugins, check immediately regardless of active fetches
    if (root.availablePlugins.length > 0) {
      Logger.d("PluginService", "Available plugins already loaded, checking now");
      performUpdateCheck();
      return;
    }

    // No plugins yet - check if fetch is in progress
    if (Object.keys(activeFetches).length > 0) {
      Logger.d("PluginService", "Registry fetch in progress, will check after fetch completes");
      shouldCheckUpdatesAfterFetch = true;
      return;
    }

    // No plugins and no fetches - trigger refresh
    Logger.d("PluginService", "No available plugins yet, triggering refresh");
    shouldCheckUpdatesAfterFetch = true;
    refreshAvailablePlugins();
  }

  // Perform the actual update check
  function performUpdateCheck() {
    var updates = {};
    var pendingUpdates = {};
    var installedIds = PluginRegistry.getAllInstalledPluginIds();

    Logger.d("PluginService", "Checking", installedIds.length, "installed plugins against", root.availablePlugins.length, "available plugins");

    for (var i = 0; i < installedIds.length; i++) {
      var pluginId = installedIds[i];
      var installedManifest = PluginRegistry.getPluginManifest(pluginId);
      var availablePlugin = findAvailablePlugin(pluginId);

      if (installedManifest && availablePlugin) {
        var currentVersion = installedManifest.version;
        var availableVersion = availablePlugin.version;

        Logger.d("PluginService", "Comparing", pluginId + ":", currentVersion, "vs", availableVersion);

        // Compare versions
        if (compareVersions(availableVersion, currentVersion) > 0) {
          // Check if the available version requires a higher Noctalia version
          if (availablePlugin.minNoctaliaVersion) {
            var noctaliaVersion = UpdateService.baseVersion;
            if (compareVersions(availablePlugin.minNoctaliaVersion, noctaliaVersion) > 0) {
              Logger.d("PluginService", "Pending update for", pluginId + ": requires Noctalia v" + availablePlugin.minNoctaliaVersion + " (current: v" + noctaliaVersion + ")");
              pendingUpdates[pluginId] = {
                currentVersion: currentVersion,
                availableVersion: availableVersion,
                minNoctaliaVersion: availablePlugin.minNoctaliaVersion
              };
              continue;
            }
          }

          updates[pluginId] = {
            currentVersion: currentVersion,
            availableVersion: availableVersion
          };
          Logger.i("PluginService", "Update available for", pluginId + ":", currentVersion, "→", availableVersion);
        }
      } else if (installedManifest && !availablePlugin) {
        Logger.d("PluginService", "Plugin", pluginId, "not found in available plugins (might be from disabled source)");
      }
    }

    root.pluginUpdates = updates;
    root.pluginUpdatesPending = pendingUpdates;
    var updateCount = Object.keys(updates).length;
    var pendingCount = Object.keys(pendingUpdates).length;
    var updatesDescription = Object.keys(updates).map(function (pluginId) {
      return pluginId + ": " + updates[pluginId].currentVersion + " → " + updates[pluginId].availableVersion;
    }).join("\n");

    if (updateCount > 0) {
      Logger.i("PluginService", updateCount, "plugin update(s) available");
      ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.trp("panels.plugins.update-available", updateCount) + "\n\n" + updatesDescription, "plugin", 5000, I18n.tr("panels.plugins.open-plugins-tab"), function () {
        // Open settings panel to Plugins tab on the screen where the cursor is
        if (root.screenDetector) {
          root.screenDetector.withCurrentScreen(function (screen) {
            var panel = PanelService.getPanel("settingsPanel", screen);
            if (panel) {
              panel.requestedTab = SettingsPanel.Tab.Plugins;
              panel.open();
            }
          });
        } else {
          // Fallback to primary screen if screen detector is not available
          var panel = PanelService.getPanel("settingsPanel", Quickshell.screens[0]);
          if (panel) {
            panel.requestedTab = SettingsPanel.Tab.Plugins;
            panel.open();
          }
        }
      });
    } else if (pendingCount > 0) {
      Logger.i("PluginService", pendingCount, "plugin update(s) pending (require newer Noctalia)");
    } else {
      Logger.i("PluginService", "All installed plugins are up to date");
    }

    // Auto-update on startup if enabled
    if (root._isStartupCheck && Settings.data.plugins.autoUpdate && updateCount > 0) {
      Logger.i("PluginService", "Auto-updating", updateCount, "plugin(s)");
      updateAllPlugins();
    }

    root._isStartupCheck = false;
    shouldCheckUpdatesAfterFetch = false;
  }

  // Update all plugins sequentially
  function updateAllPlugins(callback) {
    var pluginIds = Object.keys(root.pluginUpdates);
    var currentIndex = 0;

    function updateNext() {
      if (currentIndex >= pluginIds.length) {
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.update-all-success"));
        if (callback)
          callback();
        return;
      }

      var pluginId = pluginIds[currentIndex];
      currentIndex++;

      root.updatePlugin(pluginId, function (success, error) {
        if (!success) {
          Logger.w("PluginService", "Failed to auto-update", pluginId + ":", error);
        }
        Qt.callLater(updateNext);
      });
    }

    updateNext();
  }

  // Simple version comparison (semantic versioning x.y.z)
  function compareVersions(a, b) {
    var aParts = a.split('.').map(function (x) {
      return parseInt(x) || 0;
    });
    var bParts = b.split('.').map(function (x) {
      return parseInt(x) || 0;
    });

    for (var i = 0; i < 3; i++) {
      var aNum = aParts[i] || 0;
      var bNum = bParts[i] || 0;
      if (aNum > bNum)
        return 1;
      if (aNum < bNum)
        return -1;
    }
    return 0;
  }

  // Update a plugin to the latest version
  function updatePlugin(pluginId, callback) {
    Logger.i("PluginService", "Updating plugin:", pluginId);

    // Find available plugin metadata
    var availablePlugin = findAvailablePlugin(pluginId);
    if (!availablePlugin) {
      Logger.e("PluginService", "Plugin not found in available plugins:", pluginId);
      if (callback)
        callback(false, "Plugin not found");
      return;
    }

    // Check Noctalia compatibility
    if (availablePlugin.minNoctaliaVersion) {
      // Simple check: just warn, don't block (UpdateService would have more sophisticated logic)
      Logger.d("PluginService", "Plugin requires Noctalia v" + availablePlugin.minNoctaliaVersion);
    }

    // Backup entire bar layout (global + screen overrides)
    var barBackup = {
      left: JSON.parse(JSON.stringify(Settings.data.bar.widgets.left || [])),
      center: JSON.parse(JSON.stringify(Settings.data.bar.widgets.center || [])),
      right: JSON.parse(JSON.stringify(Settings.data.bar.widgets.right || []))
    };
    var screenOverridesBackup = JSON.parse(JSON.stringify(Settings.data.bar.screenOverrides || []));
    Logger.d("PluginService", "Backed up bar layout (global + screen overrides)");

    // Backup desktop widget settings (includes this plugin's widgets)
    var desktopWidgetsBackup = JSON.parse(JSON.stringify(Settings.data.desktopWidgets.monitorWidgets || []));
    Logger.d("PluginService", "Backed up desktop widget settings");

    // Close any open panels for this plugin before update
    for (var slotNum = 1; slotNum <= 2; slotNum++) {
      var panelName = "pluginPanel" + slotNum;
      for (var s = 0; s < Quickshell.screens.length; s++) {
        var panel = PanelService.getPanel(panelName, Quickshell.screens[s]);
        if (panel && panel.currentPluginId === pluginId) {
          Logger.d("PluginService", "Closing plugin panel before update");
          panel.close();
          panel.unloadPluginPanel();
        }
      }
    }

    // Disable plugin (this removes widgets and unloads code)
    if (PluginRegistry.isPluginEnabled(pluginId)) {
      disablePlugin(pluginId);
    }

    // Now install the new version (reuse installPlugin logic, skip collision check since we're updating)
    installPlugin(availablePlugin, true, function (success, error) {
      if (success) {
        Logger.i("PluginService", "Plugin updated successfully:", pluginId);

        // Increment load version to invalidate Qt component cache
        PluginRegistry.incrementPluginLoadVersion(pluginId);

        // Re-enable the plugin first, so the new component is registered
        // Skip adding to bar since we'll restore the layout from backup
        enablePlugin(pluginId, true);

        // Then restore bar layout (so BarWidgetLoaders can find the new component)
        Settings.data.bar.widgets.left = barBackup.left;
        Settings.data.bar.widgets.center = barBackup.center;
        Settings.data.bar.widgets.right = barBackup.right;
        Settings.data.bar.screenOverrides = screenOverridesBackup;
        Logger.d("PluginService", "Restored bar layout (global + screen overrides)");

        // Restore desktop widget settings
        Settings.data.desktopWidgets.monitorWidgets = desktopWidgetsBackup;
        Logger.d("PluginService", "Restored desktop widget settings");

        // Remove from updates list
        var updates = Object.assign({}, root.pluginUpdates);
        delete updates[pluginId];
        root.pluginUpdates = updates;

        if (callback)
          callback(true, null);
      } else {
        Logger.e("PluginService", "Failed to update plugin:", pluginId, error);

        // Restore bar layout even on failure (global + screen overrides)
        Settings.data.bar.widgets.left = barBackup.left;
        Settings.data.bar.widgets.center = barBackup.center;
        Settings.data.bar.widgets.right = barBackup.right;
        Settings.data.bar.screenOverrides = screenOverridesBackup;

        // Restore desktop widget settings even on failure
        Settings.data.desktopWidgets.monitorWidgets = desktopWidgetsBackup;

        if (callback)
          callback(false, error);
      }
    });
  }

  // Get plugin API for a loaded plugin
  function getPluginAPI(pluginId) {
    return root.loadedPlugins[pluginId]?.api || null;
  }

  // Check if plugin is loaded
  function isPluginLoaded(pluginId) {
    return !!root.loadedPlugins[pluginId];
  }

  // Open a plugin's panel (finds a free slot and loads the panel)
  function openPluginPanel(pluginId, screen, buttonItem) {
    if (!isPluginLoaded(pluginId)) {
      Logger.w("PluginService", "Cannot open panel: plugin not loaded:", pluginId);
      return false;
    }

    var plugin = root.loadedPlugins[pluginId];
    if (!plugin || !plugin.manifest || !plugin.manifest.entryPoints || !plugin.manifest.entryPoints.panel) {
      Logger.w("PluginService", "Plugin does not provide a panel:", pluginId);
      return false;
    }

    // Try to find the plugin panel slot (pluginPanel1 or pluginPanel2)
    // Priority: 1) toggle same plugin, 2) empty slot, 3) closed slot, 4) replace open slot
    var closedSlot = null;

    for (var slotNum = 1; slotNum <= 2; slotNum++) {
      var panelName = "pluginPanel" + slotNum;
      var panel = PanelService.getPanel(panelName, screen);

      if (panel) {
        // If this slot is already showing this plugin's panel, toggle it
        if (panel.currentPluginId === pluginId) {
          panel.toggle(buttonItem);
          return true;
        }

        // If this slot is empty, use it
        if (panel.currentPluginId === "") {
          panel.currentPluginId = pluginId;
          panel.open(buttonItem);
          return true;
        }

        // Track first closed slot (panel assigned but not showing)
        if (!closedSlot && !panel.isPanelOpen) {
          closedSlot = panel;
        }
      }
    }

    // Prefer reusing a closed slot over replacing an open one
    if (closedSlot) {
      closedSlot.currentPluginId = pluginId;
      closedSlot.open(buttonItem);
      return true;
    }

    // If both slots are occupied and open, use slot 1 (replace existing)
    var panel1 = PanelService.getPanel("pluginPanel1", screen);
    if (panel1) {
      var wasAlreadyOpen = panel1.isPanelOpen;
      panel1.unloadPluginPanel();
      panel1.currentPluginId = pluginId;

      // If panel was already open, Component.onCompleted won't fire again
      // since panelContent is already loaded. We need to load the plugin manually.
      if (wasAlreadyOpen && panel1.contentLoader) {
        panel1.loadPluginPanel(pluginId);
      }

      panel1.open(buttonItem);
      return true;
    }

    Logger.e("PluginService", "Failed to find plugin panel slot");
    return false;
  }

  // Toggle a plugin's panel - close if open, open if closed
  // buttonItem: optional, if provided the panel will position near this button
  function togglePluginPanel(pluginId, screen, buttonItem) {
    if (!isPluginLoaded(pluginId)) {
      Logger.w("PluginService", "Cannot toggle panel: plugin not loaded:", pluginId);
      return false;
    }

    var plugin = root.loadedPlugins[pluginId];
    if (!plugin || !plugin.manifest || !plugin.manifest.entryPoints || !plugin.manifest.entryPoints.panel) {
      Logger.w("PluginService", "Plugin does not provide a panel:", pluginId);
      return false;
    }

    // Check if this plugin's panel is already open in any slot
    for (var slotNum = 1; slotNum <= 2; slotNum++) {
      var panelName = "pluginPanel" + slotNum;
      var panel = PanelService.getPanel(panelName, screen);

      if (panel && panel.currentPluginId === pluginId) {
        // Panel is open for this plugin - toggle it (close)
        panel.toggle(buttonItem);
        return true;
      }
    }

    // Panel is not open - open it using the existing logic
    return openPluginPanel(pluginId, screen, buttonItem);
  }

  // ----- Error tracking functions -----

  function recordPluginError(pluginId, entryPoint, errorMessage) {
    var errors = Object.assign({}, root.pluginErrors);
    errors[pluginId] = {
      error: errorMessage,
      entryPoint: entryPoint,
      timestamp: new Date()
    };
    root.pluginErrors = errors;
    root.pluginLoadError(pluginId, entryPoint, errorMessage);
    Logger.e("PluginService", "Plugin load error [" + pluginId + "/" + entryPoint + "]:", errorMessage);
  }

  function clearPluginError(pluginId) {
    if (pluginId in root.pluginErrors) {
      var errors = Object.assign({}, root.pluginErrors);
      delete errors[pluginId];
      root.pluginErrors = errors;
    }
  }

  function getPluginError(pluginId) {
    return root.pluginErrors[pluginId] || null;
  }

  function hasPluginError(pluginId) {
    return pluginId in root.pluginErrors;
  }

  // ----- Hot reload functions -----

  // Set up file watcher for a plugin directory
  function setupPluginFileWatcher(pluginId) {
    if (!isPluginHotReloadEnabled(pluginId)) {
      return;
    }

    // Don't create duplicate watchers
    if (root.pluginFileWatchers[pluginId]) {
      return;
    }

    var manifest = PluginRegistry.getPluginManifest(pluginId);
    if (!manifest) {
      return;
    }

    var pluginDir = PluginRegistry.getPluginDir(pluginId);

    // Create a debounce timer for this plugin
    var debounceTimer = Qt.createQmlObject(`
      import QtQuick
      Timer {
        property string targetPluginId: ""
        property var reloadCallback: null
        interval: 500
        repeat: false
        onTriggered: {
          if (reloadCallback) reloadCallback(targetPluginId);
        }
      }
    `, root, "HotReloadDebounce_" + pluginId);

    // Set properties after creation to pass the callback
    debounceTimer.targetPluginId = pluginId;
    debounceTimer.reloadCallback = root.reloadPlugin;

    // Watch the manifest file - changes here indicate plugin updates
    var manifestWatcher = Qt.createQmlObject(`
      import Quickshell.Io
      FileView {
        path: "${pluginDir}/manifest.json"
        watchChanges: true
      }
    `, root, "ManifestWatcher_" + pluginId);

    var watchers = [manifestWatcher];

    // Only watch .qml and .js files, also follow symlinks since some of the plugins might have been symlinked in.
    var qmlWatcher = Qt.createQmlObject(`
        import QtQuick
        import Quickshell.Io

        import qs.Commons

        Item {
            id: root
            signal fileChanged();

            Process {
                command: [ "sh", "-c", "find -L ${pluginDir} -name '*.qml' -o -name '*.js'" ]
                running: true
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: line => {
                        fileWatcher.createObject(root, { path: Qt.resolvedUrl(line) });
                    }
                }
            }

            Component {
                id: fileWatcher
                FileView {
                    watchChanges: true

                    onFileChanged: {
                        root.fileChanged();
                    }
                }
            }

        }
    `, root, "QmlWatcher_" + pluginId);
    watchers.push(qmlWatcher);

    // Connect all watchers to the debounce timer
    for (var j = 0; j < watchers.length; j++) {
      watchers[j].fileChanged.connect(function () {
        debounceTimer.restart();
      });
    }

    // Create a separate debounce timer for translation reloads (lighter weight)
    var translationDebounceTimer = Qt.createQmlObject(`
      import QtQuick
      Timer {
        property string targetPluginId: ""
        property var reloadCallback: null
        interval: 300
        repeat: false
        onTriggered: {
          if (reloadCallback) reloadCallback(targetPluginId);
        }
      }
    `, root, "TranslationReloadDebounce_" + pluginId);

    translationDebounceTimer.targetPluginId = pluginId;
    translationDebounceTimer.reloadCallback = root.reloadPluginTranslations;

    // Watch the current language's translation file
    var translationWatcher = createTranslationWatcher(pluginId, pluginDir, I18n.langCode, translationDebounceTimer);

    root.pluginFileWatchers[pluginId] = {
      watchers: watchers,
      debounceTimer: debounceTimer,
      translationWatcher: translationWatcher,
      translationDebounceTimer: translationDebounceTimer,
      pluginDir: pluginDir
    };

    Logger.d("PluginService", "Set up hot reload watcher for plugin:", pluginId, "(including translations)");
  }

  // Create a translation file watcher for a specific language
  function createTranslationWatcher(pluginId, pluginDir, language, debounceTimer) {
    var translationFile = pluginDir + "/i18n/" + language + ".json";

    var watcher = Qt.createQmlObject(`
      import Quickshell.Io
      FileView {
        path: "${translationFile}"
        watchChanges: true
      }
    `, root, "TranslationWatcher_" + pluginId + "_" + language);

    watcher.fileChanged.connect(function () {
      debounceTimer.restart();
    });

    Logger.d("PluginService", "Watching translation file:", translationFile);
    return watcher;
  }

  // Update translation watchers when language changes
  function updateTranslationWatchers() {
    for (var pluginId in root.pluginFileWatchers) {
      var watcherData = root.pluginFileWatchers[pluginId];
      if (!watcherData || !watcherData.translationDebounceTimer)
        continue;

      // Destroy old translation watcher
      if (watcherData.translationWatcher) {
        watcherData.translationWatcher.destroy();
      }

      // Create new watcher for current language
      watcherData.translationWatcher = createTranslationWatcher(pluginId, watcherData.pluginDir, I18n.langCode, watcherData.translationDebounceTimer);
    }
    Logger.d("PluginService", "Updated translation watchers for language:", I18n.langCode);
  }

  // Remove file watcher for a plugin
  function removePluginFileWatcher(pluginId) {
    var watcherData = root.pluginFileWatchers[pluginId];
    if (!watcherData) {
      return;
    }

    // Destroy all watchers
    if (watcherData.watchers) {
      for (var i = 0; i < watcherData.watchers.length; i++) {
        if (watcherData.watchers[i]) {
          watcherData.watchers[i].destroy();
        }
      }
    }

    // Destroy debounce timer
    if (watcherData.debounceTimer) {
      watcherData.debounceTimer.destroy();
    }

    // Destroy translation watcher
    if (watcherData.translationWatcher) {
      watcherData.translationWatcher.destroy();
    }

    // Destroy translation debounce timer
    if (watcherData.translationDebounceTimer) {
      watcherData.translationDebounceTimer.destroy();
    }

    delete root.pluginFileWatchers[pluginId];
    Logger.d("PluginService", "Removed hot reload watcher for plugin:", pluginId);
  }

  // Reload a plugin (hot reload)
  function reloadPlugin(pluginId) {
    if (!root.loadedPlugins[pluginId]) {
      Logger.w("PluginService", "Cannot reload: plugin not loaded:", pluginId);
      return false;
    }

    Logger.i("PluginService", "Hot reloading plugin:", pluginId);

    var manifest = PluginRegistry.getPluginManifest(pluginId);
    if (!manifest) {
      Logger.e("PluginService", "Cannot reload: manifest not found for:", pluginId);
      return false;
    }

    // Unregister widget instances from the bar
    BarService.destroyPluginWidgetInstances(pluginId);

    // Unload the plugin (destroys components and instances)
    // Pass true to preserve desktop widget settings during hot reload
    unloadPlugin(pluginId, true);

    // Increment load version to invalidate Qt's component cache
    PluginRegistry.incrementPluginLoadVersion(pluginId);

    // Use Qt.callLater to ensure destruction is complete before reloading
    // This prevents IPC handler conflicts and other timing issues
    Qt.callLater(function () {
      // Reload the plugin
      loadPlugin(pluginId);

      // Re-setup file watcher (it was destroyed during unload)
      setupPluginFileWatcher(pluginId);

      // Emit signal
      root.pluginReloaded(pluginId);

      // Show toast notification
      var pluginName = manifest.name || pluginId;
      ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.hot-reloaded", {
                                                                         "name": pluginName
                                                                       }));

      Logger.i("PluginService", "Hot reload complete for plugin:", pluginId);
    });

    return true;
  }

  // Hot reload only translations for a plugin (lightweight, no component reload)
  function reloadPluginTranslations(pluginId) {
    var plugin = root.loadedPlugins[pluginId];
    if (!plugin || !plugin.api || !plugin.manifest) {
      Logger.w("PluginService", "Cannot reload translations: plugin not loaded:", pluginId);
      return false;
    }

    Logger.i("PluginService", "Hot reloading translations for plugin:", pluginId);

    loadPluginTranslationsAsync(pluginId, plugin.manifest, I18n.langCode, function (translations) {
      plugin.api.pluginTranslations = translations;

      // Also reload English fallback for non-English languages
      if (I18n.langCode !== "en") {
        loadPluginTranslationsAsync(pluginId, plugin.manifest, "en", function (fallbackTranslations) {
          plugin.api.pluginFallbackTranslations = fallbackTranslations;
          plugin.api.translationVersion++;

          var pluginName = plugin.manifest.name || pluginId;
          ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.translations-reloaded", {
                                                                             "name": pluginName
                                                                           }));
          Logger.i("PluginService", "Translation hot reload complete for plugin:", pluginId);
        });
      } else {
        plugin.api.pluginFallbackTranslations = {};
        plugin.api.translationVersion++;

        var pluginName = plugin.manifest.name || pluginId;
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.translations-reloaded", {
                                                                           "name": pluginName
                                                                         }));
        Logger.i("PluginService", "Translation hot reload complete for plugin:", pluginId);
      }
    });

    return true;
  }

  // Check if a certain plugin has hot reload enabled
  function isPluginHotReloadEnabled(pluginId) {
    return root.pluginHotReloadEnabled.indexOf(pluginId) !== -1;
  }

  // Toggle the hot reload state of a certain plugin
  function togglePluginHotReload(pluginId) {
    const index = root.pluginHotReloadEnabled.indexOf(pluginId);
    if (index === -1) {
      root.pluginHotReloadEnabled.push(pluginId);
      setupPluginFileWatcher(pluginId);
      Logger.i("PluginService", "Hot reload enabled for plugin:", pluginId);
    } else {
      root.pluginHotReloadEnabled.splice(index, 1);
      removePluginFileWatcher(pluginId);
      Logger.i("PluginService", "Hot reload disabled for plugin:", pluginId);
    }
  }
}
