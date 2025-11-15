import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.Commons
import qs.Services.UI
import qs.Modules.MainScreen

// ------------------------------
// MainScreen for each screen (manages bar + all panels)
// Wrapped in Loader to optimize memory - only loads when screen needs it
Variants {
  model: Quickshell.screens
  delegate: Item {
    required property ShellScreen modelData

    property bool shouldBeActive: {
      if (!modelData || !modelData.name) {
        return false
      }
      Logger.d("Shell", "MainScreen activated for", modelData?.name)
      return true
    }

    property bool windowLoaded: false

    Loader {
      id: windowLoader
      active: parent.shouldBeActive
      asynchronous: false

      property ShellScreen loaderScreen: modelData

      onLoaded: {
        // Signal that window is loaded so exclusion zone can be created
        parent.windowLoaded = true
      }

      sourceComponent: MainScreen {
        screen: windowLoader.loaderScreen
      }
    }

    // Bar content in separate windows to prevent fullscreen redraws
    Loader {
      active: {
        if (!parent.windowLoaded || !parent.shouldBeActive || !BarService.isVisible)
          return false

        // Check if bar is configured for this screen
        var monitors = Settings.data.bar.monitors || []
        return monitors.length === 0 || monitors.includes(modelData?.name)
      }
      asynchronous: false

      sourceComponent: BarContentWindow {
        screen: modelData
      }

      onLoaded: {
        Logger.d("Shell", "BarContentWindow created for", modelData?.name)
      }
    }

    // BarExclusionZone - created after MainScreen has fully loaded
    // Disabled when bar is hidden or not configured for this screen
    Loader {
      active: {
        if (!parent.windowLoaded || !parent.shouldBeActive || !BarService.isVisible)
          return false

        // Check if bar is configured for this screen
        var monitors = Settings.data.bar.monitors || []
        return monitors.length === 0 || monitors.includes(modelData?.name)
      }
      asynchronous: false

      sourceComponent: BarExclusionZone {
        screen: modelData
      }

      onLoaded: {
        Logger.d("Shell", "BarExclusionZone created for", modelData?.name)
      }
    }

    // TrayMenuWindow - separate window for tray context menus
    // This must be a top-level PanelWindow.
    Loader {
      active: parent.windowLoaded && parent.shouldBeActive
      asynchronous: false

      sourceComponent: TrayMenuWindow {
        screen: modelData
      }

      onLoaded: {
        Logger.d("Shell", "TrayMenuWindow created for", modelData?.name)
      }
    }
  }
}
