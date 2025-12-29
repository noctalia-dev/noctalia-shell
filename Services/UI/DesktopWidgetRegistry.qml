pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets.Widgets
import qs.Services.Noctalia

Singleton {
  id: root

  // Transient state - not persisted, resets on shell restart
  property bool editMode: false

  // Signal emitted when plugin widgets are registered/unregistered
  signal pluginWidgetRegistryUpdated

  // Component definitions
  property Component clockComponent: Component {
    DesktopClock {}
  }
  property Component mediaPlayerComponent: Component {
    DesktopMediaPlayer {}
  }
  property Component weatherComponent: Component {
    DesktopWeather {}
  }

  // Widget registry object mapping widget names to components
  // Created in Component.onCompleted to ensure Components are ready
  property var widgets: ({})

  Component.onCompleted: {
    // Initialize widgets object after Components are ready
    var widgetsObj = {};
    widgetsObj["Clock"] = clockComponent;
    widgetsObj["MediaPlayer"] = mediaPlayerComponent;
    widgetsObj["Weather"] = weatherComponent;
    widgets = widgetsObj;

    Logger.i("DesktopWidgetRegistry", "Service started");
    Logger.d("DesktopWidgetRegistry", "Available widgets:", Object.keys(widgets));
    Logger.d("DesktopWidgetRegistry", "Clock component:", clockComponent ? "exists" : "null");
    Logger.d("DesktopWidgetRegistry", "MediaPlayer component:", mediaPlayerComponent ? "exists" : "null");
    Logger.d("DesktopWidgetRegistry", "Weather component:", weatherComponent ? "exists" : "null");
    Logger.d("DesktopWidgetRegistry", "Widgets object keys:", Object.keys(widgets));
    Logger.d("DesktopWidgetRegistry", "Widgets object values check - Clock:", widgets["Clock"] ? "exists" : "null");
  }

  property var widgetSettingsMap: ({
                                     "Clock": "WidgetSettings/ClockSettings.qml",
                                     "MediaPlayer": "WidgetSettings/MediaPlayerSettings.qml",
                                     "Weather": "WidgetSettings/WeatherSettings.qml"
                                   })

  property var widgetMetadata: ({
                                  "Clock": {
                                    "showBackground": true,
                                    "clockStyle": "digital",
                                    "usePrimaryColor": false,
                                    "useCustomFont": false,
                                    "format": "HH:mm\\nd MMMM yyyy"
                                  },
                                  "MediaPlayer": {
                                    "showBackground": true,
                                    "visualizerType": "linear",
                                    "hideMode": "visible",
                                    "showButtons": true,
                                    "showAlbumArt": true,
                                    "showVisualizer": true,
                                    "roundedCorners": true
                                  },
                                  "Weather": {
                                    "showBackground": true
                                  }
                                })

  // Plugin widget storage (mirroring BarWidgetRegistry pattern)
  property var pluginWidgets: ({})
  property var pluginWidgetMetadata: ({})

  function init() {
    Logger.i("DesktopWidgetRegistry", "Service started");
  }

  // Helper function to get widget component by name
  function getWidget(id) {
    return widgets[id] || null;
  }

  // Helper function to check if widget exists
  function hasWidget(id) {
    return id in widgets;
  }

  // Get list of available widget ids
  function getAvailableWidgets() {
    var keys = Object.keys(widgets);
    Logger.d("DesktopWidgetRegistry", "getAvailableWidgets() called, returning:", keys);
    return keys;
  }

  // Helper function to check if widget has user settings
  function widgetHasUserSettings(id) {
    return widgetMetadata[id] !== undefined;
  }

  // Check if a widget is a plugin widget
  function isPluginWidget(id) {
    return id.startsWith("plugin:");
  }

  // Get list of plugin widget IDs
  function getPluginWidgets() {
    return Object.keys(pluginWidgets);
  }

  // Get display name for a widget ID
  function getWidgetDisplayName(widgetId) {
    if (widgetId.startsWith("plugin:")) {
      var pluginId = widgetId.replace("plugin:", "");
      var manifest = PluginRegistry.getPluginManifest(pluginId);
      return manifest ? manifest.name : pluginId;
    }
    // Core widgets - return as-is (Clock, MediaPlayer, Weather)
    return widgetId;
  }

  // Register a plugin desktop widget
  function registerPluginWidget(pluginId, component, metadata) {
    if (!pluginId || !component) {
      Logger.e("DesktopWidgetRegistry", "Cannot register plugin widget: invalid parameters");
      return false;
    }

    var widgetId = "plugin:" + pluginId;

    // Create new objects to trigger QML property change detection
    var newPluginWidgets = Object.assign({}, pluginWidgets);
    newPluginWidgets[widgetId] = component;
    pluginWidgets = newPluginWidgets;

    var newPluginMetadata = Object.assign({}, pluginWidgetMetadata);
    newPluginMetadata[widgetId] = metadata || {};
    pluginWidgetMetadata = newPluginMetadata;

    // Also add to main widgets object for unified access - reassign to trigger change
    var newWidgets = Object.assign({}, widgets);
    newWidgets[widgetId] = component;
    widgets = newWidgets;

    var newMetadata = Object.assign({}, widgetMetadata);
    newMetadata[widgetId] = Object.assign({}, {
                                            "showBackground": true
                                          }, metadata || {});
    widgetMetadata = newMetadata;

    Logger.i("DesktopWidgetRegistry", "Registered plugin widget:", widgetId);
    root.pluginWidgetRegistryUpdated();
    return true;
  }

  // Unregister a plugin desktop widget
  function unregisterPluginWidget(pluginId) {
    var widgetId = "plugin:" + pluginId;

    if (!pluginWidgets[widgetId]) {
      Logger.w("DesktopWidgetRegistry", "Plugin widget not registered:", widgetId);
      return false;
    }

    // Create new objects without the widget to trigger QML property change detection
    var newPluginWidgets = Object.assign({}, pluginWidgets);
    delete newPluginWidgets[widgetId];
    pluginWidgets = newPluginWidgets;

    var newPluginMetadata = Object.assign({}, pluginWidgetMetadata);
    delete newPluginMetadata[widgetId];
    pluginWidgetMetadata = newPluginMetadata;

    var newWidgets = Object.assign({}, widgets);
    delete newWidgets[widgetId];
    widgets = newWidgets;

    var newMetadata = Object.assign({}, widgetMetadata);
    delete newMetadata[widgetId];
    widgetMetadata = newMetadata;

    Logger.i("DesktopWidgetRegistry", "Unregistered plugin widget:", widgetId);
    root.pluginWidgetRegistryUpdated();
    return true;
  }
}
