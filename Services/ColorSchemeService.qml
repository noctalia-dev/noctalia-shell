pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services

Singleton {
  id: root

  property var schemes: []
  property bool scanning: false
  property string schemesDirectory: Quickshell.shellDir + "/Assets/ColorScheme"
  property string colorsJsonFilePath: Settings.configDir + "colors.json"

  Connections {
    target: Settings.data.colorSchemes
    function onDarkModeChanged() {
      Logger.i("ColorScheme", "Detected dark mode change")
      if (!Settings.data.colorSchemes.useWallpaperColors && Settings.data.colorSchemes.predefinedScheme) {
        // Re-apply current scheme to pick the right variant
        applyScheme(Settings.data.colorSchemes.predefinedScheme)
      }
      // Toast: dark/light mode switched
      const enabled = !!Settings.data.colorSchemes.darkMode
      const label = enabled ? "Dark mode" : "Light mode"
      const description = enabled ? "Enabled" : "Enabled"
      ToastService.showNotice(label, description, "dark-mode")
    }
  }

  // --------------------------------
  function init() {
    // does nothing but ensure the singleton is created
    // do not remove
    Logger.i("ColorScheme", "Service started")
    loadColorSchemes()
  }

  function loadColorSchemes() {
    Logger.d("ColorScheme", "Load colorScheme")
    scanning = true
    schemes = []
    // Use find command to locate all scheme.json files
    findProcess.command = ["find", schemesDirectory, "-name", "*.json", "-type", "f"]
    findProcess.running = true
  }

  function getBasename(path) {
    if (!path)
      return ""
    var chunks = path.split("/")
    // Get the filename without extension
    var filename = chunks[chunks.length - 1]
    var schemeName = filename.replace(".json", "")
    // Convert back to display names for special cases
    if (schemeName === "Noctalia-default") {
      return "Noctalia (default)"
    } else if (schemeName === "Noctalia-legacy") {
      return "Noctalia (legacy)"
    } else if (schemeName === "Tokyo-Night") {
      return "Tokyo Night"
    }
    return schemeName
  }

  function resolveSchemePath(nameOrPath) {
    if (!nameOrPath)
      return ""
    if (nameOrPath.indexOf("/") !== -1) {
      return nameOrPath
    }
    // Handle special cases for Noctalia schemes
    var schemeName = nameOrPath.replace(".json", "")
    if (schemeName === "Noctalia (default)") {
      schemeName = "Noctalia-default"
    } else if (schemeName === "Noctalia (legacy)") {
      schemeName = "Noctalia-legacy"
    } else if (schemeName === "Tokyo Night") {
      schemeName = "Tokyo-Night"
    }
    return schemesDirectory + "/" + schemeName + "/" + schemeName + ".json"
  }

  function applyScheme(nameOrPath) {
    // Force reload by bouncing the path
    var filePath = resolveSchemePath(nameOrPath)
    schemeReader.path = ""
    schemeReader.path = filePath
  }

  function setPredefinedScheme(schemeName) {
    Logger.i("ColorScheme", "Attempting to set predefined scheme to:", schemeName)

    var resolvedPath = resolveSchemePath(schemeName)
    var basename = getBasename(schemeName)

    // Check if the scheme actually exists in the loaded schemes list
    var schemeExists = false
    for (var i = 0; i < schemes.length; i++) {
      if (getBasename(schemes[i]) === basename) {
        schemeExists = true
        break
      }
    }

    if (schemeExists) {
      Settings.data.colorSchemes.predefinedScheme = basename
      applyScheme(schemeName)
      ToastService.showNotice("Color Scheme", `Set to ${basename}`, "settings-color-scheme")
    } else {
      Logger.e("ColorScheme", "Scheme not found:", schemeName)
      ToastService.showError("Color Scheme", `Scheme '${basename}' not found!`)
    }
  }

  Process {
    id: findProcess
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        var output = stdout.text.trim()
        var files = output.split('\n').filter(function (line) {
          return line.length > 0
        })
        files.sort(function (a, b) {
          var nameA = getBasename(a).toLowerCase()
          var nameB = getBasename(b).toLowerCase()
          return nameA.localeCompare(nameB)
        })
        schemes = files
        scanning = false
        Logger.d("ColorScheme", "Listed", schemes.length, "schemes")
        // Normalize stored scheme to basename and re-apply if necessary
        var stored = Settings.data.colorSchemes.predefinedScheme
        if (stored) {
          var basename = getBasename(stored)
          if (basename !== stored) {
            Settings.data.colorSchemes.predefinedScheme = basename
          }
          if (!Settings.data.colorSchemes.useWallpaperColors) {
            applyScheme(basename)
          }
        }
      } else {
        Logger.e("ColorScheme", "Failed to find color scheme files")
        schemes = []
        scanning = false
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // Internal loader to read a scheme file
  FileView {
    id: schemeReader
    onLoaded: {
      try {
        var data = JSON.parse(text())
        var variant = data
        // If scheme provides dark/light variants, pick based on settings
        if (data && (data.dark || data.light)) {
          if (Settings.data.colorSchemes.darkMode) {
            variant = data.dark || data.light
          } else {
            variant = data.light || data.dark
          }
        }
        writeColorsToDisk(variant)
        Logger.i("ColorScheme", "Applying color scheme:", getBasename(path))

        // Generate Matugen templates if any are enabled and setting allows it
        if (Settings.data.colorSchemes.generateTemplatesForPredefined && hasEnabledTemplates()) {
          AppThemeService.generateFromPredefinedScheme(data)
        }
      } catch (e) {
        Logger.e("ColorScheme", "Failed to parse scheme JSON:", path, e)
      }
    }
  }

  // Check if any templates are enabled
  function hasEnabledTemplates() {
    const templates = Settings.data.templates
    for (const key in templates) {
      if (templates[key]) {
        return true
      }
    }
    return false
  }

  // Writer to colors.json using a JsonAdapter for safety
  FileView {
    id: colorsWriter
    path: colorsJsonFilePath
    onSaved: {

      // Logger.i("ColorScheme", "Colors saved")
    }
    JsonAdapter {
      id: out
      property color mPrimary: "#000000"
      property color mOnPrimary: "#000000"
      property color mSecondary: "#000000"
      property color mOnSecondary: "#000000"
      property color mTertiary: "#000000"
      property color mOnTertiary: "#000000"
      property color mError: "#ff0000"
      property color mOnError: "#000000"
      property color mSurface: "#ffffff"
      property color mOnSurface: "#000000"
      property color mSurfaceVariant: "#cccccc"
      property color mOnSurfaceVariant: "#333333"
      property color mOutline: "#444444"
      property color mShadow: "#000000"
    }
  }

  function writeColorsToDisk(obj) {
    function pick(o, a, b, fallback) {
      return (o && (o[a] || o[b])) || fallback
    }
    out.mPrimary = pick(obj, "mPrimary", "primary", out.mPrimary)
    out.mOnPrimary = pick(obj, "mOnPrimary", "onPrimary", out.mOnPrimary)
    out.mSecondary = pick(obj, "mSecondary", "secondary", out.mSecondary)
    out.mOnSecondary = pick(obj, "mOnSecondary", "onSecondary", out.mOnSecondary)
    out.mTertiary = pick(obj, "mTertiary", "tertiary", out.mTertiary)
    out.mOnTertiary = pick(obj, "mOnTertiary", "onTertiary", out.mOnTertiary)
    out.mError = pick(obj, "mError", "error", out.mError)
    out.mOnError = pick(obj, "mOnError", "onError", out.mOnError)
    out.mSurface = pick(obj, "mSurface", "surface", out.mSurface)
    out.mOnSurface = pick(obj, "mOnSurface", "onSurface", out.mOnSurface)
    out.mSurfaceVariant = pick(obj, "mSurfaceVariant", "surfaceVariant", out.mSurfaceVariant)
    out.mOnSurfaceVariant = pick(obj, "mOnSurfaceVariant", "onSurfaceVariant", out.mOnSurfaceVariant)
    out.mOutline = pick(obj, "mOutline", "outline", out.mOutline)
    out.mShadow = pick(obj, "mShadow", "shadow", out.mShadow)

    // Force a rewrite by updating the path
    colorsWriter.path = ""
    colorsWriter.path = colorsJsonFilePath
    colorsWriter.writeAdapter()
  }
}
