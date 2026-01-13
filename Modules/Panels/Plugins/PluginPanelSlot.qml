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

  // ===== KEYBOARD EVENT FORWARDING =====
  // Helper function to safely retrieve a handler function from the plugin instance
  function getHandler(funcName) {
    // Check if instance exists and has the function
    if (root.pluginInstance && typeof root.pluginInstance[funcName] === "function") {
      // Return a wrapper that calls the function on the instance
      return function() { root.pluginInstance[funcName]() }
    }
    return undefined;
  }

  // Standard Navigation
  property var onTabPressed: root.pluginInstance ? getHandler("onTabPressed") : undefined
  property var onBackTabPressed: root.pluginInstance ? getHandler("onBackTabPressed") : undefined
  property var onUpPressed: root.pluginInstance ? getHandler("onUpPressed") : undefined
  property var onDownPressed: root.pluginInstance ? getHandler("onDownPressed") : undefined
  property var onLeftPressed: root.pluginInstance ? getHandler("onLeftPressed") : undefined
  property var onRightPressed: root.pluginInstance ? getHandler("onRightPressed") : undefined
  property var onReturnPressed: root.pluginInstance ? getHandler("onReturnPressed") : undefined

  // Vim Navigation
  property var onHPressed: root.pluginInstance ? getHandler("onHPressed") : undefined
  property var onJPressed: root.pluginInstance ? getHandler("onJPressed") : undefined
  property var onKPressed: root.pluginInstance ? getHandler("onKPressed") : undefined
  property var onLPressed: root.pluginInstance ? getHandler("onLPressed") : undefined

  // Panel content is dynamically loaded
  panelContent: Component {
    Item {
      id: panelContainer

      // Required by SmartPanel for background rendering geometry
      readonly property var geometryPlaceholder: pluginContentItem

      // Panel properties expected by SmartPanel
      readonly property bool allowAttach: (pluginContentLoader.item && pluginContentLoader.item.allowAttach !== undefined) ? pluginContentLoader.item.allowAttach : true
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

    var pluginDir = PluginRegistry.getPluginDir(pluginId);
    var panelPath = pluginDir + "/" + plugin.manifest.entryPoints.panel;

    Logger.i("PluginPanelSlot", "Loading panel for plugin:", pluginId, "in slot", root.slotNumber);

    // Load the panel component with cache-busting version parameter
    var loadVersion = PluginRegistry.pluginLoadVersions[pluginId] || 0;
    var component = Qt.createComponent("file://" + panelPath + "?v=" + loadVersion);

    if (component.status === Component.Ready) {
      // Get plugin API
      var api = PluginService.getPluginAPI(pluginId);

      // Activate loader and set component simultaneously
      root.contentLoader.active = true;
      root.contentLoader.sourceComponent = component;

      // Immediately inject API (before any bindings evaluate)
      if (root.contentLoader.item) {
        if (root.contentLoader.item.hasOwnProperty("pluginApi")) {
          root.contentLoader.item.pluginApi = api;
        }

        root.pluginInstance = root.contentLoader.item;
        root.currentPluginId = pluginId;

        Logger.i("PluginPanelSlot", "Panel loaded for:", pluginId);
        return true;
      }
    } else if (component.status === Component.Error) {
      PluginService.recordPluginError(pluginId, "panel", component.errorString());
      return false;
    }

    return false;
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
  }
}
