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
                           "DarkMode": darkMode,
                           "KeepAwake": keepAwakeComponent,
                           "KeyboardLayout": keyboardLayoutComponent,
                           "MediaMini": mediaMiniComponent,
                           "Microphone": microphoneComponent,
                           "NightLight": nightLightComponent,
                           "NotificationHistory": notificationHistoryComponent,
                           "PowerProfile": powerProfileComponent,
                           "ScreenRecorder": screenRecorderComponent,
                           "SessionMenu": sessionMenuComponent,
                           "Spacer": spacerComponent,
                           "SystemMonitor": systemMonitorComponent,
                           "Taskbar": taskbarComponent,
                           "TaskbarGrouped": taskbarGroupedComponent,
                           "Tray": trayComponent,
                           "Volume": volumeComponent,
                           "WiFi": wiFiComponent,
                           "WallpaperSelector": wallpaperSelectorComponent,
                           "Workspace": workspaceComponent
                         })

  property var widgetMetadata: ({
                                  "ActiveWindow": {
                                    "allowUserSettings": true,
                                    "showIcon": true,
                                    "hideMode": "hidden",
                                    "scrollingMode"// "visible", "hidden", "transparent"
                                    : "hover",
                                    "maxWidth": 145,
                                    "useFixedWidth": false,
                                    "colorizeIcons": false
                                  },
                                  "AudioVisualizer": {
                                    "allowUserSettings": true,
                                    "width": 200,
                                    "hideWhenIdle": false
                                  },
                                  "Battery": {
                                    "allowUserSettings": true,
                                    "displayMode": "onhover",
                                    "warningThreshold": 30
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
                                    "customIconPath": ""
                                  },
                                  "CustomButton": {
                                    "allowUserSettings": true,
                                    "icon": "heart",
                                    "leftClickExec": "",
                                    "rightClickExec": "",
                                    "middleClickExec": "",
                                    "textCommand": "",
                                    "textStream": false,
                                    "textIntervalMs": 3000,
                                    "textCollapse": "",
                                    "parseJson": false
                                  },
                                  "KeyboardLayout": {
                                    "allowUserSettings": true,
                                    "displayMode": "onhover"
                                  },
                                  "MediaMini": {
                                    "allowUserSettings": true,
                                    "hideMode": "hidden",
                                    "scrollingMode"// "visible", "hidden", "transparent"
                                    : "hover",
                                    "maxWidth": 145,
                                    "useFixedWidth": false,
                                    "showAlbumArt": false,
                                    "showVisualizer": false,
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
                                  "Spacer": {
                                    "allowUserSettings": true,
                                    "width": 20
                                  },
                                  "SystemMonitor": {
                                    "allowUserSettings": true,
                                    "showCpuUsage": true,
                                    "showCpuTemp": true,
                                    "showMemoryUsage": true,
                                    "showMemoryAsPercent": false,
                                    "showNetworkStats": false,
                                    "showDiskUsage": false
                                  },
                                  "Taskbar": {
                                    "allowUserSettings": true,
                                    "onlySameOutput": true,
                                    "onlyActiveWorkspaces": true,
                                    "hideMode": "hidden",
                                    "colorizeIcons": false
                                  },
                                  "TaskbarGrouped": {
                                    "allowUserSettings": true
                                  },
                                  "Tray": {
                                    "allowUserSettings": true,
                                    "blacklist": [],
                                    "colorizeIcons": false
                                  },
                                  "WiFi": {
                                    "allowUserSettings": true,
                                    "displayMode": "onhover"
                                  },
                                  "Workspace": {
                                    "allowUserSettings": true,
                                    "labelMode": "index",
                                    "hideUnoccupied": false,
                                    "characterCount": 2
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
  property Component darkMode: Component {
    DarkMode {}
  }
  property Component keyboardLayoutComponent: Component {
    KeyboardLayout {}
  }
  property Component keepAwakeComponent: Component {
    KeepAwake {}
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
    Logger.i("BarWidgetRegistry", "Service started")
  }

  // ------------------------------
  // Helper function to get widget component by name
  function getWidget(id) {
    return widgets[id] || null
  }

  // Helper function to check if widget exists
  function hasWidget(id) {
    return id in widgets
  }

  // Get list of available widget id
  function getAvailableWidgets() {
    return Object.keys(widgets)
  }

  // Helper function to check if widget has user settings
  function widgetHasUserSettings(id) {
    return (widgetMetadata[id] !== undefined) && (widgetMetadata[id].allowUserSettings === true)
  }
}
