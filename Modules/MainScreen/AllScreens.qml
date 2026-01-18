import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Noctalia
import qs.Services.UI

// ------------------------------
// MainScreen for each screen (manages bar + all panels)
// Wrapped in Loader to optimize memory - only loads when screen needs it
Variants {
  model: Quickshell.screens
  delegate: Item {
    required property ShellScreen modelData

    property bool shouldBeActive: {
      if (!modelData || !modelData.name) {
        return false;
      }

      let shouldLoad = true;
      if (!Settings.data.general.allowPanelsOnScreenWithoutBar) {
        // Check if bar is configured for this screen
        var monitors = Settings.data.bar.monitors || [];
        shouldLoad = monitors.length === 0 || monitors.includes(modelData?.name);
      }

      if (shouldLoad) {
        Logger.d("AllScreens", "Screen activated: ", modelData?.name);
      }
      return shouldLoad;
    }

    property bool windowLoaded: false

    // Main Screen loader - Bar and panels backgrounds
    Loader {
      id: windowLoader
      active: parent.shouldBeActive && PluginService.pluginsFullyLoaded
      asynchronous: false

      property ShellScreen loaderScreen: modelData

      onLoaded: {
        // Signal that window is loaded so exclusion zone can be created
        parent.windowLoaded = true;
      }

      sourceComponent: MainScreen {
        screen: windowLoader.loaderScreen
      }
    }

    // Bar content in separate windows to prevent fullscreen redraws
    Loader {
      active: {
        if (!parent.windowLoaded || !parent.shouldBeActive || !BarService.effectivelyVisible)
          return false;

        // Check if bar is configured for this screen
        var monitors = Settings.data.bar.monitors || [];
        return monitors.length === 0 || monitors.includes(modelData?.name);
      }
      asynchronous: false

      sourceComponent: BarContentWindow {
        screen: modelData
      }

      onLoaded: {
        Logger.d("AllScreens", "BarContentWindow created for", modelData?.name);
      }
    }

    // BarExclusionZone - created after MainScreen has fully loaded
    // Disabled when bar is hidden or not configured for this screen
    Loader {
      active: {
        if (!parent.windowLoaded || !parent.shouldBeActive || !BarService.isVisible)
          return false;

        // Check if bar is configured for this screen
        var monitors = Settings.data.bar.monitors || [];
        return monitors.length === 0 || monitors.includes(modelData?.name);
      }
      asynchronous: false

      sourceComponent: BarExclusionZone {
        screen: modelData
      }

      onLoaded: {
        Logger.d("AllScreens", "BarExclusionZone created for", modelData?.name);
      }
    }

    // PopupMenuWindow - reusable popup window for both tray menus and context menus
    // Disabled when bar is hidden or not configured for this screen
    Loader {
      active: {
        if (!parent.windowLoaded || !parent.shouldBeActive || !BarService.effectivelyVisible)
          return false;

        // Check if bar is configured for this screen
        var monitors = Settings.data.bar.monitors || [];
        return monitors.length === 0 || monitors.includes(modelData?.name);
      }
      asynchronous: false

      sourceComponent: PopupMenuWindow {
        screen: modelData
      }

      onLoaded: {
        Logger.d("AllScreens", "PopupMenuWindow created for", modelData?.name);
      }
    }
  }
}
