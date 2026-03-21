pragma Singleton
import Qt.labs.folderlistmodel

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  property var schemes: []
  property bool scanning: false
  property string schemesDirectory: Quickshell.shellDir + "/Assets/ColorScheme"
  property string downloadedSchemesDirectory: Settings.configDir + "colorschemes"
  readonly property string userSavedSchemeId: "User-saved-theme"
  property string colorsJsonFilePath: Settings.configDir + "colors.json"
  readonly property string gtkRefreshScript: Quickshell.shellDir + "/Scripts/python/src/theming/gtk-refresh.py"
  readonly property string templateProcessorScript: Quickshell.shellDir + "/Scripts/python/src/theming/template-processor.py"

  function pushSystemColorScheme() {
    const mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
    Quickshell.execDetached(["python3", gtkRefreshScript, "--appearance-only", mode]);
  }

  Connections {
    target: Settings.data.colorSchemes
    function onDarkModeChanged() {
      Logger.d("ColorScheme", "Detected dark mode change");
      if (!Settings.data.colorSchemes.useWallpaperColors && Settings.data.colorSchemes.predefinedScheme) {
        // Re-apply current scheme to pick the right variant
        applyScheme(Settings.data.colorSchemes.predefinedScheme);
      }
      root.pushSystemColorScheme();
      // Toast: dark/light mode switched
      const enabled = !!Settings.data.colorSchemes.darkMode;
      const label = enabled ? I18n.tr("tooltips.switch-to-dark-mode") : I18n.tr("tooltips.switch-to-light-mode");
      const description = I18n.tr("common.enabled");
      ToastService.showNotice(label, description, "dark-mode");
    }
  }

  // --------------------------------
  function init() {
    // does nothing but ensure the singleton is created
    // do not remove
    Logger.i("ColorScheme", "Service started");
    loadColorSchemes();
    Qt.callLater(pushSystemColorScheme);
  }

  function loadColorSchemes() {
    Logger.d("ColorScheme", "Load colorScheme");
    scanning = true;
    schemes = [];
    // Use find command to locate all scheme.json files in both directories
    // First ensure the downloaded schemes directory exists
    Quickshell.execDetached(["mkdir", "-p", downloadedSchemesDirectory]);
    // Find in both preinstalled and downloaded directories
    findProcess.command = ["find", "-L", schemesDirectory, downloadedSchemesDirectory, "-mindepth", "2", "-name", "*.json", "-type", "f"];
    findProcess.running = true;
  }

  function getBasename(path) {
    if (!path)
      return "";
    var chunks = path.split("/");
    // Get the filename without extension
    var filename = chunks[chunks.length - 1];
    var schemeName = filename.replace(".json", "");
    // Convert back to display names for special cases
    if (schemeName === "Noctalia-default") {
      return "Noctalia (default)";
    } else if (schemeName === "Noctalia-legacy") {
      return "Noctalia (legacy)";
    } else if (schemeName === "Tokyo-Night") {
      return "Tokyo Night";
    } else if (schemeName === "Rosepine") {
      return "Rose Pine";
    } else if (schemeName === userSavedSchemeId) {
      return I18n.tr("panels.color-scheme.user-saved-theme-name");
    }
    return schemeName;
  }

  function resolveSchemePath(nameOrPath) {
    if (!nameOrPath)
      return "";
    if (nameOrPath.indexOf("/") !== -1) {
      return nameOrPath;
    }
    // Handle special cases for Noctalia schemes
    var schemeName = nameOrPath.replace(".json", "");
    if (schemeName === "Noctalia (default)") {
      schemeName = "Noctalia-default";
    } else if (schemeName === "Noctalia (legacy)") {
      schemeName = "Noctalia-legacy";
    } else if (schemeName === "Tokyo Night") {
      schemeName = "Tokyo-Night";
    } else if (schemeName === "Rose Pine") {
      schemeName = "Rosepine";
    } else if (schemeName === I18n.tr("panels.color-scheme.user-saved-theme-name")) {
      schemeName = userSavedSchemeId;
    }
    // Check preinstalled directory first, then downloaded directory
    var preinstalledPath = schemesDirectory + "/" + schemeName + "/" + schemeName + ".json";
    var downloadedPath = downloadedSchemesDirectory + "/" + schemeName + "/" + schemeName + ".json";
    // Try to find the scheme in the loaded schemes list to determine which directory it's in
    for (var i = 0; i < schemes.length; i++) {
      if (schemes[i].indexOf("/" + schemeName + "/") !== -1 || schemes[i].indexOf("/" + schemeName + ".json") !== -1) {
        return schemes[i];
      }
    }
    // Fallback: prefer preinstalled, then downloaded
    return preinstalledPath;
  }

  function applyScheme(nameOrPath) {
    // Force reload by bouncing the path
    var filePath = resolveSchemePath(nameOrPath);
    schemeReader.path = "";
    schemeReader.path = filePath;
  }

  function setPredefinedScheme(schemeName) {
    Logger.i("ColorScheme", "Attempting to set predefined scheme to:", schemeName);

    var resolvedPath = resolveSchemePath(schemeName);
    var basename = getBasename(schemeName);

    // Check if the scheme actually exists in the loaded schemes list
    var schemeExists = false;
    for (var i = 0; i < schemes.length; i++) {
      if (getBasename(schemes[i]) === basename) {
        schemeExists = true;
        break;
      }
    }

    if (schemeExists) {
      Settings.data.colorSchemes.predefinedScheme = basename;
      applyScheme(schemeName);
      ToastService.showNotice(I18n.tr("panels.color-scheme.title"), basename, "settings-color-scheme");
    } else {
      Logger.e("ColorScheme", "Scheme not found:", schemeName);
      ToastService.showError(I18n.tr("panels.color-scheme.title"), `'${basename}' ` + I18n.tr("common.not-found"));
    }
  }

  function pickGeneratedColor(modeData, key, fallback) {
    if (modeData && modeData[key]) {
      return modeData[key];
    }
    return fallback;
  }

  function buildVariantFromGenerated(modeData) {
    return {
      "mPrimary": pickGeneratedColor(modeData, "primary", "#000000"),
      "mOnPrimary": pickGeneratedColor(modeData, "on_primary", "#000000"),
      "mSecondary": pickGeneratedColor(modeData, "secondary", "#000000"),
      "mOnSecondary": pickGeneratedColor(modeData, "on_secondary", "#000000"),
      "mTertiary": pickGeneratedColor(modeData, "tertiary", "#000000"),
      "mOnTertiary": pickGeneratedColor(modeData, "on_tertiary", "#000000"),
      "mError": pickGeneratedColor(modeData, "error", "#000000"),
      "mOnError": pickGeneratedColor(modeData, "on_error", "#000000"),
      "mSurface": pickGeneratedColor(modeData, "surface", "#000000"),
      "mOnSurface": pickGeneratedColor(modeData, "on_surface", "#000000"),
      "mSurfaceVariant": pickGeneratedColor(modeData, "surface_container", pickGeneratedColor(modeData, "surface_variant", "#000000")),
      "mOnSurfaceVariant": pickGeneratedColor(modeData, "on_surface_variant", "#000000"),
      "mOutline": pickGeneratedColor(modeData, "outline_variant", pickGeneratedColor(modeData, "outline", "#000000")),
      "mShadow": pickGeneratedColor(modeData, "shadow", pickGeneratedColor(modeData, "surface", "#000000")),
      "mHover": pickGeneratedColor(modeData, "tertiary", "#000000"),
      "mOnHover": pickGeneratedColor(modeData, "on_tertiary", "#000000")
    };
  }

  function buildTerminalSectionFromGenerated(modeData) {
    return {
      "foreground": pickGeneratedColor(modeData, "on_surface", "#ffffff"),
      "background": pickGeneratedColor(modeData, "surface", "#000000"),
      "selectionFg": pickGeneratedColor(modeData, "on_surface_variant", "#ffffff"),
      "selectionBg": pickGeneratedColor(modeData, "surface_variant", "#222222"),
      "cursorText": pickGeneratedColor(modeData, "surface", "#000000"),
      "cursor": pickGeneratedColor(modeData, "on_surface", "#ffffff"),
      "normal": {
        "black": pickGeneratedColor(modeData, "surface", "#000000"),
        "red": pickGeneratedColor(modeData, "error", "#ff5f5f"),
        "green": pickGeneratedColor(modeData, "primary", "#5fff87"),
        "yellow": pickGeneratedColor(modeData, "secondary", "#ffd75f"),
        "blue": pickGeneratedColor(modeData, "tertiary", "#5f87ff"),
        "magenta": pickGeneratedColor(modeData, "primary_fixed_dim", pickGeneratedColor(modeData, "primary", "#af5fff")),
        "cyan": pickGeneratedColor(modeData, "secondary_fixed_dim", pickGeneratedColor(modeData, "secondary", "#5fd7d7")),
        "white": pickGeneratedColor(modeData, "on_surface", "#d0d0d0")
      },
      "bright": {
        "black": pickGeneratedColor(modeData, "outline", "#303030"),
        "red": pickGeneratedColor(modeData, "error", "#ff5f5f"),
        "green": pickGeneratedColor(modeData, "primary", "#5fff87"),
        "yellow": pickGeneratedColor(modeData, "secondary", "#ffd75f"),
        "blue": pickGeneratedColor(modeData, "tertiary", "#5f87ff"),
        "magenta": pickGeneratedColor(modeData, "primary_fixed_dim", pickGeneratedColor(modeData, "primary", "#af5fff")),
        "cyan": pickGeneratedColor(modeData, "secondary_fixed_dim", pickGeneratedColor(modeData, "secondary", "#5fd7d7")),
        "white": pickGeneratedColor(modeData, "on_surface", "#ffffff")
      }
    };
  }

  function buildSavedSchemeMode(modeData) {
    var outVariant = buildVariantFromGenerated(modeData);
    outVariant.terminal = buildTerminalSectionFromGenerated(modeData);
    return outVariant;
  }

  function resolveWallpaperForThemeGeneration() {
    var effectiveMonitor = Settings.data.colorSchemes.monitorForColors;
    if (effectiveMonitor === "" || effectiveMonitor === undefined) {
      effectiveMonitor = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }
    return WallpaperService.getWallpaper(effectiveMonitor);
  }

  function saveCurrentAsUserScheme() {
    if (saveSchemeProcess.running || generateSchemeProcess.running)
      return;

    saveSchemeProcess.schemeDisplayName = I18n.tr("panels.color-scheme.user-saved-theme-name");
    saveSchemeProcess.schemePath = downloadedSchemesDirectory + "/" + userSavedSchemeId + "/" + userSavedSchemeId + ".json";

    var wallpaperPath = resolveWallpaperForThemeGeneration();
    if (!wallpaperPath) {
      Logger.e("ColorScheme", "Cannot save user scheme: wallpaper path missing");
      ToastService.showError(I18n.tr("panels.color-scheme.title"), I18n.tr("common.error"));
      return;
    }

    generateSchemeProcess.command = ["python3", templateProcessorScript, wallpaperPath, "--scheme-type", Settings.data.colorSchemes.generationMethod];
    generateSchemeProcess.running = true;
  }

  Process {
    id: findProcess
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        var output = stdout.text.trim();
        var files = output.split('\n').filter(function (line) {
          return line.length > 0;
        });
        files.sort(function (a, b) {
          var nameA = getBasename(a).toLowerCase();
          var nameB = getBasename(b).toLowerCase();
          return nameA.localeCompare(nameB);
        });
        schemes = files;
        scanning = false;
        Logger.d("ColorScheme", "Listed", schemes.length, "schemes");
        // Normalize stored scheme to basename and re-apply if necessary
        var stored = Settings.data.colorSchemes.predefinedScheme;
        if (stored) {
          var basename = getBasename(stored);
          if (basename !== stored) {
            Settings.data.colorSchemes.predefinedScheme = basename;
          }
          if (!Settings.data.colorSchemes.useWallpaperColors) {
            applyScheme(basename);
          }
        }
      } else {
        Logger.e("ColorScheme", "Failed to find color scheme files");
        schemes = [];
        scanning = false;
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  Process {
    id: generateSchemeProcess
    running: false

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("ColorScheme", "Failed to generate dark/light wallpaper palettes for user scheme");
        ToastService.showError(I18n.tr("panels.color-scheme.title"), I18n.tr("common.error"));
        return;
      }

      try {
        var generatedData = JSON.parse(stdout.text || "{}");
        var darkModeData = generatedData.dark || generatedData.light || {};
        var lightModeData = generatedData.light || generatedData.dark || {};

        saveSchemeProcess.schemePayload = {
          "dark": buildSavedSchemeMode(darkModeData),
          "light": buildSavedSchemeMode(lightModeData)
        };

        saveSchemeProcess.command = ["python3", "-c", "import json, pathlib, sys; p=pathlib.Path(sys.argv[1]); p.parent.mkdir(parents=True, exist_ok=True); p.write_text(json.dumps(json.loads(sys.argv[2]), indent=2) + '\\n', encoding='utf-8')", saveSchemeProcess.schemePath, JSON.stringify(saveSchemeProcess.schemePayload)];
        saveSchemeProcess.running = true;
      } catch (e) {
        Logger.e("ColorScheme", "Failed to parse generated wallpaper palettes:", e);
        ToastService.showError(I18n.tr("panels.color-scheme.title"), I18n.tr("common.error"));
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  Process {
    id: saveSchemeProcess
    running: false
    property string schemePath: ""
    property string schemeDisplayName: ""
    property var schemePayload: ({})

    onExited: function (exitCode) {
      if (exitCode === 0) {
        Logger.i("ColorScheme", "Saved user scheme:", schemePath);
        ToastService.showNotice(I18n.tr("panels.color-scheme.title"), I18n.tr("common.save") + ": " + schemeDisplayName, "settings-color-scheme");
        loadColorSchemes();
      } else {
        Logger.e("ColorScheme", "Failed to save user scheme:", schemePath);
        ToastService.showError(I18n.tr("panels.color-scheme.title"), I18n.tr("common.error"));
      }
    }
  }

  // Internal loader to read a scheme file
  FileView {
    id: schemeReader
    onLoaded: {
      try {
        var data = JSON.parse(text());
        var variant = data;
        // If scheme provides dark/light variants, pick based on settings
        if (data && (data.dark || data.light)) {
          if (Settings.data.colorSchemes.darkMode) {
            variant = data.dark || data.light;
          } else {
            variant = data.light || data.dark;
          }
        }
        writeColorsToDisk(variant);
        Logger.i("ColorScheme", "Applying color scheme:", getBasename(path));

        // Generate templates for predefined color schemes
        if (hasEnabledTemplates() || Settings.data.templates.enableUserTheming) {
          AppThemeService.generateFromPredefinedScheme(data);
        }
      } catch (e) {
        Logger.e("ColorScheme", "Failed to parse scheme JSON:", path, e);
      }
    }
  }

  // Check if any templates are enabled
  function hasEnabledTemplates() {
    const activeTemplates = Settings.data.templates.activeTemplates;
    if (!activeTemplates || activeTemplates.length === 0) {
      return false;
    }
    for (let i = 0; i < activeTemplates.length; i++) {
      if (activeTemplates[i].enabled) {
        return true;
      }
    }
    return false;
  }

  // Writer to colors.json using a JsonAdapter for safety
  FileView {
    id: colorsWriter
    path: colorsJsonFilePath
    printErrors: false
    onSaved:

    // Logger.i("ColorScheme", "Colors saved")
    {}
    JsonAdapter {
      id: out
      property color mPrimary: "#000000"
      property color mOnPrimary: "#000000"
      property color mSecondary: "#000000"
      property color mOnSecondary: "#000000"
      property color mTertiary: "#000000"
      property color mOnTertiary: "#000000"
      property color mError: "#000000"
      property color mOnError: "#000000"
      property color mSurface: "#000000"
      property color mOnSurface: "#000000"
      property color mSurfaceVariant: "#000000"
      property color mOnSurfaceVariant: "#000000"
      property color mOutline: "#000000"
      property color mShadow: "#000000"
      property color mHover: "#000000"
      property color mOnHover: "#000000"
    }
  }

  function writeColorsToDisk(obj) {
    function pick(o, a, b, fallback) {
      return (o && (o[a] || o[b])) || fallback;
    }
    out.mPrimary = pick(obj, "mPrimary", "primary", out.mPrimary);
    out.mOnPrimary = pick(obj, "mOnPrimary", "onPrimary", out.mOnPrimary);
    out.mSecondary = pick(obj, "mSecondary", "secondary", out.mSecondary);
    out.mOnSecondary = pick(obj, "mOnSecondary", "onSecondary", out.mOnSecondary);
    out.mTertiary = pick(obj, "mTertiary", "tertiary", out.mTertiary);
    out.mOnTertiary = pick(obj, "mOnTertiary", "onTertiary", out.mOnTertiary);
    out.mError = pick(obj, "mError", "error", out.mError);
    out.mOnError = pick(obj, "mOnError", "onError", out.mOnError);
    out.mSurface = pick(obj, "mSurface", "surface", out.mSurface);
    out.mOnSurface = pick(obj, "mOnSurface", "onSurface", out.mOnSurface);
    out.mSurfaceVariant = pick(obj, "mSurfaceVariant", "surfaceVariant", out.mSurfaceVariant);
    out.mOnSurfaceVariant = pick(obj, "mOnSurfaceVariant", "onSurfaceVariant", out.mOnSurfaceVariant);
    out.mOutline = pick(obj, "mOutline", "outline", out.mOutline);
    out.mShadow = pick(obj, "mShadow", "shadow", out.mShadow);
    out.mHover = pick(obj, "mHover", "hover", out.mHover);
    out.mOnHover = pick(obj, "mOnHover", "onHover", out.mOnHover);

    // Force a rewrite by updating the path
    colorsWriter.path = "";
    colorsWriter.path = colorsJsonFilePath;
    colorsWriter.writeAdapter();
  }
}
