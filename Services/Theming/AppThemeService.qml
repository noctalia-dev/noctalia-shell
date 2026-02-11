pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  Connections {
    target: WallpaperService

    // When the wallpaper changes, regenerate theme if necessary
    function onWallpaperChanged(screenName, path) {
      if (!Settings.data.colorSchemes.useWallpaperColors)
        return;

      var effectiveMonitor = Settings.data.colorSchemes.monitorForColors;
      if (effectiveMonitor === "" || effectiveMonitor === undefined) {
        effectiveMonitor = Screen.name;
      }

      if (screenName === effectiveMonitor) {
        generateFromWallpaper();
      }
    }
  }

  Connections {
    target: Settings.data.colorSchemes
    function onDarkModeChanged() {
      Logger.d("AppThemeService", "Detected dark mode change");
      generate();
    }
    function onMonitorForColorsChanged() {
      if (Settings.data.colorSchemes.useWallpaperColors) {
        Logger.d("AppThemeService", "Monitor for colors changed to:", Settings.data.colorSchemes.monitorForColors);
        generateFromWallpaper();
      }
    }
    function onGenerationMethodChanged() {
      Logger.d("AppThemeService", "Generation method changed to:", Settings.data.colorSchemes.generationMethod);
      generate();
    }
  }

  // PUBLIC FUNCTIONS
  function init() {
    Logger.i("AppThemeService", "Service started");
  }

  function generate() {
    if (Settings.data.colorSchemes.useWallpaperColors) {
      generateFromWallpaper();
    } else {
      // applyScheme will trigger template generation via schemeReader.onLoaded
      ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme);
    }
  }

  function generateFromWallpaper() {
    var effectiveMonitor = Settings.data.colorSchemes.monitorForColors;
    if (effectiveMonitor === "" || effectiveMonitor === undefined) {
      effectiveMonitor = Screen.name;
    }

    const wp = WallpaperService.getWallpaper(effectiveMonitor);
    if (!wp) {
      Logger.e("AppThemeService", "No wallpaper found for monitor:", effectiveMonitor);
      return;
    }
    const mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
    TemplateProcessor.processWallpaperColors(wp, mode);
  }

  function generateFromPredefinedScheme(schemeData) {
    Logger.i("AppThemeService", "Generating templates from predefined color scheme");
    const mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
    TemplateProcessor.processPredefinedScheme(schemeData, mode);
  }
}
