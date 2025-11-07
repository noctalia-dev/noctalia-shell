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
                           "Notifications": notificationsComponent,
                           "KeepAwake": keepAwakeComponent,
                           "NightLight": nightLightComponent,
                           "PowerProfile": powerProfileComponent,
                           "ScreenRecorder": screenRecorderComponent,
                           "WiFi": wiFiComponent,
                           "WallpaperSelector": wallpaperSelectorComponent,
                           "CustomButton": customButtonComponent
                         })

  property var widgetMetadata: ({
                                  "CustomButton": {
                                    "allowUserSettings": true,
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
  property Component notificationsComponent: Component {
    Notifications {}
  }
  property Component keepAwakeComponent: Component {
    KeepAwake {}
  }
  property Component nightLightComponent: Component {
    NightLight {}
  }
  property Component powerProfileComponent: Component {
    PowerProfile {}
  }
  property Component screenRecorderComponent: Component {
    ScreenRecorder {}
  }
  property Component wiFiComponent: Component {
    WiFi {}
  }
  property Component wallpaperSelectorComponent: Component {
    WallpaperSelector {}
  }
  property Component customButtonComponent: Component {
    CustomButton {}
  }

  function init() {
    Logger.i("ControlCenterWidgetRegistry", "Service started")
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
