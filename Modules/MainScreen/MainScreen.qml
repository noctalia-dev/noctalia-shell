import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI
import "Backgrounds" as Backgrounds

// All panels
import qs.Modules.Bar
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
  readonly property alias trayMenuPanel: trayMenuPanel
  readonly property alias wallpaperPanel: wallpaperPanel
  readonly property alias wifiPanel: wifiPanel

  Component.onCompleted: {
    Logger.d("MainScreen", "Initialized for screen:", screen?.name, "- Dimensions:", screen?.width, "x", screen?.height, "- Position:", screen?.x, ",", screen?.y)
  }

  // Wayland
  // Always use Exclusive keyboard focus when a panel is open
  // This ensures all keyboard shortcuts work reliably (Escape, etc.)
  // The centralized shortcuts in this window handle delegation to panels
  WlrLayershell.keyboardFocus: root.isPanelOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "noctalia-screen-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore // Don't reserve space - BarExclusionZone handles that

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Desktop dimming when panels are open
  property bool dimDesktop: Settings.data.general.dimDesktop
  property bool isPanelOpen: (PanelService.openedPanel !== null) && (PanelService.openedPanel.screen === screen)
  property bool isPanelClosing: (PanelService.openedPanel !== null) && PanelService.openedPanel.isClosing

  color: {
    if (dimDesktop && isPanelOpen) {
      return Qt.alpha(Color.mShadow, 0.8)
    }
    return Color.transparent
  }

  Behavior on color {
    ColorAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutQuad
    }
  }

  // Fully reactive mask system, make everything click-through except bar and open panels
  mask: Region {
    id: clickableMask

    // Cover entire window (everything is masked/click-through)
    x: 0
    y: 0
    width: root.width
    height: root.height
    intersection: Intersection.Xor

    // Direct binding to Variants.instances plus additional regions
    regions: panelRegions.instances.concat([barMaskRegion, backgroundMaskRegion])

    // Bar region - subtract bar area from mask
    Region {
      id: barMaskRegion

      x: barPlaceholder.x
      y: barPlaceholder.y
      width: barPlaceholder.width
      height: barPlaceholder.height
      intersection: Intersection.Subtract
    }

    // Background region for click-to-close - reactive sizing
    Region {
      id: backgroundMaskRegion
      x: 0
      y: 0
      width: root.isPanelOpen && !isPanelClosing ? root.width : 0
      height: root.isPanelOpen && !isPanelClosing ? root.height : 0
      intersection: Intersection.Subtract
    }
  }

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

    // Background MouseArea for closing panels when clicking outside
    // Active whenever a panel is open - the mask ensures it only receives clicks when panel is open
    MouseArea {
      anchors.fill: parent
      enabled: root.isPanelOpen
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: mouse => {
                   if (PanelService.openedPanel) {
                     PanelService.openedPanel.close()
                   }
                 }
      z: 0 // Behind panels and bar
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

    TrayMenuPanel {
      id: trayMenuPanel
      screen: root.screen
      z: 50

      Component.onCompleted: {
        objectName = "trayMenuPanel-" + (screen?.name || "unknown")
        PanelService.registerPanel(trayMenuPanel)
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

    // Bar placeholder - just for background positioning (actual bar content is in BarContentWindow)
    Item {
      id: barPlaceholder

      // Expose self as barItem for AllBackgrounds compatibility
      readonly property var barItem: barPlaceholder

      // Screen reference
      property ShellScreen screen: root.screen

      // Bar positioning properties (match Bar.qml logic)
      readonly property string barPosition: Settings.data.bar.position || "top"
      readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
      readonly property bool barFloating: Settings.data.bar.floating || false
      readonly property real barMarginH: barFloating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0
      readonly property real barMarginV: barFloating ? Settings.data.bar.marginVertical * Style.marginXL : 0

      // Expose bar dimensions directly on this Item for BarBackground
      // Use screen dimensions directly
      x: {
        if (barPosition === "right")
          return screen.width - Style.barHeight - barMarginH
        return barMarginH
      }
      y: {
        if (barPosition === "bottom")
          return screen.height - Style.barHeight - barMarginV
        return barMarginV
      }
      width: {
        if (barIsVertical) {
          return Style.barHeight + 1
        }
        return screen.width - barMarginH * 2
      }
      height: {
        if (barIsVertical) {
          return screen.height - barMarginV * 2
        }
        return Style.barHeight
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

  // Centralized keyboard shortcuts - delegate to opened panel
  // This ensures shortcuts work regardless of panel focus state
  Shortcut {
    sequence: "Escape"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onEscapePressed) {
        PanelService.openedPanel.onEscapePressed()
      } else if (PanelService.openedPanel) {
        PanelService.openedPanel.close()
      }
    }
  }

  Shortcut {
    sequence: "Tab"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onTabPressed) {
        PanelService.openedPanel.onTabPressed()
      }
    }
  }

  Shortcut {
    sequence: "Shift+Tab"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onShiftTabPressed) {
        PanelService.openedPanel.onShiftTabPressed()
      }
    }
  }

  Shortcut {
    sequence: "Up"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onUpPressed) {
        PanelService.openedPanel.onUpPressed()
      }
    }
  }

  Shortcut {
    sequence: "Down"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onDownPressed) {
        PanelService.openedPanel.onDownPressed()
      }
    }
  }

  Shortcut {
    sequence: "Return"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onReturnPressed) {
        PanelService.openedPanel.onReturnPressed()
      }
    }
  }

  Shortcut {
    sequence: "Enter"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onReturnPressed) {
        PanelService.openedPanel.onReturnPressed()
      }
    }
  }

  Shortcut {
    sequence: "Home"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onHomePressed) {
        PanelService.openedPanel.onHomePressed()
      }
    }
  }

  Shortcut {
    sequence: "End"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onEndPressed) {
        PanelService.openedPanel.onEndPressed()
      }
    }
  }

  Shortcut {
    sequence: "PgUp"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onPageUpPressed) {
        PanelService.openedPanel.onPageUpPressed()
      }
    }
  }

  Shortcut {
    sequence: "PgDown"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onPageDownPressed) {
        PanelService.openedPanel.onPageDownPressed()
      }
    }
  }

  Shortcut {
    sequence: "Ctrl+J"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onCtrlJPressed) {
        PanelService.openedPanel.onCtrlJPressed()
      }
    }
  }

  Shortcut {
    sequence: "Ctrl+K"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onCtrlKPressed) {
        PanelService.openedPanel.onCtrlKPressed()
      }
    }
  }

  Shortcut {
    sequence: "Left"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onLeftPressed) {
        PanelService.openedPanel.onLeftPressed()
      }
    }
  }

  Shortcut {
    sequence: "Right"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onRightPressed) {
        PanelService.openedPanel.onRightPressed()
      }
    }
  }
}
