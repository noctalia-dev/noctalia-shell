import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Widgets

/**
* AllBackgrounds - Unified Shape container for all bar and panel backgrounds
*
* Unified shadow system. This component contains a single Shape
* with multiple ShapePath children (one for bar, one for each panel type).
*
* Benefits:
* - Single GPU-accelerated rendering pass for all backgrounds
* - Unified shadow system (one MultiEffect for everything)
*/
Item {
  id: root

  // Reference Bar
  required property var bar

  // Reference to MainScreen (for panel access)
  required property var windowRoot

  readonly property color panelBackgroundColor: Color.mSurface

  anchors.fill: parent

  // Wrapper with layer caching for better shadow performance
  Item {
    anchors.fill: parent

    // Enable layer caching to prevent continuous re-rendering
    // This caches the Shape to a GPU texture, reducing GPU tessellation overhead
    layer.enabled: true

    // Apply opacity to all backgrounds
    opacity: Settings.data.ui.panelBackgroundOpacity

    // The unified Shape container
    Shape {
      id: backgroundsShape
      anchors.fill: parent

      // Use curve renderer for smooth corners (GPU-accelerated)
      preferredRendererType: Shape.CurveRenderer

      enabled: false // Disable mouse input on the Shape itself

      Component.onCompleted: {
        Logger.d("AllBackgrounds", "AllBackgrounds initialized");
      }

      /**
      *  Bar
      */
      BarBackground {
        bar: root.bar
        shapeContainer: backgroundsShape
        windowRoot: root.windowRoot
        backgroundColor: Settings.data.bar.transparent ? Color.transparent : panelBackgroundColor
      }

      /**
      *  Panels
      */

      // Audio
      PanelBackground {
        panel: root.windowRoot.audioPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Battery
      PanelBackground {
        panel: root.windowRoot.batteryPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Bluetooth
      PanelBackground {
        panel: root.windowRoot.bluetoothPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Brightness
      PanelBackground {
        panel: root.windowRoot.brightnessPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Clock
      PanelBackground {
        panel: root.windowRoot.clockPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Control Center
      PanelBackground {
        panel: root.windowRoot.controlCenterPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Changelog
      PanelBackground {
        panel: root.windowRoot.changelogPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Launcher
      PanelBackground {
        panel: root.windowRoot.launcherPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Notification History
      PanelBackground {
        panel: root.windowRoot.notificationHistoryPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Session Menu
      PanelBackground {
        panel: root.windowRoot.sessionMenuPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: Settings.data.sessionMenu.largeButtonsStyle ? Color.transparent : panelBackgroundColor
      }

      // Settings
      PanelBackground {
        panel: root.windowRoot.settingsPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Setup Wizard
      PanelBackground {
        panel: root.windowRoot.setupWizardPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // TrayDrawer
      PanelBackground {
        panel: root.windowRoot.trayDrawerPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Wallpaper
      PanelBackground {
        panel: root.windowRoot.wallpaperPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBg ? panelBg.panelBackgroundColor : panelBackgroundColor
      }

      // WiFi
      PanelBackground {
        panel: root.windowRoot.wifiPanelPlaceholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Plugin Panel Slot 1
      PanelBackground {
        panel: root.windowRoot.pluginPanel1Placeholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }

      // Plugin Panel Slot 2
      PanelBackground {
        panel: root.windowRoot.pluginPanel2Placeholder
        shapeContainer: backgroundsShape
        backgroundColor: panelBackgroundColor
      }
    }

    // Apply shadow to the cached layer
    NDropShadow {
      anchors.fill: parent
      source: backgroundsShape
    }
  }
}
