pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  readonly property string colorsApplyScript: Quickshell.shellDir + '/Scripts/theming/template-apply.sh'

  Connections {
    target: WallpaperService

    // When the wallpaper changes, regenerate theme if necessary
    function onWallpaperChanged(screenName, path) {
      if (screenName === Screen.name && Settings.data.colorSchemes.useWallpaperColors) {
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
    const wp = WallpaperService.getWallpaper(Screen.name);
    if (!wp) {
      Logger.e("AppThemeService", "No wallpaper found");
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
