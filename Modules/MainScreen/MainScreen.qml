import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

import qs.Commons
import qs.Services.UI
import "Backgrounds" as Backgrounds

// All panels
import qs.Modules.Bar
import qs.Modules.Bar.Extras
import qs.Modules.Panels.Audio
import qs.Modules.Panels.Battery
import qs.Modules.Panels.Bluetooth
import qs.Modules.Panels.Calendar
import qs.Modules.Panels.ControlCenter
import qs.Modules.Panels.Launcher
import qs.Modules.Panels.NotificationHistory
import qs.Modules.Panels.SessionMenu
import qs.Modules.Panels.Settings
import qs.Modules.Panels.SetupWizard
import qs.Modules.Panels.Tray
import qs.Modules.Panels.Wallpaper
import qs.Modules.Panels.WiFi


/**
 * MainScreen - Single PanelWindow per screen that manages all panels and the bar
 */
PanelWindow {
  id: root

  // Expose panels as readonly property aliases
  readonly property alias audioPanel: audioPanel
  readonly property alias batteryPanel: batteryPanel
  readonly property alias bluetoothPanel: bluetoothPanel
  readonly property alias calendarPanel: calendarPanel
  readonly property alias controlCenterPanel: controlCenterPanel
  readonly property alias launcherPanel: launcherPanel
  readonly property alias notificationHistoryPanel: notificationHistoryPanel
  readonly property alias sessionMenuPanel: sessionMenuPanel
  readonly property alias settingsPanel: settingsPanel
  readonly property alias setupWizardPanel: setupWizardPanel
  readonly property alias trayDrawerPanel: trayDrawerPanel
  readonly property alias wallpaperPanel: wallpaperPanel
  readonly property alias wifiPanel: wifiPanel

  // Expose panel placeholders for AllBackgrounds
  readonly property var audioPanelPlaceholder: audioPanel.panelPlaceholder
  readonly property var batteryPanelPlaceholder: batteryPanel.panelPlaceholder
  readonly property var bluetoothPanelPlaceholder: bluetoothPanel.panelPlaceholder
  readonly property var calendarPanelPlaceholder: calendarPanel.panelPlaceholder
  readonly property var controlCenterPanelPlaceholder: controlCenterPanel.panelPlaceholder
  readonly property var launcherPanelPlaceholder: launcherPanel.panelPlaceholder
  readonly property var notificationHistoryPanelPlaceholder: notificationHistoryPanel.panelPlaceholder
  readonly property var sessionMenuPanelPlaceholder: sessionMenuPanel.panelPlaceholder
  readonly property var settingsPanelPlaceholder: settingsPanel.panelPlaceholder
  readonly property var setupWizardPanelPlaceholder: setupWizardPanel.panelPlaceholder
  readonly property var trayDrawerPanelPlaceholder: trayDrawerPanel.panelPlaceholder
  readonly property var wallpaperPanelPlaceholder: wallpaperPanel.panelPlaceholder
  readonly property var wifiPanelPlaceholder: wifiPanel.panelPlaceholder

  Component.onCompleted: {
    Logger.d("MainScreen", "Initialized for screen:", screen?.name, "- Dimensions:", screen?.width, "x", screen?.height, "- Position:", screen?.x, ",", screen?.y)
  }

  // Wayland
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "noctalia-background-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore // Don't reserve space - BarExclusionZone handles that
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Desktop dimming when panels are open
  property real dimmerOpacity: Settings.data.general.dimmerOpacity ?? 0.8
  property bool isPanelOpen: (PanelService.openedPanel !== null) && (PanelService.openedPanel.screen === screen)
  property bool isPanelClosing: (PanelService.openedPanel !== null) && PanelService.openedPanel.isClosing

  color: {
    if (dimmerOpacity > 0 && isPanelOpen && !isPanelClosing) {
      return Qt.alpha(Color.mShadow, dimmerOpacity)
    }
    return Color.transparent
  }

  Behavior on color {
    ColorAnimation {
      duration: isPanelClosing ? Style.animationFaster : Style.animationNormal
      easing.type: Easing.OutQuad
    }
  }

  // Check if bar should be visible on this screen
  readonly property bool barShouldShow: {
    // Check global bar visibility
    if (!BarService.isVisible)
      return false

    // Check screen-specific configuration
    var monitors = Settings.data.bar.monitors || []
    var screenName = screen?.name || ""

    // If no monitors specified, show on all screens
    // If monitors specified, only show if this screen is in the list
    return monitors.length === 0 || monitors.includes(screenName)
  }

  // Make everything click-through except bar
  mask: Region {
    id: clickableMask

    // Cover entire window (everything is masked/click-through)
    x: 0
    y: 0
    width: root.width
    height: root.height
    intersection: Intersection.Xor

    regions: [barMaskRegion]

    // Bar region - subtract bar area from mask (only if bar should be shown on this screen)
    Region {
      id: barMaskRegion

      x: barPlaceholder.x
      y: barPlaceholder.y

      // Set width/height to 0 if bar shouldn't show on this screen (makes region empty)
      width: root.barShouldShow ? barPlaceholder.width : 0
      height: root.barShouldShow ? barPlaceholder.height : 0
      intersection: Intersection.Subtract
    }
  }

  // --------------------------------------
  // Container for all UI elements
  Item {
    id: container
    width: root.width
    height: root.height

    // Unified backgrounds container / unified shadow system
    // Renders all bar and panel backgrounds as ShapePaths within a single Shape
    // This allows the shadow effect to apply to all backgrounds in one render pass
    Backgrounds.AllBackgrounds {
      id: unifiedBackgrounds
      anchors.fill: parent
      bar: barPlaceholder.barItem || null
      windowRoot: root
      z: 0 // Behind all content
    }

    // ---------------------------------------
    // All panels always exist
    // ---------------------------------------
    AudioPanel {
      id: audioPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "audioPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(audioPanel)
      }
    }

    BatteryPanel {
      id: batteryPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "batteryPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(batteryPanel)
      }
    }

    BluetoothPanel {
      id: bluetoothPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "bluetoothPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(bluetoothPanel)
      }
    }

    ControlCenterPanel {
      id: controlCenterPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "controlCenterPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(controlCenterPanel)
      }
    }

    CalendarPanel {
      id: calendarPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "calendarPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(calendarPanel)
      }
    }

    Launcher {
      id: launcherPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "launcherPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(launcherPanel)
      }
    }

    NotificationHistoryPanel {
      id: notificationHistoryPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "notificationHistoryPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(notificationHistoryPanel)
      }
    }

    SessionMenu {
      id: sessionMenuPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "sessionMenuPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(sessionMenuPanel)
      }
    }

    SettingsPanel {
      id: settingsPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "settingsPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(settingsPanel)
      }
    }

    SetupWizard {
      id: setupWizardPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "setupWizardPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(setupWizardPanel)
      }
    }

    TrayDrawerPanel {
      id: trayDrawerPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "trayDrawerPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(trayDrawerPanel)
      }
    }

    WallpaperPanel {
      id: wallpaperPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "wallpaperPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(wallpaperPanel)
      }
    }

    WiFiPanel {
      id: wifiPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "wifiPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(wifiPanel)
      }
    }

    // ----------------------------------------------
    // Bar background placeholder - just for background positioning (actual bar content is in BarContentWindow)
    Item {
      id: barPlaceholder

      // Expose self as barItem for AllBackgrounds compatibility
      readonly property var barItem: barPlaceholder

      // Screen reference
      property ShellScreen screen: root.screen

      // Bar background positioning properties
      readonly property string barPosition: Settings.data.bar.position || "top"
      readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
      readonly property bool barFloating: Settings.data.bar.floating || false
      readonly property real barMarginH: barFloating ? Math.round(Settings.data.bar.marginHorizontal * Style.marginXL) : 0
      readonly property real barMarginV: barFloating ? Math.round(Settings.data.bar.marginVertical * Style.marginXL) : 0
      readonly property real attachmentOverlap: 1 // Attachment overlap to fix hairline gap with fractional scaling

      // Expose bar dimensions directly on this Item for BarBackground
      // Use screen dimensions directly
      x: {
        if (barPosition === "right")
          return screen.width - Style.barHeight - barMarginH - attachmentOverlap // Extend left towards panels
        return barMarginH
      }
      y: {
        if (barPosition === "bottom")
          return screen.height - Style.barHeight - barMarginV - attachmentOverlap
        return barMarginV
      }
      width: {
        if (barIsVertical) {
          return Style.barHeight + attachmentOverlap
        }
        return screen.width - barMarginH * 2
      }
      height: {
        if (barIsVertical) {
          return screen.height - barMarginV * 2
        }
        return Style.barHeight + attachmentOverlap
      }

      // Corner states (same as Bar.qml)
      readonly property int topLeftCornerState: {
        if (barFloating)
          return 0
        if (barPosition === "top")
          return -1
        if (barPosition === "left")
          return -1
        if (Settings.data.bar.outerCorners && (barPosition === "bottom" || barPosition === "right")) {
          return barIsVertical ? 1 : 2
        }
        return -1
      }

      readonly property int topRightCornerState: {
        if (barFloating)
          return 0
        if (barPosition === "top")
          return -1
        if (barPosition === "right")
          return -1
        if (Settings.data.bar.outerCorners && (barPosition === "bottom" || barPosition === "left")) {
          return barIsVertical ? 1 : 2
        }
        return -1
      }

      readonly property int bottomLeftCornerState: {
        if (barFloating)
          return 0
        if (barPosition === "bottom")
          return -1
        if (barPosition === "left")
          return -1
        if (Settings.data.bar.outerCorners && (barPosition === "top" || barPosition === "right")) {
          return barIsVertical ? 1 : 2
        }
        return -1
      }

      readonly property int bottomRightCornerState: {
        if (barFloating)
          return 0
        if (barPosition === "bottom")
          return -1
        if (barPosition === "right")
          return -1
        if (Settings.data.bar.outerCorners && (barPosition === "top" || barPosition === "left")) {
          return barIsVertical ? 1 : 2
        }
        return -1
      }

      Component.onCompleted: {
        Logger.d("MainScreen", "===== Bar placeholder loaded =====")
        Logger.d("MainScreen", "  Screen:", screen?.name, "Size:", screen?.width, "x", screen?.height)
        Logger.d("MainScreen", "  Bar position:", barPosition, "| isVertical:", barIsVertical)
        Logger.d("MainScreen", "  Bar dimensions: x=" + x, "y=" + y, "width=" + width, "height=" + height)
        Logger.d("MainScreen", "  Style.barHeight =", Style.barHeight)
        Logger.d("MainScreen", "  Margins: H=" + barMarginH, "V=" + barMarginV, "| Floating:", barFloating)
      }
    }


    /**
     *  Screen Corners
     */
    ScreenCorners {}
  }
}
