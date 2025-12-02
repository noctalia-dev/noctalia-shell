import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "Backgrounds" as Backgrounds

import qs.Commons

// All panels
import qs.Modules.Bar
import qs.Modules.Bar.Extras
import qs.Modules.Panels.Audio
import qs.Modules.Panels.Battery
import qs.Modules.Panels.Bluetooth
import qs.Modules.Panels.Brightness
import qs.Modules.Panels.Calendar
import qs.Modules.Panels.Changelog
import qs.Modules.Panels.ControlCenter
import qs.Modules.Panels.Launcher
import qs.Modules.Panels.NotificationHistory
import qs.Modules.Panels.SessionMenu
import qs.Modules.Panels.Settings
import qs.Modules.Panels.SetupWizard
import qs.Modules.Panels.Tray
import qs.Modules.Panels.Wallpaper
import qs.Modules.Panels.WiFi
import qs.Services.Compositor
import qs.Services.UI

/**
* MainScreen - Single PanelWindow per screen that manages all panels and the bar
*/
PanelWindow {
  id: root

  // Expose panels as readonly property aliases
  readonly property alias audioPanel: audioPanel
  readonly property alias batteryPanel: batteryPanel
  readonly property alias bluetoothPanel: bluetoothPanel
  readonly property alias brightnessPanel: brightnessPanel
  readonly property alias calendarPanel: calendarPanel
  readonly property alias changelogPanel: changelogPanel
  readonly property alias controlCenterPanel: controlCenterPanel
  readonly property alias launcherPanel: launcherPanel
  readonly property alias notificationHistoryPanel: notificationHistoryPanel
  readonly property alias sessionMenuPanel: sessionMenuPanel
  readonly property alias settingsPanel: settingsPanel
  readonly property alias setupWizardPanel: setupWizardPanel
  readonly property alias trayDrawerPanel: trayDrawerPanel
  readonly property alias wallpaperPanel: wallpaperPanel
  readonly property alias wifiPanel: wifiPanel

  // Expose panel backgrounds for AllBackgrounds
  readonly property var audioPanelPlaceholder: audioPanel.panelRegion
  readonly property var batteryPanelPlaceholder: batteryPanel.panelRegion
  readonly property var bluetoothPanelPlaceholder: bluetoothPanel.panelRegion
  readonly property var brightnessPanelPlaceholder: brightnessPanel.panelRegion
  readonly property var calendarPanelPlaceholder: calendarPanel.panelRegion
  readonly property var changelogPanelPlaceholder: changelogPanel.panelRegion
  readonly property var controlCenterPanelPlaceholder: controlCenterPanel.panelRegion
  readonly property var launcherPanelPlaceholder: launcherPanel.panelRegion
  readonly property var notificationHistoryPanelPlaceholder: notificationHistoryPanel.panelRegion
  readonly property var sessionMenuPanelPlaceholder: sessionMenuPanel.panelRegion
  readonly property var settingsPanelPlaceholder: settingsPanel.panelRegion
  readonly property var setupWizardPanelPlaceholder: setupWizardPanel.panelRegion
  readonly property var trayDrawerPanelPlaceholder: trayDrawerPanel.panelRegion
  readonly property var wallpaperPanelPlaceholder: wallpaperPanel.panelRegion
  readonly property var wifiPanelPlaceholder: wifiPanel.panelRegion

  Component.onCompleted: {
    Logger.d("MainScreen", "Initialized for screen:", screen?.name, "- Dimensions:", screen?.width, "x", screen?.height, "- Position:", screen?.x, ",", screen?.y);
  }

  // Wayland
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "noctalia-background-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore // Don't reserve space - BarExclusionZone handles that
  WlrLayershell.keyboardFocus: {
    const p = PanelService.openedPanel;

    if (!root.isPanelOpen || !p)
        return WlrKeyboardFocus.None;

    if (Settings.data.virtualKeyboard.enabled)
        return Settings.data.virtualKeyboard.clicking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None;

    return p.exclusiveKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.onDemand;
  }


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
      return Qt.alpha(Color.mShadow, dimmerOpacity);
    }
    return Color.transparent;
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
      return false;

    // Check screen-specific configuration
    var monitors = Settings.data.bar.monitors || [];
    var screenName = screen?.name || "";

    // If no monitors specified, show on all screens
    // If monitors specified, only show if this screen is in the list
    return monitors.length === 0 || monitors.includes(screenName);
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

    // Only include regions that are actually needed
    // panelRegions is handled by PanelService, bar is local to this screen
    regions: [barMaskRegion, backgroundMaskRegion]

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

    // Background MouseArea for closing panels when clicking outside
    // Active whenever a panel is open - the mask ensures it only receives clicks when panel is open
    MouseArea {
      anchors.fill: parent
      enabled: root.isPanelOpen && PanelService.openedPanel && !PanelService.openedPanel.mouseOnVirtualKeyboard
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: mouse => {
                   if (PanelService.openedPanel) {
                     PanelService.openedPanel.close();
                   }
                 }
      z: 0 // Behind panels and bar
    }

    // ---------------------------------------
    // All panels always exist
    // ---------------------------------------
    AudioPanel {
      id: audioPanel
      objectName: "audioPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    BatteryPanel {
      id: batteryPanel
      objectName: "batteryPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    BluetoothPanel {
      id: bluetoothPanel
      objectName: "bluetoothPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    BrightnessPanel {
      id: brightnessPanel
      objectName: "brightnessPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    ControlCenterPanel {
      id: controlCenterPanel
      objectName: "controlCenterPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    ChangelogPanel {
      id: changelogPanel
      objectName: "changelogPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    CalendarPanel {
      id: calendarPanel
      objectName: "calendarPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    Launcher {
      id: launcherPanel
      objectName: "launcherPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    NotificationHistoryPanel {
      id: notificationHistoryPanel
      objectName: "notificationHistoryPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    SessionMenu {
      id: sessionMenuPanel
      objectName: "sessionMenuPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    SettingsPanel {
      id: settingsPanel
      objectName: "settingsPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    SetupWizard {
      id: setupWizardPanel
      objectName: "setupWizardPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    TrayDrawerPanel {
      id: trayDrawerPanel
      objectName: "trayDrawerPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    WallpaperPanel {
      id: wallpaperPanel
      objectName: "wallpaperPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
    }

    WiFiPanel {
      id: wifiPanel
      objectName: "wifiPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
      z: 50
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
          return screen.width - Style.barHeight - barMarginH - attachmentOverlap; // Extend left towards panels
        return barMarginH;
      }
      y: {
        if (barPosition === "bottom")
          return screen.height - Style.barHeight - barMarginV - attachmentOverlap;
        return barMarginV;
      }
      width: {
        if (barIsVertical) {
          return Style.barHeight + attachmentOverlap;
        }
        return screen.width - barMarginH * 2;
      }
      height: {
        if (barIsVertical) {
          return screen.height - barMarginV * 2;
        }
        return Style.barHeight + attachmentOverlap;
      }

      // Corner states (same as Bar.qml)
      readonly property int topLeftCornerState: {
        if (barFloating)
          return 0;
        if (barPosition === "top")
          return -1;
        if (barPosition === "left")
          return -1;
        if (Settings.data.bar.outerCorners && (barPosition === "bottom" || barPosition === "right")) {
          return barIsVertical ? 1 : 2;
        }
        return -1;
      }

      readonly property int topRightCornerState: {
        if (barFloating)
          return 0;
        if (barPosition === "top")
          return -1;
        if (barPosition === "right")
          return -1;
        if (Settings.data.bar.outerCorners && (barPosition === "bottom" || barPosition === "left")) {
          return barIsVertical ? 1 : 2;
        }
        return -1;
      }

      readonly property int bottomLeftCornerState: {
        if (barFloating)
          return 0;
        if (barPosition === "bottom")
          return -1;
        if (barPosition === "left")
          return -1;
        if (Settings.data.bar.outerCorners && (barPosition === "top" || barPosition === "right")) {
          return barIsVertical ? 1 : 2;
        }
        return -1;
      }

      readonly property int bottomRightCornerState: {
        if (barFloating)
          return 0;
        if (barPosition === "bottom")
          return -1;
        if (barPosition === "right")
          return -1;
        if (Settings.data.bar.outerCorners && (barPosition === "top" || barPosition === "left")) {
          return barIsVertical ? 1 : 2;
        }
        return -1;
      }
    }

    /**
    *  Screen Corners
    */
    ScreenCorners {}
  }

  // ========================================
  // Centralized Keyboard Shortcuts
  // ========================================
  // These shortcuts delegate to the opened panel's handler functions
  // Panels can implement: onEscapePressed, onTabPressed, onShiftTabPressed,
  // onUpPressed, onDownPressed, onReturnPressed

  Shortcut {
    sequence: "Escape"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onEscapePressed) {
        PanelService.openedPanel.onEscapePressed();
      } else if (PanelService.openedPanel) {
        PanelService.openedPanel.close();
      }
    }
  }

  Shortcut {
    sequence: "Tab"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onTabPressed) {
        PanelService.openedPanel.onTabPressed();
      }
    }
  }

  Shortcut {
    sequence: "Shift+Tab"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onShiftTabPressed) {
        PanelService.openedPanel.onShiftTabPressed();
      }
    }
  }

  Shortcut {
    sequence: "Up"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onUpPressed) {
        PanelService.openedPanel.onUpPressed();
      }
    }
  }

  Shortcut {
    sequence: "Down"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onDownPressed) {
        PanelService.openedPanel.onDownPressed();
      }
    }
  }

  Shortcut {
    sequence: "Return"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onReturnPressed) {
        PanelService.openedPanel.onReturnPressed();
      }
    }
  }

  Shortcut {
    sequence: "Left"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onLeftPressed) {
        PanelService.openedPanel.onLeftPressed();
      }
    }
  }

  Shortcut {
    sequence: "Right"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onRightPressed) {
        PanelService.openedPanel.onRightPressed();
      }
    }
  }

  Shortcut {
    sequence: "Home"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onHomePressed) {
        PanelService.openedPanel.onHomePressed();
      }
    }
  }

  Shortcut {
    sequence: "End"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onEndPressed) {
        PanelService.openedPanel.onEndPressed();
      }
    }
  }

  Shortcut {
    sequence: "PgUp"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onPageUpPressed) {
        PanelService.openedPanel.onPageUpPressed();
      }
    }
  }

  Shortcut {
    sequence: "PgDown"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onPageDownPressed) {
        PanelService.openedPanel.onPageDownPressed();
      }
    }
  }

  Shortcut {
    sequence: "Backtab"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onBackTabPressed) {
        PanelService.openedPanel.onBackTabPressed();
      }
    }
  }

  Shortcut {
    sequence: "Ctrl+J"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onCtrlJPressed) {
        PanelService.openedPanel.onCtrlJPressed();
      }
    }
  }

  Shortcut {
    sequence: "Ctrl+K"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onCtrlKPressed) {
        PanelService.openedPanel.onCtrlKPressed();
      }
    }
  }

  Shortcut {
    sequence: "Ctrl+N"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onCtrlNPressed) {
        PanelService.openedPanel.onCtrlNPressed();
      }
    }
  }

  Shortcut {
    sequence: "Ctrl+P"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onCtrlPPressed) {
        PanelService.openedPanel.onCtrlPPressed();
      }
    }
  }
}
