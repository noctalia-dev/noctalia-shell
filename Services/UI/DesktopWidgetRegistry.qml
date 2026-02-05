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
  property Component systemStatComponent: Component {
    DesktopSystemStat {}
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
    widgetsObj["SystemStat"] = systemStatComponent;
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
                                     "Weather": "WidgetSettings/WeatherSettings.qml",
                                     "SystemStat": "WidgetSettings/SystemStatSettings.qml"
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
                                  },
                                  "SystemStat": {
                                    "showBackground": true,
                                    "statType": "CPU",
                                    "diskPath": "/",
                                    "roundedCorners": true,
                                    "layout": "bottom"
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
    // Core widgets - return as-is (Clock, MediaPlayer, Weather, SystemStat)
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

  function updateWidgetData(monitorName, widgetIndex, properties) {
    if (widgetIndex < 0 || !monitorName) {
      return;
    }

    var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
    var newMonitorWidgets = monitorWidgets.slice();

    for (var i = 0; i < newMonitorWidgets.length; i++) {
      if (newMonitorWidgets[i].name === monitorName) {
        var widgets = (newMonitorWidgets[i].widgets || []).slice();
        if (widgetIndex < widgets.length) {
          widgets[widgetIndex] = Object.assign({}, widgets[widgetIndex], properties);
          newMonitorWidgets[i] = Object.assign({}, newMonitorWidgets[i], {
                                                 "widgets": widgets
                                               });
          Settings.data.desktopWidgets.monitorWidgets = newMonitorWidgets;
        }
        break;
      }
    }
  }

  property var currentSettingsDialog: null

  function openWidgetSettings(screen, widgetIndex, widgetId, widgetData) {
    if (!widgetId || !screen) {
      return;
    }

    if (root.currentSettingsDialog) {
      root.currentSettingsDialog.close();
      root.currentSettingsDialog.destroy();
      root.currentSettingsDialog = null;
    }

    var hasSettings = false;
    if (root.isPluginWidget(widgetId)) {
      var pluginId = widgetId.replace("plugin:", "");
      var manifest = PluginRegistry.getPluginManifest(pluginId);
      if (manifest && manifest.entryPoints && manifest.entryPoints.settings) {
        hasSettings = true;
      }
    } else {
      hasSettings = root.widgetSettingsMap[widgetId] !== undefined;
    }

    if (!hasSettings) {
      Logger.w("DesktopWidgetRegistry", "Widget does not have settings:", widgetId);
      return;
    }

    var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
    if (!popupMenuWindow) {
      Logger.e("DesktopWidgetRegistry", "No popup menu window found for screen");
      return;
    }

    if (popupMenuWindow.hideDynamicMenu) {
      popupMenuWindow.hideDynamicMenu();
    }

    var component = Qt.createComponent(Quickshell.shellDir + "/Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml");

    function instantiateAndOpen() {
      var dialog = component.createObject(popupMenuWindow.dialogParent, {
                                            "widgetIndex": widgetIndex,
                                            "widgetData": widgetData,
                                            "widgetId": widgetId,
                                            "sectionId": screen.name,
                                            "screen": screen
                                          });

      if (dialog) {
        root.currentSettingsDialog = dialog;
        dialog.updateWidgetSettings.connect((sec, idx, settings) => {
                                              root.updateWidgetData(sec, idx, settings);
                                            });
        popupMenuWindow.hasDialog = true;
        dialog.closed.connect(() => {
                                popupMenuWindow.hasDialog = false;
                                popupMenuWindow.close();
                                if (root.currentSettingsDialog === dialog) {
                                  root.currentSettingsDialog = null;
                                }
                                dialog.destroy();
                              });
        dialog.open();
      } else {
        Logger.e("DesktopWidgetRegistry", "Failed to create widget settings dialog");
      }
    }

    if (component.status === Component.Ready) {
      instantiateAndOpen();
    } else if (component.status === Component.Error) {
      Logger.e("DesktopWidgetRegistry", "Error loading settings dialog component:", component.errorString());
    } else {
      component.statusChanged.connect(() => {
                                        if (component.status === Component.Ready) {
                                          instantiateAndOpen();
                                        } else if (component.status === Component.Error) {
                                          Logger.e("DesktopWidgetRegistry", "Error loading settings dialog component:", component.errorString());
                                        }
                                      });
    }
  }
}
