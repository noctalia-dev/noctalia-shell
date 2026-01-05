pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Panels.ControlCenter.Widgets

Singleton {
  id: root

  // Widget registry object mapping widget names to components
  property var widgets: ({
                           "Bluetooth": bluetoothComponent,
                           "CustomButton": customButtonComponent,
                           "DarkMode": darkModeComponent,
                           "KeepAwake": keepAwakeComponent,
                           "NightLight": nightLightComponent,
                           "Notifications": notificationsComponent,
                           "PowerProfile": powerProfileComponent,
                           "ScreenRecorder": screenRecorderComponent,
                           "WiFi": networkComponent,
                           "Network": networkComponent,
                           "WallpaperSelector": wallpaperSelectorComponent
                         })

  property var widgetMetadata: ({
                                  "CustomButton": {
                                    "icon": "heart",
                                    "onClicked": "",
                                    "onRightClicked": "",
                                    "onMiddleClicked": "",
                                    "stateChecks": [],
                                    "generalTooltipText": "Custom Button",
                                    "enableOnStateLogic": false
                                  }
                                })

  // Component definitions - these are loaded once at startup
  property Component bluetoothComponent: Component {
    Bluetooth {}
  }
  property Component customButtonComponent: Component {
    CustomButton {}
  }
  property Component darkModeComponent: Component {
    DarkMode {}
  }
  property Component keepAwakeComponent: Component {
    KeepAwake {}
  }
  property Component nightLightComponent: Component {
    NightLight {}
  }
  property Component notificationsComponent: Component {
    Notifications {}
  }
  property Component powerProfileComponent: Component {
    PowerProfile {}
  }
  property Component screenRecorderComponent: Component {
    ScreenRecorder {}
  }
  property Component networkComponent: Component {
    Network {}
  }
  property Component wallpaperSelectorComponent: Component {
    WallpaperSelector {}
  }

  function init() {
    Logger.i("ControlCenterWidgetRegistry", "Service started");
  }

  // ------------------------------
  // Helper function to get widget component by name
  function getWidget(id) {
    return widgets[id] || null;
  }

  // Helper function to check if widget exists
  function hasWidget(id) {
    return id in widgets;
  }

  // Get list of available widget id
  function getAvailableWidgets() {
    return Object.keys(widgets);
  }

  // Helper function to check if widget has user settings
  function widgetHasUserSettings(id) {
    return widgetMetadata[id] !== undefined;
  }

  // ------------------------------
  // Plugin widget registration

  // Track plugin widgets separately
  property var pluginWidgets: ({})
  property var pluginWidgetMetadata: ({})

  // Register a plugin widget
  function registerPluginWidget(pluginId, component, metadata) {
    if (!pluginId || !component) {
      Logger.e("ControlCenterWidgetRegistry", "Cannot register plugin widget: invalid parameters");
      return false;
    }

    // Add plugin: prefix to avoid conflicts with core widgets
    var widgetId = "plugin:" + pluginId;

    pluginWidgets[widgetId] = component;
    pluginWidgetMetadata[widgetId] = metadata || {};

    // Also add to main widgets object for unified access
    widgets[widgetId] = component;
    widgetMetadata[widgetId] = metadata || {};

    Logger.i("ControlCenterWidgetRegistry", "Registered plugin widget:", widgetId);
    return true;
  }

  // Unregister a plugin widget
  function unregisterPluginWidget(pluginId) {
    var widgetId = "plugin:" + pluginId;

    if (!pluginWidgets[widgetId]) {
      Logger.w("ControlCenterWidgetRegistry", "Plugin widget not registered:", widgetId);
      return false;
    }

    delete pluginWidgets[widgetId];
    delete pluginWidgetMetadata[widgetId];
    delete widgets[widgetId];
    delete widgetMetadata[widgetId];

    Logger.i("ControlCenterWidgetRegistry", "Unregistered plugin widget:", widgetId);
    return true;
  }

  // Check if a widget is a plugin widget
  function isPluginWidget(id) {
    return id.startsWith("plugin:");
  }

  // Get list of plugin widget IDs
  function getPluginWidgets() {
    return Object.keys(pluginWidgets);
  }
}
