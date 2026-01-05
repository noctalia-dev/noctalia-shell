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
import qs.Modules.Panels.Changelog
import qs.Modules.Panels.Clock
import qs.Modules.Panels.ControlCenter
import qs.Modules.Panels.Launcher
import qs.Modules.Panels.Network
import qs.Modules.Panels.NotificationHistory
import qs.Modules.Panels.Plugins
import qs.Modules.Panels.SessionMenu
import qs.Modules.Panels.Settings
import qs.Modules.Panels.SetupWizard
import qs.Modules.Panels.SystemStats
import qs.Modules.Panels.Tray
import qs.Modules.Panels.Wallpaper
import qs.Services.Compositor
import qs.Services.UI

/**
* MainScreen - Single PanelWindow per screen that manages all panels and the bar
*/
PanelWindow {
  id: root

  Component.onCompleted: {
    Logger.d("MainScreen", "Initialized for screen:", screen?.name, "- Dimensions:", screen?.width, "x", screen?.height, "- Position:", screen?.x, ",", screen?.y);
  }

  // Wayland
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "noctalia-background-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore // Don't reserve space - BarExclusionZone handles that
  WlrLayershell.keyboardFocus: {
    // No panel open anywhere: no keyboard focus needed
    if (!root.isAnyPanelOpen) {
      return WlrKeyboardFocus.None;
    }
    // Panel open on THIS screen: use panel's preferred focus mode
    if (root.isPanelOpen) {
      // Hyprland's Exclusive captures ALL input globally (including pointer),
      // preventing click-to-close from working on other monitors.
      // Workaround: briefly use Exclusive when panel opens (for text input focus),
      // then switch to OnDemand (for click-to-close on other screens).
      if (CompositorService.isHyprland) {
        return PanelService.isInitializingKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand;
      }
      return PanelService.openedPanel.exclusiveKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand;
    }
    // Panel open on ANOTHER screen: OnDemand allows receiving pointer events for click-to-close
    return WlrKeyboardFocus.OnDemand;
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
  property bool isAnyPanelOpen: PanelService.openedPanel !== null

  color: {
    if (dimmerOpacity > 0 && isPanelOpen && !isPanelClosing) {
      return Qt.alpha(Color.mShadow, dimmerOpacity);
    }
    return "transparent";
  }

  Behavior on color {
    enabled: !PanelService.closedImmediately
    ColorAnimation {
      duration: isPanelClosing ? Style.animationFaster : Style.animationNormal
      easing.type: Easing.OutQuad
    }
  }

  // Reset closedImmediately flag after color change is applied
  onColorChanged: {
    if (PanelService.closedImmediately) {
      PanelService.closedImmediately = false;
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
    // Uses isAnyPanelOpen so clicking on any screen's background closes the panel
    Region {
      id: backgroundMaskRegion
      x: 0
      y: 0
      width: root.isAnyPanelOpen ? root.width : 0
      height: root.isAnyPanelOpen ? root.height : 0
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
    // Uses isAnyPanelOpen so clicking on any screen's background closes the panel
    MouseArea {
      anchors.fill: parent
      enabled: root.isAnyPanelOpen
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
    }

    BatteryPanel {
      id: batteryPanel
      objectName: "batteryPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    BluetoothPanel {
      id: bluetoothPanel
      objectName: "bluetoothPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    BrightnessPanel {
      id: brightnessPanel
      objectName: "brightnessPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    ControlCenterPanel {
      id: controlCenterPanel
      objectName: "controlCenterPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    ChangelogPanel {
      id: changelogPanel
      objectName: "changelogPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    ClockPanel {
      id: clockPanel
      objectName: "clockPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    Launcher {
      id: launcherPanel
      objectName: "launcherPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    NotificationHistoryPanel {
      id: notificationHistoryPanel
      objectName: "notificationHistoryPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    SessionMenu {
      id: sessionMenuPanel
      objectName: "sessionMenuPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    SettingsPanel {
      id: settingsPanel
      objectName: "settingsPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    SetupWizard {
      id: setupWizardPanel
      objectName: "setupWizardPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    TrayDrawerPanel {
      id: trayDrawerPanel
      objectName: "trayDrawerPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    WallpaperPanel {
      id: wallpaperPanel
      objectName: "wallpaperPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    NetworkPanel {
      id: networkPanel
      objectName: "networkPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    SystemStatsPanel {
      id: systemStatsPanel
      objectName: "systemStatsPanel-" + (root.screen?.name || "unknown")
      screen: root.screen
    }

    // ----------------------------------------------
    // Plugin panel slots
    // ----------------------------------------------
    PluginPanelSlot {
      id: pluginPanel1
      objectName: "pluginPanel1-" + (root.screen?.name || "unknown")
      screen: root.screen
      slotNumber: 1
    }

    PluginPanelSlot {
      id: pluginPanel2
      objectName: "pluginPanel2-" + (root.screen?.name || "unknown")
      screen: root.screen
      slotNumber: 2
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
      readonly property real barMarginH: barFloating ? Math.floor(Settings.data.bar.marginHorizontal * Style.marginXL) : 0
      readonly property real barMarginV: barFloating ? Math.floor(Settings.data.bar.marginVertical * Style.marginXL) : 0

      // Expose bar dimensions directly on this Item for BarBackground
      // Use screen dimensions directly
      x: {
        if (barPosition === "right")
          return screen.width - Style.barHeight - barMarginH;
        return barMarginH;
      }
      y: {
        if (barPosition === "bottom")
          return screen.height - Style.barHeight - barMarginV;
        return barMarginV;
      }
      width: {
        if (barIsVertical) {
          return Style.barHeight;
        }
        return screen.width - barMarginH * 2;
      }
      height: {
        if (barIsVertical) {
          return screen.height - barMarginV * 2;
        }
        return Style.barHeight;
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
  // Panels can implement: onEscapePressed, onTabPressed, onBackTabPressed,
  // onUpPressed, onDownPressed, onReturnPressed, etc...
  Shortcut {
    sequence: "Escape"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onEscapePressed !== undefined)
    onActivated: PanelService.openedPanel.onEscapePressed()
  }

  Shortcut {
    sequence: "Tab"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onTabPressed !== undefined)
    onActivated: PanelService.openedPanel.onTabPressed()
  }

  Shortcut {
    sequence: "Backtab"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onBackTabPressed !== undefined)
    onActivated: PanelService.openedPanel.onBackTabPressed()
  }

  Shortcut {
    sequence: "Up"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onUpPressed !== undefined)
    onActivated: PanelService.openedPanel.onUpPressed()
  }

  Shortcut {
    sequence: "Down"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onDownPressed !== undefined)
    onActivated: PanelService.openedPanel.onDownPressed()
  }

  Shortcut {
    sequence: "Return"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onReturnPressed !== undefined)
    onActivated: PanelService.openedPanel.onReturnPressed()
  }

  Shortcut {
    sequence: "Left"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onLeftPressed !== undefined)
    onActivated: PanelService.openedPanel.onLeftPressed()
  }

  Shortcut {
    sequence: "Right"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onRightPressed !== undefined)
    onActivated: PanelService.openedPanel.onRightPressed()
  }

  Shortcut {
    sequence: "Home"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onHomePressed !== undefined)
    onActivated: PanelService.openedPanel.onHomePressed()
  }

  Shortcut {
    sequence: "End"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onEndPressed !== undefined)
    onActivated: PanelService.openedPanel.onEndPressed()
  }

  Shortcut {
    sequence: "PgUp"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onPageUpPressed !== undefined)
    onActivated: PanelService.openedPanel.onPageUpPressed()
  }

  Shortcut {
    sequence: "PgDown"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onPageDownPressed !== undefined)
    onActivated: PanelService.openedPanel.onPageDownPressed()
  }

  Shortcut {
    sequence: "Ctrl+J"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onCtrlJPressed !== undefined)
    onActivated: PanelService.openedPanel.onCtrlJPressed()
  }

  Shortcut {
    sequence: "Ctrl+K"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onCtrlKPressed !== undefined)
    onActivated: PanelService.openedPanel.onCtrlKPressed()
  }

  Shortcut {
    sequence: "Ctrl+N"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onCtrlNPressed !== undefined)
    onActivated: PanelService.openedPanel.onCtrlNPressed()
  }

  Shortcut {
    sequence: "Ctrl+P"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onCtrlPPressed !== undefined)
    onActivated: PanelService.openedPanel.onCtrlPPressed()
  }

  Shortcut {
    sequence: "1"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(1)
  }

  Shortcut {
    sequence: "2"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(2)
  }

  Shortcut {
    sequence: "3"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(3)
  }

  Shortcut {
    sequence: "4"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(4)
  }

  Shortcut {
    sequence: "5"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(5)
  }

  Shortcut {
    sequence: "6"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(6)
  }

  Shortcut {
    sequence: "7"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(7)
  }

  Shortcut {
    sequence: "8"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(8)
  }

  Shortcut {
    sequence: "9"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onNumberPressed !== undefined)
    onActivated: PanelService.openedPanel.onNumberPressed(9)
  }

  // ===== VIM BINDINGS =====
  Shortcut {
    sequence: "H"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onHPressed !== undefined)
    onActivated: PanelService.openedPanel.onHPressed()
  }

  Shortcut {
    sequence: "J"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onJPressed !== undefined)
    onActivated: PanelService.openedPanel.onJPressed()
  }

  Shortcut {
    sequence: "K"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onKPressed !== undefined)
    onActivated: PanelService.openedPanel.onKPressed()
  }

  Shortcut {
    sequence: "L"
    enabled: root.isPanelOpen && (PanelService.openedPanel.onLPressed !== undefined)
    onActivated: PanelService.openedPanel.onLPressed()
  }
}
