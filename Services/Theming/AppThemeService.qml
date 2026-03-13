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
      var effectiveMonitor = Settings.data.colorSchemes.monitorForColors;
      if (effectiveMonitor === "" || effectiveMonitor === undefined) {
        effectiveMonitor = Screen.name;
      }

      if (screenName !== effectiveMonitor)
        return;

      if (Settings.data.colorSchemes.useWallpaperColors) {
        generateFromWallpaper();
      } else {
        // Re-run predefined scheme templates so {{image}} reflects the new wallpaper path
        ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme);
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
    function onWallpaperForegroundModeChanged() {
      Logger.d("AppThemeService", "Wallpaper foreground mode changed to:", Settings.data.colorSchemes.wallpaperForegroundMode);
      generate();
    }
    function onWallpaperForegroundSourceSchemeChanged() {
      if (Settings.data.colorSchemes.useWallpaperColors && (Settings.data.colorSchemes.wallpaperForegroundMode === "static" || Settings.data.colorSchemes.wallpaperForegroundMode === "app-static")) {
        Logger.d("AppThemeService", "Static foreground source changed to:", Settings.data.colorSchemes.wallpaperForegroundSourceScheme || "Noctalia (default)");
        generate();
      }
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
    var effectiveMonitor = Settings.data.colorSchemes.monitorForColors;
    if (effectiveMonitor === "" || effectiveMonitor === undefined) {
      effectiveMonitor = Screen.name;
    }
    const wallpaperPath = WallpaperService.getWallpaper(effectiveMonitor) || "";
    TemplateProcessor.processPredefinedScheme(schemeData, mode, wallpaperPath);
  }
}
