pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  readonly property string pluginsDir: Settings.configDir + "plugins"
  readonly property string pluginsFile: Settings.configDir + "plugins.json"

  // Signals
  signal pluginsChanged

  // In-memory plugin cache (populated by scanning disk)
  property var installedPlugins: ({}) // { pluginId: manifest }
  property var pluginStates: ({}) // { pluginId: { enabled: bool } }
  property var pluginSources: [] // Array of { name, url }

  // Track async loading
  property int pendingManifests: 0

  // File storage (minimal - only states and sources)
  property FileView pluginsFileView: FileView {
    id: pluginsFileView
    path: root.pluginsFile

    adapter: JsonAdapter {
      id: adapter
      property int version: 1
      property var states: ({})
      property list<var> sources: []
    }

    onLoaded: {
      Logger.i("PluginRegistry", "Loaded plugin states from:", path);
      root.pluginStates = adapter.states || {};
      root.pluginSources = adapter.sources || [];

      // Ensure official repo is in sources
      if (root.pluginSources.length === 0) {
        root.pluginSources = [
          {
            "name": "Official Noctalia Plugins",
            "url": "https://github.com/noctalia-dev/noctalia-plugins",
            "enabled": true
          }
        ];
        root.save();
      }

      // Scan plugin folder to discover installed plugins
      scanPluginFolder();
    }

    onLoadFailed: function (error) {
      Logger.w("PluginRegistry", "Failed to load plugins.json, will create it:", error);
      // Initialize defaults and continue
      root.pluginStates = {};
      root.pluginSources = [
            {
              "name": "Official Noctalia Plugins",
              "url": "https://github.com/noctalia-dev/noctalia-plugins",
              "enabled": true
            }
          ];
      // Scan for installed plugins
      root.scanPluginFolder();
    }
  }

  Component.onCompleted: {
    ensurePluginsDirectory();
    ensurePluginsFile();
  }

  function init() {
    Logger.d("PluginRegistry", "Initialized");
    // Force instantiation of PluginService to set up signal listener
    PluginService.initialized;
  }

  // Ensure plugins directory exists
  function ensurePluginsDirectory() {
    var mkdirProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["mkdir", "-p", "${root.pluginsDir}"]
      }
    `, root, "MkdirPlugins");

    mkdirProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        Logger.d("PluginRegistry", "Plugins directory ensured:", root.pluginsDir);
      } else {
        Logger.e("PluginRegistry", "Failed to create plugins directory");
      }
      mkdirProcess.destroy();
    });

    mkdirProcess.running = true;
  }

  // Ensure plugins.json exists (create minimal one if it doesn't)
  function ensurePluginsFile() {
    var checkProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "test -f '${root.pluginsFile}' || echo '{\\"version\\":1,\\"states\\":{},\\"sources\\":[]}' > '${root.pluginsFile}'"]
      }
    `, root, "EnsurePluginsFile");

    checkProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        Logger.d("PluginRegistry", "Plugins file ensured:", root.pluginsFile);
      }
      checkProcess.destroy();
    });

    checkProcess.running = true;
  }

  // Scan plugin folder to discover installed plugins
  function scanPluginFolder() {
    Logger.i("PluginRegistry", "Scanning plugin folder:", root.pluginsDir);

    var lsProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "ls -1 '${root.pluginsDir}' 2>/dev/null || true"]
        stdout: StdioCollector {}
        running: true
      }
    `, root, "ScanPlugins");

    lsProcess.exited.connect(function (exitCode) {
      var output = String(lsProcess.stdout.text || "");
      var pluginDirs = output.trim().split('\n').filter(function (dir) {
        return dir.length > 0;
      });

      Logger.i("PluginRegistry", "Found", pluginDirs.length, "potential plugin directories");

      if (pluginDirs.length === 0) {
        // No plugins to load, emit signal immediately
        root.pluginsChanged();
        lsProcess.destroy();
        return;
      }

      // Track how many manifests we're loading
      root.pendingManifests = pluginDirs.length;
      Logger.i("PluginRegistry", "Starting to load", root.pendingManifests, "manifests");

      // Load each manifest
      for (var i = 0; i < pluginDirs.length; i++) {
        loadPluginManifest(pluginDirs[i]);
      }

      lsProcess.destroy();
    });
  }

  // Load a single plugin's manifest from disk
  function loadPluginManifest(pluginId) {
    var manifestPath = root.pluginsDir + "/" + pluginId + "/manifest.json";

    var catProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${manifestPath}"]
        stdout: StdioCollector {}
        running: true
      }
    `, root, "LoadManifest_" + pluginId);

    catProcess.exited.connect(function (exitCode) {
      var output = String(catProcess.stdout.text || "");
      if (exitCode === 0 && output) {
        try {
          var manifest = JSON.parse(output);
          var validation = validateManifest(manifest);

          if (validation.valid) {
            root.installedPlugins[pluginId] = manifest;
            Logger.i("PluginRegistry", "Loaded plugin:", pluginId, "-", manifest.name);

            // Ensure state exists (default to disabled)
            if (!root.pluginStates[pluginId]) {
              root.pluginStates[pluginId] = {
                enabled: false
              };
            }
          } else {
            Logger.e("PluginRegistry", "Invalid manifest for", pluginId + ":", validation.error);
          }
        } catch (e) {
          Logger.e("PluginRegistry", "Failed to parse manifest for", pluginId + ":", e.toString());
        }
      } else {
        Logger.d("PluginRegistry", "No manifest found for:", pluginId);
      }

      // Decrement pending count and emit signal when all are done
      root.pendingManifests--;
      Logger.d("PluginRegistry", "Pending manifests remaining:", root.pendingManifests);
      if (root.pendingManifests === 0) {
        var installedIds = Object.keys(root.installedPlugins);
        Logger.i("PluginRegistry", "All plugin manifests loaded. Total plugins:", installedIds.length);
        Logger.d("PluginRegistry", "Installed plugin IDs:", JSON.stringify(installedIds));
        root.pluginsChanged();
      }

      catProcess.destroy();
    });
  }

  // Save registry to disk (only states and sources)
  function save() {
    adapter.states = root.pluginStates;
    adapter.sources = root.pluginSources;

    Qt.callLater(() => {
                   pluginsFileView.writeAdapter();
                   Logger.d("PluginRegistry", "Plugin states saved");
                 });
  }

  // Enable/disable a plugin
  function setPluginEnabled(pluginId, enabled) {
    if (!root.installedPlugins[pluginId]) {
      Logger.w("PluginRegistry", "Cannot set state for non-existent plugin:", pluginId);
      return;
    }

    if (!root.pluginStates[pluginId]) {
      root.pluginStates[pluginId] = {
        enabled: enabled
      };
    } else {
      root.pluginStates[pluginId].enabled = enabled;
    }

    save();
    root.pluginsChanged();
    Logger.i("PluginRegistry", "Plugin", pluginId, enabled ? "enabled" : "disabled");
  }

  // Check if plugin is enabled
  function isPluginEnabled(pluginId) {
    return root.pluginStates[pluginId]?.enabled || false;
  }

  // Check if plugin is downloaded/installed
  function isPluginDownloaded(pluginId) {
    return pluginId in root.installedPlugins;
  }

  // Get plugin manifest from cache
  function getPluginManifest(pluginId) {
    return root.installedPlugins[pluginId] || null;
  }

  // Get ALL installed plugin IDs (discovered from disk)
  function getAllInstalledPluginIds() {
    return Object.keys(root.installedPlugins);
  }

  // Get enabled plugin IDs only
  function getEnabledPluginIds() {
    return Object.keys(root.pluginStates).filter(function (id) {
      return root.pluginStates[id].enabled === true;
    });
  }

  // Register a plugin (add to installed plugins after download)
  function registerPlugin(manifest) {
    var pluginId = manifest.id;
    root.installedPlugins[pluginId] = manifest;

    // Ensure state exists (default to disabled)
    if (!root.pluginStates[pluginId]) {
      root.pluginStates[pluginId] = {
        enabled: false
      };
    }

    save();
    root.pluginsChanged();
    Logger.i("PluginRegistry", "Registered plugin:", pluginId);
  }

  // Unregister a plugin (remove from registry)
  function unregisterPlugin(pluginId) {
    delete root.pluginStates[pluginId];
    delete root.installedPlugins[pluginId];
    save();
    root.pluginsChanged();
    Logger.i("PluginRegistry", "Unregistered plugin:", pluginId);
  }

  // Remove plugin state (call after deleting plugin folder)
  function removePluginState(pluginId) {
    delete root.pluginStates[pluginId];
    delete root.installedPlugins[pluginId];
    save();
    root.pluginsChanged();
    Logger.i("PluginRegistry", "Removed plugin state:", pluginId);
  }

  // Add a plugin source
  function addPluginSource(name, url) {
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url === url) {
        Logger.w("PluginRegistry", "Source already exists:", url);
        return false;
      }
    }

    // Create a new array to trigger property change notification
    var newSources = root.pluginSources.slice();
    newSources.push({
                      name: name,
                      url: url,
                      enabled: true
                    });
    root.pluginSources = newSources;
    save();
    Logger.i("PluginRegistry", "Added plugin source:", name);
    return true;
  }

  // Remove a plugin source
  function removePluginSource(url) {
    var newSources = [];
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url !== url) {
        newSources.push(root.pluginSources[i]);
      }
    }

    if (newSources.length === root.pluginSources.length) {
      Logger.w("PluginRegistry", "Source not found:", url);
      return false;
    }

    root.pluginSources = newSources;
    save();
    Logger.i("PluginRegistry", "Removed plugin source:", url);
    return true;
  }

  // Set source enabled/disabled state
  function setSourceEnabled(url, enabled) {
    var newSources = [];
    var found = false;
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url === url) {
        newSources.push({
                          name: root.pluginSources[i].name,
                          url: root.pluginSources[i].url,
                          enabled: enabled
                        });
        found = true;
      } else {
        newSources.push(root.pluginSources[i]);
      }
    }

    if (!found) {
      Logger.w("PluginRegistry", "Source not found:", url);
      return false;
    }

    root.pluginSources = newSources;
    save();
    Logger.i("PluginRegistry", "Source", url, enabled ? "enabled" : "disabled");
    return true;
  }

  // Check if source is enabled
  function isSourceEnabled(url) {
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url === url) {
        return root.pluginSources[i].enabled !== false; // Default to true if not set
      }
    }
    return false;
  }

  // Get enabled sources only
  function getEnabledSources() {
    var enabledSources = [];
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].enabled !== false) {
        enabledSources.push(root.pluginSources[i]);
      }
    }
    return enabledSources;
  }

  // Get plugin directory path
  function getPluginDir(pluginId) {
    return root.pluginsDir + "/" + pluginId;
  }

  // Get plugin settings file path
  function getPluginSettingsFile(pluginId) {
    return getPluginDir(pluginId) + "/settings.json";
  }

  // Validate manifest
  function validateManifest(manifest) {
    if (!manifest) {
      return {
        valid: false,
        error: "Manifest is null or undefined"
      };
    }

    var required = ["id", "name", "version", "author", "description"];
    for (var i = 0; i < required.length; i++) {
      if (!manifest[required[i]]) {
        return {
          valid: false,
          error: "Missing required field: " + required[i]
        };
      }
    }

    if (!manifest.entryPoints) {
      return {
        valid: false,
        error: "Missing 'entryPoints' field"
      };
    }

    // Check version format (simple x.y.z check)
    var versionRegex = /^\d+\.\d+\.\d+$/;
    if (!versionRegex.test(manifest.version)) {
      return {
        valid: false,
        error: "Invalid version format (must be x.y.z)"
      };
    }

    return {
      valid: true,
      error: null
    };
  }
}
