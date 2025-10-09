pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import "../Helpers/ColorVariants.js" as ColorVariants

Singleton {
  id: root

  readonly property string colorsApplyScript: Quickshell.shellDir + '/Bin/colors-apply.sh'

  property string dynamicConfigPath: Settings.cacheDir + "matugen.dynamic.toml"

  // External state management
  Connections {
    target: WallpaperService
    function onWallpaperChanged(screenName, path) {
      // Only detect changes on main screen
      if (screenName === Screen.name && Settings.data.colorSchemes.useWallpaperColors) {
        generateFromWallpaper()
      }
    }
  }

  Connections {
    target: Settings.data.colorSchemes
    function onDarkModeChanged() {
      Logger.log("Matugen", "Detected dark mode change")
      if (Settings.data.colorSchemes.useWallpaperColors) {
        MatugenService.generateFromWallpaper()
      }
    }
  }

  // --------------------------------
  function init() {
    // does nothing but ensure the singleton is created
    // do not remove
    Logger.log("Matugen", "Service started")
  }

  // --------------------------------
  // Convert predefined color scheme to Matugen format
  function convertPredefinedSchemeToMatugen(schemeData) {
    var variant = schemeData
    // If scheme provides dark/light variants, pick based on settings
    if (schemeData && (schemeData.dark || schemeData.light)) {
      if (Settings.data.colorSchemes.darkMode) {
        variant = schemeData.dark || schemeData.light
      } else {
        variant = schemeData.light || schemeData.dark
      }
    }

    // Helper function to strip # from hex colors
    function stripHex(color) {
      return color.toString().replace('#', '')
    }

    // Helper function to create color object with both color and hex_stripped properties
    function createColorObj(colorValue) {
      return {
        "color": colorValue,
        "hex": colorValue,
        "hex_stripped": stripHex(colorValue)
      }
    }

    // Map predefined scheme colors to Matugen color structure - only core Material 3 colors
    var matugenColors = {
      "colors": {
        "background": {
          "light": createColorObj(variant.mSurface),
          "default": createColorObj(variant.mSurface),
          "dark": createColorObj(variant.mSurface)
        },
        "primary": {
          "light": createColorObj(variant.mPrimary),
          "default": createColorObj(variant.mPrimary),
          "dark": createColorObj(variant.mPrimary)
        },
        "on_primary": {
          "light": createColorObj(variant.mOnPrimary),
          "default": createColorObj(variant.mOnPrimary),
          "dark": createColorObj(variant.mOnPrimary)
        },
        "secondary": {
          "light": createColorObj(variant.mSecondary),
          "default": createColorObj(variant.mSecondary),
          "dark": createColorObj(variant.mSecondary)
        },
        "on_secondary": {
          "light": createColorObj(variant.mOnSecondary),
          "default": createColorObj(variant.mOnSecondary),
          "dark": createColorObj(variant.mOnSecondary)
        },
        "tertiary": {
          "light": createColorObj(variant.mTertiary),
          "default": createColorObj(variant.mTertiary),
          "dark": createColorObj(variant.mTertiary)
        },
        "on_tertiary": {
          "light": createColorObj(variant.mOnTertiary),
          "default": createColorObj(variant.mOnTertiary),
          "dark": createColorObj(variant.mOnTertiary)
        },
        "error": {
          "light": createColorObj(variant.mError),
          "default": createColorObj(variant.mError),
          "dark": createColorObj(variant.mError)
        },
        "on_error": {
          "light": createColorObj(variant.mOnError),
          "default": createColorObj(variant.mOnError),
          "dark": createColorObj(variant.mOnError)
        },
        "surface": {
          "light": createColorObj(variant.mSurface),
          "default": createColorObj(variant.mSurface),
          "dark": createColorObj(variant.mSurface)
        },
        "on_surface": {
          "light": createColorObj(variant.mOnSurface),
          "default": createColorObj(variant.mOnSurface),
          "dark": createColorObj(variant.mOnSurface)
        },
        "surface_variant": {
          "light": createColorObj(variant.mSurfaceVariant),
          "default": createColorObj(variant.mSurfaceVariant),
          "dark": createColorObj(variant.mSurfaceVariant)
        },
        "on_surface_variant": {
          "light": createColorObj(variant.mOnSurfaceVariant),
          "default": createColorObj(variant.mOnSurfaceVariant),
          "dark": createColorObj(variant.mOnSurfaceVariant)
        },
        "outline": {
          "light": createColorObj(variant.mOutline),
          "default": createColorObj(variant.mOutline),
          "dark": createColorObj(variant.mOutline)
        },
        "primary_fixed_dim": {
          "light": createColorObj(ColorVariants.generateFixedDim(variant.mPrimary)),
          "default": createColorObj(ColorVariants.generateFixedDim(variant.mPrimary)),
          "dark": createColorObj(ColorVariants.generateFixedDim(variant.mPrimary))
        },
        "secondary_fixed_dim": {
          "light": createColorObj(ColorVariants.generateFixedDim(variant.mSecondary)),
          "default": createColorObj(ColorVariants.generateFixedDim(variant.mSecondary)),
          "dark": createColorObj(ColorVariants.generateFixedDim(variant.mSecondary))
        },
        "tertiary_fixed_dim": {
          "light": createColorObj(ColorVariants.generateFixedDim(variant.mTertiary)),
          "default": createColorObj(ColorVariants.generateFixedDim(variant.mTertiary)),
          "dark": createColorObj(ColorVariants.generateFixedDim(variant.mTertiary))
        },
        "surface_bright": {
          "light": createColorObj(ColorVariants.generateBright(variant.mSurface)),
          "default": createColorObj(ColorVariants.generateBright(variant.mSurface)),
          "dark": createColorObj(ColorVariants.generateBright(variant.mSurface))
        },
        "surface_variant_bright": {
          "light": createColorObj(ColorVariants.generateBright(variant.mSurfaceVariant)),
          "default": createColorObj(ColorVariants.generateBright(variant.mSurfaceVariant)),
          "dark": createColorObj(ColorVariants.generateBright(variant.mSurfaceVariant))
        },
        "primary_container": {
          "light": createColorObj(ColorVariants.generateContainer(variant.mPrimary, false)),
          "default": createColorObj(ColorVariants.generateContainer(variant.mPrimary, true)),
          "dark": createColorObj(ColorVariants.generateContainer(variant.mPrimary, true))
        },
        "secondary_container": {
          "light": createColorObj(ColorVariants.generateContainer(variant.mSecondary, false)),
          "default": createColorObj(ColorVariants.generateContainer(variant.mSecondary, true)),
          "dark": createColorObj(ColorVariants.generateContainer(variant.mSecondary, true))
        },
        "tertiary_container": {
          "light": createColorObj(ColorVariants.generateContainer(variant.mTertiary, false)),
          "default": createColorObj(ColorVariants.generateContainer(variant.mTertiary, true)),
          "dark": createColorObj(ColorVariants.generateContainer(variant.mTertiary, true))
        },
        "on_primary_container": {
          "light": createColorObj(ColorVariants.generateContainer(variant.mOnPrimary, false)),
          "default": createColorObj(ColorVariants.generateContainer(variant.mOnPrimary, true)),
          "dark": createColorObj(ColorVariants.generateContainer(variant.mOnPrimary, true))
        },
        "on_secondary_container": {
          "light": createColorObj(ColorVariants.generateContainer(variant.mOnSecondary, false)),
          "default": createColorObj(ColorVariants.generateContainer(variant.mOnSecondary, true)),
          "dark": createColorObj(ColorVariants.generateContainer(variant.mOnSecondary, true))
        },
        "on_tertiary_container": {
          "light": createColorObj(ColorVariants.generateContainer(variant.mOnTertiary, false)),
          "default": createColorObj(ColorVariants.generateContainer(variant.mOnTertiary, true)),
          "dark": createColorObj(ColorVariants.generateContainer(variant.mOnTertiary, true))
        },
        "surface_container": {
          "light": createColorObj(ColorVariants.generateContainer(variant.mSurface, false)),
          "default": createColorObj(ColorVariants.generateContainer(variant.mSurface, true)),
          "dark": createColorObj(ColorVariants.generateContainer(variant.mSurface, true))
        }
      }
    }

    return JSON.stringify(matugenColors)
  }

  // --------------------------------
  // Generate colors using current wallpaper and settings
  function generateFromWallpaper() {
    Logger.log("Matugen", "Generating from wallpaper on screen:", Screen.name)
    var wp = WallpaperService.getWallpaper(Screen.name).replace(/'/g, "'\\''")
    if (wp === "") {
      Logger.error("Matugen", "No wallpaper was found")
      return
    }

    var content = MatugenTemplates.buildConfigToml()
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    var pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")
    var extraRepo = (Quickshell.shellDir + "/Assets/Matugen/extra").replace(/'/g, "'\\''")
    var extraUser = (Settings.configDir + "matugen.d").replace(/'/g, "'\\''")

    // Build the main script
    var script = "cat > '" + pathEsc + "' << 'EOF'\n" + content + "EOF\n" + "for d in '" + extraRepo + "' '" + extraUser + "'; do\n" + "  if [ -d \"$d\" ]; then\n" + "    for f in \"$d\"/*.toml; do\n" + "      [ -f \"$f\" ] && { echo; echo \"# extra: $f\"; cat \"$f\"; } >> '" + pathEsc + "'\n" + "    done\n" + "  fi\n"
        + "done\n" + "matugen image '" + wp + "' --config '" + pathEsc + "' --mode " + mode + " --type " + Settings.data.colorSchemes.matugenSchemeType

    // Add user config execution if enabled
    if (Settings.data.templates.enableUserTemplates) {
      var userConfigDir = (Quickshell.env("HOME") + "/.config/matugen/").replace(/'/g, "'\\''")
      script += "\n# Execute user config if it exists\nif [ -f '" + userConfigDir + "config.toml' ]; then\n"
      script += "  matugen image '" + wp + "' --config '" + userConfigDir + "config.toml' --mode " + mode + " --type " + Settings.data.colorSchemes.matugenSchemeType + "\n"
      script += "fi"
    }

    script += "\n"
    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  // --------------------------------
  // Generate templates from predefined color scheme
  function generateFromPredefinedScheme(schemeData) {
    Logger.log("Matugen", "Generating templates from predefined color scheme")

    var content = MatugenTemplates.buildConfigToml()
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    var pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")
    var extraRepo = (Quickshell.shellDir + "/Assets/Matugen/extra").replace(/'/g, "'\\''")
    var extraUser = (Settings.configDir + "matugen.d").replace(/'/g, "'\\''")

    // Convert predefined scheme to Matugen format
    var matugenJson = convertPredefinedSchemeToMatugen(schemeData)
    var jsonPath = Settings.cacheDir + "matugen.import.json"
    var jsonPathEsc = jsonPath.replace(/'/g, "'\\''")

    // Build the script
    var script = ""
    script += "cat > '" + pathEsc + "' << 'EOF'\n" + content + "EOF\n"
    script += "for d in '" + extraRepo + "' '" + extraUser + "'; do\n"
    script += "  if [ -d \"$d\" ]; then\n"
    script += "    for f in \"$d\"/*.toml; do\n"
    script += "      [ -f \"$f\" ] && { echo; echo \"# extra: $f\"; cat \"$f\"; } >> '" + pathEsc + "'\n"
    script += "    done\n"
    script += "  fi\n"
    script += "done\n"
    script += "matugen image --import-json '" + jsonPathEsc + "' --config '" + pathEsc + "' --mode " + mode + " '" + Quickshell.shellDir + "/Assets/Wallpaper/noctalia.png'"

    // Add user config execution if enabled
    if (Settings.data.templates.enableUserTemplates) {
      var userConfigDir = (Quickshell.env("HOME") + "/.config/matugen/").replace(/'/g, "'\\''")
      script += "\n# Execute user config if it exists\nif [ -f '" + userConfigDir + "config.toml' ]; then\n"
      script += "  matugen image --import-json '" + jsonPathEsc + "' --config '" + userConfigDir + "config.toml' --mode " + mode + " '" + Quickshell.shellDir + "/Assets/Wallpaper/noctalia.png'\n"
      script += "fi"
    }

    script += "\n"
    generateProcess.command = ["bash", "-lc", script]

    // Write JSON file with our custom colors
    // once written matugen will be executed via 'generateProcess'
    jsonWriter.path = jsonPath
    jsonWriter.setText(matugenJson)

    // -----
    // For terminals simply copy the full color from theme from iTerm2 so everything looks super nice!
    var copyCmd = ""
    if (Settings.data.templates.foot) {
      if (copyCmd !== "")
        copyCmd += " ; "
      copyCmd += `cp -f ${getTerminalColorsTemplate('foot')} ~/.config/foot/themes/noctalia`
      copyCmd += ` ; ${colorsApplyScript} foot`
    }

    if (Settings.data.templates.ghostty) {
      if (copyCmd !== "")
        copyCmd += " ; "
      copyCmd += `cp -f ${getTerminalColorsTemplate('ghostty')} ~/.config/ghostty/themes/noctalia`
      copyCmd += ` ; ${colorsApplyScript} ghostty`
    }

    if (Settings.data.templates.kitty) {
      if (copyCmd !== "")
        copyCmd += " ; "
      copyCmd += `cp -f ${getTerminalColorsTemplate('kitty')}.conf ~/.config/kitty/themes/noctalia.conf`
      copyCmd += ` ; ${colorsApplyScript} kitty`
    }

    // Finally execute all copies at once.
    if (copyCmd !== "") {
      //console.log(copyCmd)
      copyProcess.command = ["bash", "-lc", copyCmd]
      copyProcess.running = true
    }
  }

  // --------------------------------
  function getTerminalColorsTemplate(terminal) {
    var colorScheme = Settings.data.colorSchemes.predefinedScheme
    const darkLight = Settings.data.colorSchemes.darkMode ? 'dark' : 'light'

    // Convert display names back to folder names
    if (colorScheme === "Noctalia (default)") {
      colorScheme = "Noctalia-default"
    } else if (colorScheme === "Noctalia (legacy)") {
      colorScheme = "Noctalia-legacy"
    } else if (colorScheme === "Tokyo Night") {
      colorScheme = "Tokyo-Night"
    }

    return `${Quickshell.shellDir}/Assets/ColorScheme/${colorScheme}/terminal/${terminal}/${colorScheme}-${darkLight}`
  }

  // --------------------------------
  // File writer for JSON import file
  FileView {
    id: jsonWriter
    onSaved: {
      Logger.log("Matugen", "JSON import file written successfully")
      // Run matugen command after JSON file is written
      generateProcess.running = true
    }
    onSaveFailed: {
      Logger.error("Matugen", "Failed to write JSON import file:", error)
    }
  }

  // --------------------------------
  Process {
    id: generateProcess
    workingDirectory: Quickshell.shellDir
    running: false
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text !== "") {
          Logger.warn("MatugenService", "GenerateProcess stderr:", this.text)
        }
      }
    }
  }

  // --------------------------------
  Process {
    id: copyProcess
    running: false
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text !== "") {
          Logger.warn("MatugenService", "CopyProcess stderr:", this.text)
        }
      }
    }
  }
}
