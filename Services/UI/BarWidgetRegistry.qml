pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Bar.Widgets

Singleton {
  id: root

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
                           "TaskbarGrouped": taskbarGroupedComponent,
                           "Tray": trayComponent,
                           "VirtualKeyboard": virtualKeyboardComponent,
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
                                     "TaskbarGrouped": "WidgetSettings/TaskbarGroupedSettings.qml",
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
                                    "deviceNativePath": ""
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
                                    "colorizeSystemIcon": "none"
                                  },
                                  "CustomButton": {
                                    "allowUserSettings": true,
                                    "icon": "heart",
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
                                    "hideWhenZero": true
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
                                    "colorizeIcons": false
                                  },
                                  "TaskbarGrouped": {
                                    "allowUserSettings": true,
                                    "hideUnoccupied": false,
                                    "labelMode": "index",
                                    "showLabelsOnlyWhenOccupied": true,
                                    "colorizeIcons": false
                                  },
                                  "Tray": {
                                    "allowUserSettings": true,
                                    "blacklist": [],
                                    "colorizeIcons": false,
                                    "pinned": [],
                                    "drawerEnabled": true
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
                                    "characterCount": 2
                                  },
                                  "VirtualKeyboard": {
                                      "allowUserSettings": false
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
  property Component virtualKeyboardComponent: Component {
    VirtualKeyboard {}
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
  property Component taskbarGroupedComponent: Component {
    TaskbarGrouped {}
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
}
