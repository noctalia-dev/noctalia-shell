pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../../Helpers/sha256.js" as Crypto
import qs.Commons

Singleton {
  id: root

  readonly property string pluginsDir: Settings.configDir + "plugins"
  readonly property string pluginsFile: Settings.configDir + "plugins.json"

  // Main source URL - plugins from this source keep plain IDs
  readonly property string mainSourceUrl: "https://github.com/noctalia-dev/noctalia-plugins"

  Component.onCompleted: {
    ensurePluginsDirectory();
    ensurePluginsFile();
  }

  // Generate a short hash (6 characters) from a source URL
  function generateSourceHash(sourceUrl) {
    var hash = Crypto.sha256(sourceUrl);
    return hash.substring(0, 6);
  }

  // Check if a source is the main Noctalia plugins repository
  function isMainSource(sourceUrl) {
    return sourceUrl === root.mainSourceUrl;
  }

  // Generate composite key: plain ID for official, "hash:id" for custom
  function generateCompositeKey(pluginId, sourceUrl) {
    if (!sourceUrl || isMainSource(sourceUrl)) {
      return pluginId;
    }
    var hash = generateSourceHash(sourceUrl);
    return hash + ":" + pluginId;
  }

  // Parse composite key back to components
  function parseCompositeKey(compositeKey) {
    var colonIndex = compositeKey.indexOf(":");
    // If no colon or colon is after position 6 (hash length), it's a plain ID
    if (colonIndex === -1 || colonIndex > 6) {
      return {
        sourceHash: null,
        pluginId: compositeKey,
        isOfficial: true
      };
    }
    // Has hash prefix (custom source plugin)
    return {
      sourceHash: compositeKey.substring(0, colonIndex),
      pluginId: compositeKey.substring(colonIndex + 1),
      isOfficial: false
    };
  }

  // Get source name by URL
  function getSourceNameByUrl(sourceUrl) {
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url === sourceUrl) {
        return root.pluginSources[i].name;
      }
    }
    return null;
  }

  // Get source name by hash
  function getSourceNameByHash(hash) {
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (generateSourceHash(root.pluginSources[i].url) === hash) {
        return root.pluginSources[i].name;
      }
    }
    return null;
  }

  // Get source URL from plugin state
  function getPluginSourceUrl(compositeKey) {
    var state = root.pluginStates[compositeKey];
    return state?.sourceUrl || root.mainSourceUrl;
  }

  // Signals
  signal pluginsChanged

  // In-memory plugin cache (populated by scanning disk)
  property var installedPlugins: ({}) // { pluginId: manifest }
  property var pluginStates: ({}) // { pluginId: { enabled: bool } }
  property var pluginSources: [] // Array of { name, url }
  property var pluginLoadVersions: ({}) // { pluginId: versionNumber } - for cache busting

  // Track async loading
  property int pendingManifests: 0

  // File storage (minimal - only states and sources)
  property FileView pluginsFileView: FileView {
    id: pluginsFileView
    path: root.pluginsFile

    adapter: JsonAdapter {
      id: adapter
      property int version: 2 // v2 adds sourceUrl to states
      property var states: ({})
      property list<var> sources: []
    }

    onLoaded: {
      Logger.i("PluginRegistry", "Loaded plugin states from:", path);
      root.pluginStates = adapter.states || {};
      root.pluginSources = adapter.sources || [];

      // Ensure default repo is in sources
      if (root.pluginSources.length === 0) {
        root.pluginSources = [
          {
            "name": "Noctalia Plugins",
            "url": "https://github.com/noctalia-dev/noctalia-plugins",
            "enabled": true
          }
        ];
        root.save();
      }

      // Migrate from v1 to v2 (add sourceUrl to states)
      root.migratePluginData();

      // Scan plugin folder to discover installed plugins
      scanPluginFolder();
    }

    onLoadFailed: function (error) {
      Logger.w("PluginRegistry", "Failed to load plugins.json, will create it:", error);
      // Initialize defaults and continue
      root.pluginStates = {};
      root.pluginSources = [
            {
              "name": "Noctalia Plugins",
              "url": "https://github.com/noctalia-dev/noctalia-plugins",
              "enabled": true
            }
          ];
      // Scan for installed plugins
      root.scanPluginFolder();
    }
  }

  function init() {
    Logger.d("PluginRegistry", "Initialized");
    // Force instantiation of PluginService to set up signal listener
    PluginService.initialized;
  }

  // Migrate plugin data from older versions
  function migratePluginData() {
    var needsSave = false;

    // Migration v1 -> v2: add sourceUrl to states
    for (var pluginId in root.pluginStates) {
      if (root.pluginStates[pluginId].sourceUrl === undefined) {
        Logger.i("PluginRegistry", "Migrating plugin data to v2 (adding sourceUrl)");

        var newStates = {};
        for (var id in root.pluginStates) {
          // For v1 -> v2 migration, we assume plugins are from main source
          // Custom plugins installed before this feature need to be reinstalled
          newStates[id] = {
            enabled: root.pluginStates[id].enabled,
            sourceUrl: root.mainSourceUrl
          };
        }
        root.pluginStates = newStates;
        needsSave = true;
        break;
      }
    }

    // Migration: rename "Official Noctalia Plugins" -> "Noctalia Plugins"
    var newSources = [];
    var sourcesChanged = false;
    for (var i = 0; i < root.pluginSources.length; i++) {
      var source = root.pluginSources[i];
      if (source.name === "Official Noctalia Plugins") {
        newSources.push({
                          name: "Noctalia Plugins",
                          url: source.url,
                          enabled: source.enabled
                        });
        sourcesChanged = true;
        Logger.i("PluginRegistry", "Migrating source name: 'Official Noctalia Plugins' -> 'Noctalia Plugins'");
      } else {
        newSources.push(source);
      }
    }
    if (sourcesChanged) {
      root.pluginSources = newSources;
      needsSave = true;
    }

    if (needsSave) {
      root.save();
      Logger.i("PluginRegistry", "Migration complete");
    }
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
  // sourceUrl is required for new plugins to generate composite key
  function registerPlugin(manifest, sourceUrl) {
    var compositeKey = generateCompositeKey(manifest.id, sourceUrl);
    root.installedPlugins[compositeKey] = manifest;

    // Ensure state exists (default to disabled, store sourceUrl)
    if (!root.pluginStates[compositeKey]) {
      root.pluginStates[compositeKey] = {
        enabled: false,
        sourceUrl: sourceUrl || root.mainSourceUrl
      };
    } else {
      // Preserve enabled state but update sourceUrl
      root.pluginStates[compositeKey].sourceUrl = sourceUrl || root.mainSourceUrl;
    }

    save();
    root.pluginsChanged();
    Logger.i("PluginRegistry", "Registered plugin:", compositeKey);
    return compositeKey;
  }

  // Unregister a plugin (remove from registry)
  function unregisterPlugin(pluginId) {
    delete root.pluginStates[pluginId];
    delete root.installedPlugins[pluginId];
    save();
    root.pluginsChanged();
    Logger.i("PluginRegistry", "Unregistered plugin:", pluginId);
  }

  // Increment plugin load version (for cache busting when plugin is updated)
  function incrementPluginLoadVersion(pluginId) {
    var versions = Object.assign({}, root.pluginLoadVersions);
    versions[pluginId] = (versions[pluginId] || 0) + 1;
    root.pluginLoadVersions = versions;
    Logger.d("PluginRegistry", "Incremented load version for", pluginId, "to", versions[pluginId]);
    return versions[pluginId];
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
