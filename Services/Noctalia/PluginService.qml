pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI

Singleton {
  id: root

  signal pluginLoaded(string pluginId)
  signal pluginUnloaded(string pluginId)
  signal pluginEnabled(string pluginId)
  signal pluginDisabled(string pluginId)
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

  // Track active fetches
  property var activeFetches: ({})

  property bool initialized: false
  property bool pluginsFullyLoaded: false

  // Plugin container from shell.qml (for placing Main instances in graphics scene)
  property var pluginContainer: null

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

  // Listen for language changes to reload plugin translations
  Connections {
    target: I18n

    function onLanguageChanged() {
      Logger.d("PluginService", "Language changed to:", I18n.langCode, "- reloading plugin translations");

      // Reload translations for all loaded plugins
      for (var pluginId in root.loadedPlugins) {
        var plugin = root.loadedPlugins[pluginId];
        if (plugin && plugin.api && plugin.manifest) {
          // Update current language
          plugin.api.currentLanguage = I18n.langCode;

          // Reload translations
          loadPluginTranslationsAsync(pluginId, plugin.manifest, I18n.langCode, function (translations) {
            plugin.api.pluginTranslations = translations;
            Logger.d("PluginService", "Reloaded translations for plugin:", pluginId);
          });
        }
      }
    }
  }

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

    for (var i = 0; i < enabledIds.length; i++) {
      Logger.d("PluginService", "Attempting to load plugin:", enabledIds[i]);
      var manifest = PluginRegistry.getPluginManifest(enabledIds[i]);
      if (manifest) {
        Logger.d("PluginService", "Manifest found for", enabledIds[i]);
        loadPlugin(enabledIds[i]);
      } else {
        Logger.w("PluginService", "Plugin", enabledIds[i], "is enabled but not found on disk - cleaning up");
        // Plugin was deleted from disk but still marked as enabled
        // Unregister it completely and remove its widget from bar
        var widgetId = "plugin:" + enabledIds[i];
        removeWidgetFromBar(widgetId);
        PluginRegistry.unregisterPlugin(enabledIds[i]);
      }
    }

    // Mark plugins as fully loaded
    root.pluginsFullyLoaded = true;
    Logger.i("PluginService", "All plugins loaded");
    root.allPluginsLoaded();

    // Fetch available plugins from all sources
    refreshAvailablePlugins();
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

    var enabledSources = PluginRegistry.getEnabledSources();
    Logger.d("PluginService", "Fetching from", enabledSources.length, "enabled sources");
    for (var i = 0; i < enabledSources.length; i++) {
      fetchPluginRegistry(enabledSources[i]);
    }
  }

  // Fetch plugin registry from a source
  function fetchPluginRegistry(source) {
    var rawUrl = source.url + "/refs/heads/main/registry.json";
    var registryUrl = rawUrl.replace("github.com", "raw.githubusercontent.com");

    Logger.d("PluginService", "Fetching registry from:", registryUrl);

    var fetchProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "curl -L -s '${registryUrl}' || wget -q -O- '${registryUrl}'"]
        stdout: StdioCollector {}
      }
    `, root, "FetchRegistry_" + Date.now());

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

            // Check if already downloaded
            plugin.downloaded = PluginRegistry.isPluginDownloaded(plugin.id);
            plugin.enabled = PluginRegistry.isPluginEnabled(plugin.id);

            root.availablePlugins.push(plugin);
          }

          Logger.i("PluginService", "Loaded", registry.plugins.length, "plugins from", source.name);
          root.availablePluginsUpdated();
        }
      } catch (e) {
        Logger.e("PluginService", "Failed to parse registry from", source.name, ":", e);
        Logger.e("PluginService", "Response was:", response ? response.substring(0, 200) : "null");
      }

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

  // Download and install a plugin
  function installPlugin(pluginMetadata, callback) {
    var pluginId = pluginMetadata.id;
    var source = pluginMetadata.source;

    Logger.i("PluginService", "Installing plugin:", pluginId, "from", source.name);

    var pluginDir = PluginRegistry.getPluginDir(pluginId);
    var repoUrl = source.url;
    var pluginPath = pluginId;

    // Download plugin folder from GitHub
    var downloadCmd = `
      mkdir -p '${pluginDir}' &&
      cd '${pluginDir}' &&
      (curl -L -s '${repoUrl}/archive/refs/heads/main.tar.gz' | tar -xz --strip-components=2 --wildcards '*/${pluginPath}/*' ||
       wget -q -O- '${repoUrl}/archive/refs/heads/main.tar.gz' | tar -xz --strip-components=2 --wildcards '*/${pluginPath}/*')
    `;

    var downloadProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "${downloadCmd}"]
      }
    `, root, "DownloadPlugin_" + pluginId);

    downloadProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        Logger.i("PluginService", "Downloaded plugin:", pluginId);

        // Load and validate manifest
        var manifestPath = pluginDir + "/manifest.json";
        loadManifest(manifestPath, function (success, manifest) {
          if (success) {
            var validation = PluginRegistry.validateManifest(manifest);
            if (validation.valid) {
              // Register plugin
              PluginRegistry.registerPlugin(manifest);
              Logger.i("PluginService", "Installed plugin:", pluginId);

              // Update available plugins list
              updatePluginInAvailable(pluginId, {
                                        downloaded: true
                                      });

              if (callback)
                callback(true, null);
            } else {
              Logger.e("PluginService", "Invalid manifest:", validation.error);
              if (callback)
                callback(false, "Invalid manifest: " + validation.error);
            }
          } else {
            Logger.e("PluginService", "Failed to load manifest for:", pluginId);
            if (callback)
              callback(false, "Failed to load manifest");
          }
        });
      } else {
        Logger.e("PluginService", "Failed to download plugin:", pluginId);
        if (callback)
          callback(false, "Download failed");
      }

      downloadProcess.destroy();
    });

    downloadProcess.running = true;
  }

  // Uninstall a plugin
  function uninstallPlugin(pluginId, callback) {
    Logger.i("PluginService", "Uninstalling plugin:", pluginId);

    // Disable and unload first
    if (PluginRegistry.isPluginEnabled(pluginId)) {
      disablePlugin(pluginId);
    }

    var pluginDir = PluginRegistry.getPluginDir(pluginId);

    var removeProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["rm", "-rf", "${pluginDir}"]
      }
    `, root, "RemovePlugin_" + pluginId);

    removeProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        PluginRegistry.unregisterPlugin(pluginId);
        Logger.i("PluginService", "Uninstalled plugin:", pluginId);

        // Update available plugins list
        updatePluginInAvailable(pluginId, {
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

  // Enable a plugin
  function enablePlugin(pluginId, skipAddToBar) {
    if (PluginRegistry.isPluginEnabled(pluginId)) {
      Logger.w("PluginService", "Plugin already enabled:", pluginId);
      return true;
    }

    if (!PluginRegistry.isPluginDownloaded(pluginId)) {
      Logger.e("PluginService", "Cannot enable: plugin not downloaded:", pluginId);
      return false;
    }

    PluginRegistry.setPluginEnabled(pluginId, true);
    loadPlugin(pluginId);

    // Add plugin widget to bar if it provides one (unless we're restoring from backup)
    if (!skipAddToBar) {
      var manifest = PluginRegistry.getPluginManifest(pluginId);
      if (manifest && manifest.entryPoints && manifest.entryPoints.barWidget) {
        var widgetId = "plugin:" + pluginId;
        addWidgetToBar(widgetId, "right"); // Default to right section
      }
    }

    updatePluginInAvailable(pluginId, {
                              enabled: true
                            });
    root.pluginEnabled(pluginId);
    return true;
  }

  // Helper function to add a widget to the bar
  function addWidgetToBar(widgetId, section) {
    section = section || "right"; // Default to right section

    // Check if widget already exists in any section
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

    // Add to specified section
    var widgets = Settings.data.bar.widgets[section] || [];
    widgets.push({
                   id: widgetId
                 });
    Settings.data.bar.widgets[section] = widgets;

    Logger.i("PluginService", "Added widget", widgetId, "to bar section:", section);
    return true;
  }

  // Disable a plugin
  function disablePlugin(pluginId) {
    if (!PluginRegistry.isPluginEnabled(pluginId)) {
      Logger.w("PluginService", "Plugin already disabled:", pluginId);
      return true;
    }

    // Remove plugin widget from bar before unloading
    var widgetId = "plugin:" + pluginId;
    removeWidgetFromBar(widgetId);

    PluginRegistry.setPluginEnabled(pluginId, false);
    unloadPlugin(pluginId);
    updatePluginInAvailable(pluginId, {
                              enabled: false
                            });
    root.pluginDisabled(pluginId);
    return true;
  }

  // Helper function to remove a widget from all bar sections
  function removeWidgetFromBar(widgetId) {
    var sections = ["left", "center", "right"];
    var changed = false;

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

    return changed;
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

    // Create plugin API object
    var pluginApi = createPluginAPI(pluginId, manifest);

    // Initialize plugin entry with API and manifest
    root.loadedPlugins[pluginId] = {
      barWidgetComponent: null,
      mainInstance: null,
      api: pluginApi,
      manifest: manifest
    };

    // Load Main.qml entry point if it exists
    if (manifest.entryPoints && manifest.entryPoints.main) {
      var mainPath = pluginDir + "/" + manifest.entryPoints.main;
      var mainComponent = Qt.createComponent("file://" + mainPath);

      if (mainComponent.status === Component.Ready) {
        // Get the plugin container from shell.qml (must be in graphics scene)
        if (!root.pluginContainer) {
          Logger.e("PluginService", "Plugin container not set. Shell must set PluginService.pluginContainer.");
          return;
        }

        // Instantiate Main.qml with container as parent (places it in graphics scene)
        var mainInstance = mainComponent.createObject(root.pluginContainer);

        if (mainInstance) {
          // Set pluginApi property after creation
          if (mainInstance.hasOwnProperty('pluginApi')) {
            mainInstance.pluginApi = pluginApi;
          } else {
            Logger.w("PluginService", "Main.qml for", pluginId, "should declare 'property var pluginApi: null'");
          }

          root.loadedPlugins[pluginId].mainInstance = mainInstance;
          Logger.i("PluginService", "Loaded Main.qml for plugin:", pluginId);
        } else {
          Logger.e("PluginService", "Failed to instantiate Main.qml for:", pluginId);
        }
      } else if (mainComponent.status === Component.Error) {
        Logger.e("PluginService", "Failed to load Main.qml:", mainComponent.errorString());
      }
    }

    // Load bar widget component if provided (don't instantiate - BarWidgetRegistry will do that)
    if (manifest.entryPoints && manifest.entryPoints.barWidget) {
      var widgetPath = pluginDir + "/" + manifest.entryPoints.barWidget;
      var widgetComponent = Qt.createComponent("file://" + widgetPath);

      if (widgetComponent.status === Component.Ready) {
        root.loadedPlugins[pluginId].barWidgetComponent = widgetComponent;

        // Register with BarWidgetRegistry
        BarWidgetRegistry.registerPluginWidget(pluginId, widgetComponent, manifest.metadata);
        Logger.i("PluginService", "Loaded bar widget for plugin:", pluginId);
      } else if (widgetComponent.status === Component.Error) {
        Logger.e("PluginService", "Failed to load bar widget component:", widgetComponent.errorString());
      }
    }

    Logger.i("PluginService", "Plugin loaded:", pluginId);
    root.pluginLoaded(pluginId);
  }

  // Unload a plugin
  function unloadPlugin(pluginId) {
    var plugin = root.loadedPlugins[pluginId];
    if (!plugin) {
      Logger.w("PluginService", "Plugin not loaded:", pluginId);
      return;
    }

    Logger.i("PluginService", "Unloading plugin:", pluginId);

    // Unregister from BarWidgetRegistry
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.barWidget) {
      BarWidgetRegistry.unregisterPluginWidget(pluginId);
    }

    // Destroy Main instance if any
    if (plugin.mainInstance) {
      plugin.mainInstance.destroy();
    }

    delete root.loadedPlugins[pluginId];
    root.pluginUnloaded(pluginId);
    Logger.i("PluginService", "Unloaded plugin:", pluginId);
  }

  // Create plugin API object
  function createPluginAPI(pluginId, manifest) {
    var pluginDir = PluginRegistry.getPluginDir(pluginId);
    var settingsFile = PluginRegistry.getPluginSettingsFile(pluginId);

    var api = Qt.createQmlObject(`
      import QtQuick

      QtObject {
        // Plugin-specific
        readonly property string pluginId: "${pluginId}"
        readonly property string pluginDir: "${pluginDir}"
        property var pluginSettings: ({})
        property var manifest: ({})

        // IPC handlers storage
        property var ipcHandlers: ({})

        // Translation storage
        property var pluginTranslations: ({})
        property string currentLanguage: ""

        // Functions will be bound below
        property var saveSettings: null
        property var openPanel: null
        property var closePanel: null
        property var tr: null
        property var trp: null
        property var hasTranslation: null
      }
    `, root, "PluginAPI_" + pluginId);

    // Set manifest
    api.manifest = manifest;

    // Set current language (can't use binding in Qt.createQmlObject string)
    api.currentLanguage = I18n.langCode;

    // Load plugin settings
    loadPluginSettings(pluginId, function (settings) {
      api.pluginSettings = settings;
    });

    // Load plugin translations for current language
    loadPluginTranslationsAsync(pluginId, manifest, I18n.langCode, function (translations) {
      api.pluginTranslations = translations;
    });

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
    api.openPanel = function (screen) {
      // Open this plugin's panel on the specified screen
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for opening panel");
        return false;
      }
      return openPluginPanel(pluginId, screen);
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
    // Translation function
    api.tr = function (key, interpolations) {
      if (typeof interpolations === 'undefined') {
        interpolations = {};
      }

      var translation = getNestedProperty(api.pluginTranslations, key);

      // Return formatted key if translation not found
      if (translation === undefined || translation === null) {
        return '## ' + key + ' ##';
      }

      // Ensure translation is a string
      if (typeof translation !== 'string') {
        return '## ' + key + ' ##';
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
    api.trp = function (key, count, defaultSingular, defaultPlural, interpolations) {
      if (typeof defaultSingular === 'undefined') {
        defaultSingular = '';
      }
      if (typeof defaultPlural === 'undefined') {
        defaultPlural = '';
      }
      if (typeof interpolations === 'undefined') {
        interpolations = {};
      }

      // Use key for singular, key_plural for plural
      var pluralKey = count === 1 ? key : key + '_plural';

      // Merge interpolations with count
      var finalInterpolations = {
        'count': count
      };
      for (var prop in interpolations) {
        finalInterpolations[prop] = interpolations[prop];
      }

      // Use tr() to look up the translation
      return api.tr(pluralKey, finalInterpolations);
    };

    // ----------------------------------------
    // Check if translation exists
    api.hasTranslation = function (key) {
      return getNestedProperty(api.pluginTranslations, key) !== undefined;
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
    Logger.d("PluginService", "Settings JSON:", settingsJson);

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
  function findAvailablePlugin(pluginId) {
    for (var i = 0; i < root.availablePlugins.length; i++) {
      if (root.availablePlugins[i].id === pluginId) {
        return root.availablePlugins[i];
      }
    }
    return null;
  }

  // Internal flag to track if we should check for updates after registry fetch
  property bool shouldCheckUpdatesAfterFetch: false

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
    var updateCount = Object.keys(updates).length;

    if (updateCount > 0) {
      Logger.i("PluginService", updateCount, "plugin update(s) available");
      ToastService.showNotice(I18n.tr("settings.plugins.update-available", {
                                        "count": updateCount
                                      }), I18n.tr("common.check-settings"));
    } else {
      Logger.i("PluginService", "All plugins are up to date");
    }

    shouldCheckUpdatesAfterFetch = false;
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

    // Backup entire bar layout
    var barBackup = {
      left: JSON.parse(JSON.stringify(Settings.data.bar.widgets.left || [])),
      center: JSON.parse(JSON.stringify(Settings.data.bar.widgets.center || [])),
      right: JSON.parse(JSON.stringify(Settings.data.bar.widgets.right || []))
    };
    Logger.d("PluginService", "Backed up bar layout");

    // Disable plugin (this removes widgets and unloads code)
    if (PluginRegistry.isPluginEnabled(pluginId)) {
      disablePlugin(pluginId);
    }

    // Now install the new version (reuse installPlugin logic)
    installPlugin(availablePlugin, function (success, error) {
      if (success) {
        Logger.i("PluginService", "Plugin updated successfully:", pluginId);

        // Re-enable the plugin first, so the new component is registered
        // Skip adding to bar since we'll restore the layout from backup
        enablePlugin(pluginId, true);

        // Then restore bar layout (so BarWidgetLoaders can find the new component)
        Settings.data.bar.widgets.left = barBackup.left;
        Settings.data.bar.widgets.center = barBackup.center;
        Settings.data.bar.widgets.right = barBackup.right;
        Logger.d("PluginService", "Restored bar layout");

        // Remove from updates list
        var updates = Object.assign({}, root.pluginUpdates);
        delete updates[pluginId];
        root.pluginUpdates = updates;

        if (callback)
          callback(true, null);
      } else {
        Logger.e("PluginService", "Failed to update plugin:", pluginId, error);

        // Restore bar layout even on failure
        Settings.data.bar.widgets.left = barBackup.left;
        Settings.data.bar.widgets.center = barBackup.center;
        Settings.data.bar.widgets.right = barBackup.right;

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
  function openPluginPanel(pluginId, screen) {
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
    // Try slot 1 first, then slot 2
    for (var slotNum = 1; slotNum <= 2; slotNum++) {
      var panelName = "pluginPanel" + slotNum;
      var panel = PanelService.getPanel(panelName, screen);

      if (panel) {
        // If this slot is already showing this plugin's panel, toggle it
        if (panel.currentPluginId === pluginId) {
          panel.toggle();
          return true;
        }

        // If this slot is empty, use it
        if (panel.currentPluginId === "") {
          // Set the pluginId first - when panel opens and panelContent loads,
          // Component.onCompleted will call loadPluginPanel automatically
          panel.currentPluginId = pluginId;
          panel.open();
          return true;
        }
      }
    }

    // If both slots are occupied, use slot 1 (replace existing)
    var panel1 = PanelService.getPanel("pluginPanel1", screen);
    if (panel1) {
      panel1.unloadPluginPanel();
      // Set the pluginId first - when panel opens and panelContent loads,
      // Component.onCompleted will call loadPluginPanel automatically
      panel1.currentPluginId = pluginId;
      panel1.open();
      return true;
    }

    Logger.e("PluginService", "Failed to find plugin panel slot");
    return false;
  }
}
