import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Noctalia
import qs.Services.UI

/**
* Generic plugin panel slot that can be reused for different plugins
*/
SmartPanel {
  id: root

  // Which plugin slot this is (1 or 2)
  property int slotNumber: 1

  // Currently loaded plugin ID (empty if no plugin using this slot)
  property string currentPluginId: ""

  // Plugin instance
  property var pluginInstance: null

  // Reference to the plugin content loader (set when panel content is created)
  property var contentLoader: null

  // Pass through anchor properties from plugin panel content
  panelAnchorHorizontalCenter: pluginInstance?.panelAnchorHorizontalCenter ?? false
  panelAnchorVerticalCenter: pluginInstance?.panelAnchorVerticalCenter ?? false
  panelAnchorTop: pluginInstance?.panelAnchorTop ?? false
  panelAnchorBottom: pluginInstance?.panelAnchorBottom ?? false
  panelAnchorLeft: pluginInstance?.panelAnchorLeft ?? false
  panelAnchorRight: pluginInstance?.panelAnchorRight ?? false

  // Panel background color
  panelBackgroundColor: pluginInstance?.panelBackgroundColor ?? Color.mSurface

  // Panel content is dynamically loaded
  panelContent: Component {
    Item {
      id: panelContainer

      // Required by SmartPanel for background rendering geometry
      readonly property var geometryPlaceholder: pluginContentItem

      // Panel properties expected by SmartPanel
      // A plugin can opt out of attachment (allowAttach: false) but cannot override
      // the global "attach panels to bar" setting — if that setting is off, panels
      // stay detached regardless of what the plugin requests.
      readonly property bool allowAttach: {
        var globalAllow = Settings.data.ui.panelsAttachedToBar || root.forceAttachToBar;
        if (!globalAllow)
          return false;
        if (pluginContentLoader.item && pluginContentLoader.item.allowAttach !== undefined)
          return pluginContentLoader.item.allowAttach;
        return globalAllow;
      }
      // Expose preferred dimensions from plugin panel content
      // Only define these if the plugin provides them
      property var contentPreferredWidth: {
        if (pluginContentLoader.item && pluginContentLoader.item.contentPreferredWidth !== undefined && pluginContentLoader.item.contentPreferredWidth > 0) {
          return pluginContentLoader.item.contentPreferredWidth;
        }
        return undefined;
      }

      property var contentPreferredHeight: {
        if (pluginContentLoader.item && pluginContentLoader.item.contentPreferredHeight !== undefined && pluginContentLoader.item.contentPreferredHeight > 0) {
          return pluginContentLoader.item.contentPreferredHeight;
        }
        return undefined;
      }

      anchors.fill: parent

      // Dynamic plugin content
      Item {
        id: pluginContentItem
        anchors.fill: parent

        // Plugin content loader, pluginApi is injected synchronously in loadPluginPanel()
        Loader {
          id: pluginContentLoader
          anchors.fill: parent
          active: false
        }
      }

      Component.onCompleted: {
        // Store reference to the loader so loadPluginPanel can access it
        root.contentLoader = pluginContentLoader;

        // Load plugin panel content if assigned
        if (root.currentPluginId !== "") {
          root.loadPluginPanel(root.currentPluginId);
        }
      }
    }
  }

  // Load a plugin's panel content
  function loadPluginPanel(pluginId) {
    if (!PluginService.isPluginLoaded(pluginId)) {
      Logger.w("PluginPanelSlot", "Plugin not loaded:", pluginId);
      return false;
    }

    var plugin = PluginService.loadedPlugins[pluginId];
    if (!plugin || !plugin.manifest) {
      Logger.w("PluginPanelSlot", "Plugin data not found:", pluginId);
      return false;
    }

    if (!plugin.manifest.entryPoints || !plugin.manifest.entryPoints.panel) {
      Logger.w("PluginPanelSlot", "Plugin does not provide a panel:", pluginId);
      return false;
    }

    // Check if loader is available
    if (!root.contentLoader) {
      Logger.e("PluginPanelSlot", "Content loader not available yet");
      return false;
    }

    // Clear any stale pluginInstance before loading new content
    root.pluginInstance = null;

    var pluginDir = PluginRegistry.getPluginDir(pluginId);
    var panelPath = pluginDir + "/" + plugin.manifest.entryPoints.panel;

    Logger.i("PluginPanelSlot", "Loading panel for plugin:", pluginId, "in slot", root.slotNumber);

    // Load the panel component with cache-busting version parameter
    var loadVersion = PluginRegistry.pluginLoadVersions[pluginId] || 0;
    var component = Qt.createComponent("file://" + panelPath + "?v=" + loadVersion);

    if (component.status === Component.Ready) {
      finalizePluginLoad(pluginId, component);
      return true;
    } else if (component.status === Component.Loading) {
      // Handle async component loading - wait for it to be ready
      Logger.d("PluginPanelSlot", "Component loading asynchronously for:", pluginId);
      component.statusChanged.connect(function () {
        if (component.status === Component.Ready) {
          finalizePluginLoad(pluginId, component);
          // Force SmartPanel to recalculate position now that content is ready
          if (root.isPanelVisible) {
            root.setPosition();
          }
        } else if (component.status === Component.Error) {
          PluginService.recordPluginError(pluginId, "panel", component.errorString());
        }
      });
      return true; // Will be loaded asynchronously
    } else if (component.status === Component.Error) {
      PluginService.recordPluginError(pluginId, "panel", component.errorString());
      return false;
    }

    return false;
  }

  // Helper function to finalize plugin content loading
  function finalizePluginLoad(pluginId, component) {
    // Get plugin API
    var api = PluginService.getPluginAPI(pluginId);

    // Use setSource with initial properties so pluginApi is available
    // from the first binding evaluation (before onLoaded)
    root.contentLoader.active = true;
    root.contentLoader.setSource(component.url, api ? {
                                                        "pluginApi": api
                                                      } : {});

    if (root.contentLoader.item) {
      root.pluginInstance = root.contentLoader.item;
      root.currentPluginId = pluginId;

      Logger.i("PluginPanelSlot", "Panel loaded for:", pluginId);
    } else {
      Logger.e("PluginPanelSlot", "Failed to get loader item for:", pluginId);
    }
  }

  // Unload current plugin panel
  function unloadPluginPanel() {
    if (root.currentPluginId === "") {
      return;
    }

    Logger.i("PluginPanelSlot", "Unloading panel from slot", root.slotNumber);

    if (root.contentLoader) {
      root.contentLoader.active = false;
      root.contentLoader.sourceComponent = null;
    }
    root.pluginInstance = null;
    root.currentPluginId = "";
  }

  // Register with PanelService
  Component.onCompleted: {
    PanelService.registerPanel(root);
  }

  // Update plugin's panelOpenScreen when this panel opens/closes
  onOpened: {
    if (root.currentPluginId !== "") {
      var api = PluginService.getPluginAPI(root.currentPluginId);
      if (api) {
        api.panelOpenScreen = root.screen;
        Logger.d("PluginPanelSlot", "Set panelOpenScreen for", root.currentPluginId, "to", root.screen?.name);
      }
    }
  }

  onClosed: {
    if (root.currentPluginId !== "") {
      var api = PluginService.getPluginAPI(root.currentPluginId);
      if (api) {
        api.panelOpenScreen = null;
        Logger.d("PluginPanelSlot", "Cleared panelOpenScreen for", root.currentPluginId);
      }
    }
    // Clear stale references when panel closes (content is destroyed by SmartPanel)
    root.pluginInstance = null;
    root.contentLoader = null;
  }
}
