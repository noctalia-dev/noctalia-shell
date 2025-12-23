pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Bar.Widgets

Singleton {
  id: root

  // Signal emitted when plugin widgets are registered/unregistered
  signal pluginWidgetRegistryUpdated

  // Widget registry object mapping widget names to components
  property var widgets: ({
                           "ActiveWindow": activeWindowComponent,
                           "AudioVisualizer": audioVisualizerComponent,
                           "Battery": batteryComponent,
                           "Bluetooth": bluetoothComponent,
                           "Brightness": brightnessComponent,
                           "Clock": clockComponent,
                           "ControlCenter": controlCenterComponent,
                           "CustomButton": customButtonComponent,
                           "DarkMode": darkModeComponent,
                           "KeepAwake": keepAwakeComponent,
                           "KeyboardLayout": keyboardLayoutComponent,
                           "LockKeys": lockKeysComponent,
                           "MediaMini": mediaMiniComponent,
                           "Microphone": microphoneComponent,
                           "NightLight": nightLightComponent,
                           "NoctaliaPerformance": noctaliaPerformanceComponent,
                           "NotificationHistory": notificationHistoryComponent,
                           "PowerProfile": powerProfileComponent,
                           "ScreenRecorder": screenRecorderComponent,
                           "SessionMenu": sessionMenuComponent,
                           "Spacer": spacerComponent,
                           "SystemMonitor": systemMonitorComponent,
                           "Taskbar": taskbarComponent,
                           "Tray": trayComponent,
                           "Volume": volumeComponent,
                           "VPN": vpnComponent,
                           "WiFi": wiFiComponent,
                           "WallpaperSelector": wallpaperSelectorComponent,
                           "Workspace": workspaceComponent
                         })

  property var widgetSettingsMap: ({
                                     "ActiveWindow": "WidgetSettings/ActiveWindowSettings.qml",
                                     "AudioVisualizer": "WidgetSettings/AudioVisualizerSettings.qml",
                                     "Battery": "WidgetSettings/BatterySettings.qml",
                                     "Bluetooth": "WidgetSettings/BluetoothSettings.qml",
                                     "Brightness": "WidgetSettings/BrightnessSettings.qml",
                                     "Clock": "WidgetSettings/ClockSettings.qml",
                                     "ControlCenter": "WidgetSettings/ControlCenterSettings.qml",
                                     "CustomButton": "WidgetSettings/CustomButtonSettings.qml",
                                     "KeyboardLayout": "WidgetSettings/KeyboardLayoutSettings.qml",
                                     "LockKeys": "WidgetSettings/LockKeysSettings.qml",
                                     "MediaMini": "WidgetSettings/MediaMiniSettings.qml",
                                     "Microphone": "WidgetSettings/MicrophoneSettings.qml",
                                     "NotificationHistory": "WidgetSettings/NotificationHistorySettings.qml",
                                     "SessionMenu": "WidgetSettings/SessionMenuSettings.qml",
                                     "Spacer": "WidgetSettings/SpacerSettings.qml",
                                     "SystemMonitor": "WidgetSettings/SystemMonitorSettings.qml",
                                     "Taskbar": "WidgetSettings/TaskbarSettings.qml",
                                     "Tray": "WidgetSettings/TraySettings.qml",
                                     "Volume": "WidgetSettings/VolumeSettings.qml",
                                     "VPN": "WidgetSettings/VPNSettings.qml",
                                     "WiFi": "WidgetSettings/WiFiSettings.qml",
                                     "Workspace": "WidgetSettings/WorkspaceSettings.qml"
                                   })

  property var widgetMetadata: ({
                                  "ActiveWindow": {
                                    "allowUserSettings": true,
                                    "showIcon": true,
                                    "hideMode": "hidden",
                                    "scrollingMode": "hover",
                                    "maxWidth": 145,
                                    "useFixedWidth": false,
                                    "colorizeIcons": false
                                  },
                                  "AudioVisualizer": {
                                    "allowUserSettings": true,
                                    "width": 200,
                                    "colorName": "primary",
                                    "hideWhenIdle": false
                                  },
                                  "Battery": {
                                    "allowUserSettings": true,
                                    "displayMode": "onhover",
                                    "warningThreshold": 30,
                                    "deviceNativePath": "",
                                    "showPowerProfiles": false,
                                    "showNoctaliaPerformance": false,
                                    "hideIfNotDetected": true
                                  },
                                  "Bluetooth": {
                                    "allowUserSettings": true,
                                    "displayMode": "onhover"
                                  },
                                  "Brightness": {
                                    "allowUserSettings": true,
                                    "displayMode": "onhover"
                                  },
                                  "Clock": {
                                    "allowUserSettings": true,
                                    "usePrimaryColor": true,
                                    "useCustomFont": false,
                                    "customFont": "",
                                    "formatHorizontal": "HH:mm ddd, MMM dd",
                                    "formatVertical": "HH mm - dd MM"
                                  },
                                  "ControlCenter": {
                                    "allowUserSettings": true,
                                    "useDistroLogo": false,
                                    "icon": "noctalia",
                                    "customIconPath": "",
                                    "colorizeDistroLogo": false,
                                    "colorizeSystemIcon": "none",
                                    "enableColorization": false
                                  },
                                  "CustomButton": {
                                    "allowUserSettings": true,
                                    "icon": "heart",
                                    "showIcon": true,
                                    "hideMode": "alwaysExpanded",
                                    "leftClickExec": "",
                                    "leftClickUpdateText": false,
                                    "rightClickExec": "",
                                    "rightClickUpdateText": false,
                                    "middleClickExec": "",
                                    "middleClickUpdateText": false,
                                    "textCommand": "",
                                    "textStream": false,
                                    "textIntervalMs": 3000,
                                    "textCollapse": "",
                                    "parseJson": false,
                                    "wheelExec": "",
                                    "wheelUpExec": "",
                                    "wheelDownExec": "",
                                    "wheelMode": "unified",
                                    "wheelUpdateText": false,
                                    "wheelUpUpdateText": false,
                                    "wheelDownUpdateText": false,
                                    "maxTextLength": {
                                      "horizontal": 10,
                                      "vertical": 10
                                    }
                                  },
                                  "KeyboardLayout": {
                                    "allowUserSettings": true,
                                    "displayMode": "onhover"
                                  },
                                  "LockKeys": {
                                    "allowUserSettings": true,
                                    "showCapsLock": true,
                                    "showNumLock": true,
                                    "showScrollLock": true,
                                    "capsLockIcon": "letter-c",
                                    "numLockIcon": "letter-n",
                                    "scrollLockIcon": "letter-s"
                                  },
                                  "MediaMini": {
                                    "allowUserSettings": true,
                                    "hideMode": "hidden",
                                    "scrollingMode": "hover",
                                    "maxWidth": 145,
                                    "useFixedWidth": false,
                                    "hideWhenIdle": false,
                                    "showAlbumArt": false,
                                    "showArtistFirst": true,
                                    "showVisualizer": false,
                                    "showProgressRing": true,
                                    "visualizerType": "linear"
                                  },
                                  "Microphone": {
                                    "allowUserSettings": true,
                                    "displayMode": "onhover"
                                  },
                                  "NotificationHistory": {
                                    "allowUserSettings": true,
                                    "showUnreadBadge": true,
                                    "hideWhenZero": false
                                  },
                                  "SessionMenu": {
                                    "allowUserSettings": true,
                                    "colorName": "error"
                                  },
                                  "Spacer": {
                                    "allowUserSettings": true,
                                    "width": 20
                                  },
                                  "SystemMonitor": {
                                    "allowUserSettings": true,
                                    "usePrimaryColor": false,
                                    "showCpuUsage": true,
                                    "showCpuTemp": true,
                                    "showGpuTemp": false,
                                    "showMemoryUsage": true,
                                    "showMemoryAsPercent": false,
                                    "showNetworkStats": false,
                                    "showDiskUsage": false,
                                    "diskPath": "/"
                                  },
                                  "Taskbar": {
                                    "allowUserSettings": true,
                                    "onlySameOutput": true,
                                    "onlyActiveWorkspaces": true,
                                    "hideMode": "hidden",
                                    "colorizeIcons": false,
                                    "showTitle": false,
                                    "titleWidth": 120,
                                    "showPinnedApps": true,
                                    "smartWidth": true,
                                    "maxTaskbarWidth": 40,
                                    "iconScale": 1.0
                                  },
                                  "Tray": {
                                    "allowUserSettings": true,
                                    "blacklist": [],
                                    "colorizeIcons": false,
                                    "pinned": [],
                                    "drawerEnabled": true,
                                    "hidePassive": false
                                  },
                                  "VPN": {
                                    "allowUserSettings": true,
                                    "displayMode": "onhover"
                                  },
                                  "WiFi": {
                                    "allowUserSettings": true,
                                    "displayMode": "onhover"
                                  },
                                  "Workspace": {
                                    "allowUserSettings": true,
                                    "labelMode": "index",
                                    "followFocusedScreen": false,
                                    "hideUnoccupied": false,
                                    "characterCount": 2,
                                    "showApplications": false,
                                    "showLabelsOnlyWhenOccupied": true,
                                    "colorizeIcons": false,
                                    "enableScrollWheel": true
                                  },
                                  "Volume": {
                                    "allowUserSettings": true,
                                    "displayMode": "onhover"
                                  }
                                })

  // Component definitions - these are loaded once at startup
  property Component activeWindowComponent: Component {
    ActiveWindow {}
  }
  property Component audioVisualizerComponent: Component {
    AudioVisualizer {}
  }
  property Component batteryComponent: Component {
    Battery {}
  }
  property Component bluetoothComponent: Component {
    Bluetooth {}
  }
  property Component brightnessComponent: Component {
    Brightness {}
  }
  property Component clockComponent: Component {
    Clock {}
  }
  property Component customButtonComponent: Component {
    CustomButton {}
  }
  property Component darkModeComponent: Component {
    DarkMode {}
  }
  property Component keyboardLayoutComponent: Component {
    KeyboardLayout {}
  }
  property Component keepAwakeComponent: Component {
    KeepAwake {}
  }
  property Component lockKeysComponent: Component {
    LockKeys {}
  }
  property Component mediaMiniComponent: Component {
    MediaMini {}
  }
  property Component microphoneComponent: Component {
    Microphone {}
  }
  property Component nightLightComponent: Component {
    NightLight {}
  }
  property Component noctaliaPerformanceComponent: Component {
    NoctaliaPerformance {}
  }
  property Component notificationHistoryComponent: Component {
    NotificationHistory {}
  }
  property Component powerProfileComponent: Component {
    PowerProfile {}
  }
  property Component sessionMenuComponent: Component {
    SessionMenu {}
  }
  property Component screenRecorderComponent: Component {
    ScreenRecorder {}
  }
  property Component controlCenterComponent: Component {
    ControlCenter {}
  }
  property Component spacerComponent: Component {
    Spacer {}
  }
  property Component systemMonitorComponent: Component {
    SystemMonitor {}
  }
  property Component trayComponent: Component {
    Tray {}
  }
  property Component volumeComponent: Component {
    Volume {}
  }
  property Component vpnComponent: Component {
    VPN {}
  }
  property Component wiFiComponent: Component {
    WiFi {}
  }
  property Component wallpaperSelectorComponent: Component {
    WallpaperSelector {}
  }
  property Component workspaceComponent: Component {
    Workspace {}
  }
  property Component taskbarComponent: Component {
    Taskbar {}
  }
  function init() {
    Logger.i("BarWidgetRegistry", "Service started");
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
    return (widgetMetadata[id] !== undefined) && (widgetMetadata[id].allowUserSettings === true);
  }

  // ------------------------------
  // Plugin widget registration

  // Track plugin widgets separately
  property var pluginWidgets: ({})
  property var pluginWidgetMetadata: ({})

  // Register a plugin widget
  function registerPluginWidget(pluginId, component, metadata) {
    if (!pluginId || !component) {
      Logger.e("BarWidgetRegistry", "Cannot register plugin widget: invalid parameters");
      return false;
    }

    // Add plugin: prefix to avoid conflicts with core widgets
    var widgetId = "plugin:" + pluginId;

    pluginWidgets[widgetId] = component;
    pluginWidgetMetadata[widgetId] = metadata || {};

    // Also add to main widgets object for unified access
    widgets[widgetId] = component;
    widgetMetadata[widgetId] = metadata || {};

    Logger.i("BarWidgetRegistry", "Registered plugin widget:", widgetId);
    root.pluginWidgetRegistryUpdated();
    return true;
  }

  // Unregister a plugin widget
  function unregisterPluginWidget(pluginId) {
    var widgetId = "plugin:" + pluginId;

    if (!pluginWidgets[widgetId]) {
      Logger.w("BarWidgetRegistry", "Plugin widget not registered:", widgetId);
      return false;
    }

    delete pluginWidgets[widgetId];
    delete pluginWidgetMetadata[widgetId];
    delete widgets[widgetId];
    delete widgetMetadata[widgetId];

    Logger.i("BarWidgetRegistry", "Unregistered plugin widget:", widgetId);
    root.pluginWidgetRegistryUpdated();
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
