pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import "../Helpers/ColorsConvert.js" as ColorsConvert

Singleton {
  id: root

  readonly property string colorsApplyScript: Quickshell.shellDir + '/Bin/colors-apply.sh'
  readonly property string dynamicConfigPath: Settings.cacheDir + "matugen.dynamic.toml"
  readonly property var terminalPaths: ({
                                          "foot": "~/.config/foot/themes/noctalia",
                                          "ghostty": "~/.config/ghostty/themes/noctalia",
                                          "kitty": "~/.config/kitty/themes/noctalia.conf"
                                        })

  readonly property var schemeNameMap: ({
                                          "Noctalia (default)": "Noctalia-default",
                                          "Noctalia (legacy)": "Noctalia-legacy",
                                          "Tokyo Night": "Tokyo-Night"
                                        })
  readonly property var predefinedTemplateConfigs: ({
                                                      "gtk": {
                                                        "input": "gtk.css",
                                                        "outputs": [{
                                                            "path": "~/.config/gtk-3.0/gtk.css"
                                                          }, {
                                                            "path": "~/.config/gtk-4.0/gtk.css"
                                                          }],
                                                        "postProcess": mode => `gsettings set org.gnome.desktop.interface color-scheme prefer-${mode}\n`
                                                      },
                                                      "qt": {
                                                        "input": "qtct.conf",
                                                        "outputs": [{
                                                            "path": "~/.config/qt5ct/colors/noctalia.conf"
                                                          }, {
                                                            "path": "~/.config/qt6ct/colors/noctalia.conf"
                                                          }]
                                                      },
                                                      "fuzzel": {
                                                        "input": "fuzzel.conf",
                                                        "outputs": [{
                                                            "path": "~/.config/fuzzel/themes/noctalia"
                                                          }],
                                                        "postProcess": () => `${colorsApplyScript} fuzzel\n`
                                                      },
                                                      "pywalfox": {
                                                        "input": "pywalfox.json",
                                                        "outputs": [{
                                                            "path": "~/.cache/wal/colors.json"
                                                          }],
                                                        "postProcess": () => `${colorsApplyScript} pywalfox\n`
                                                      },
                                                      "vesktop": {
                                                        "input": "vesktop.css",
                                                        "outputs": [{
                                                            "path": "~/.config/vesktop/themes/noctalia.theme.css"
                                                          }]
                                                      }
                                                    })

  Connections {
    target: WallpaperService
    function onWallpaperChanged(screenName, path) {
      // Only regenerate for the primary screen to avoid multiple regenerations
      if (Quickshell.screens.length > 0 && screenName === Quickshell.screens[0].name && Settings.data.colorSchemes.useWallpaperColors) {
        generateFromWallpaper(screenName)
      }
    }
  }

  Connections {
    target: Settings.data.colorSchemes
    function onDarkModeChanged() {
      Logger.log("AppThemeService", "Detected dark mode change")
      AppThemeService.generate()
    }
  }

  // --------------------------------------------------------------------------------
  function init() {
    Logger.log("AppThemeService", "Service started")
  }

  function generate() {
    if (Settings.data.colorSchemes.useWallpaperColors) {
      // Use primary screen when called without a specific screen
      const screenName = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
      generateFromWallpaper(screenName)
    } else {
      generateFromPredefinedScheme()
    }
  }

  // --------------------------------------------------------------------------------
  // Wallpaper Colors Generation
  // --------------------------------------------------------------------------------
  function generateFromWallpaper(screenName) {
    if (!screenName) {
      Logger.error("AppThemeService", "No screen name provided for wallpaper generation")
      return
    }

    if (Settings.data.general.debugMode) {
      Logger.log("AppThemeService", "Generating from wallpaper on screen:", screenName)
    }

    const wp = WallpaperService.getWallpaper(screenName).replace(/'/g, "'\\''")
    if (!wp) {
      Logger.error("AppThemeService", "No wallpaper found")
      return
    }

    const content = MatugenTemplates.buildConfigToml()
    if (!content)
      return

    const mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    const script = buildMatugenScript(content, wp, mode)

    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  function buildMatugenScript(content, wallpaper, mode) {
    const delimiter = "MATUGEN_CONFIG_EOF_" + Math.random().toString(36).substr(2, 9)
    const pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")

    let script = `cat > '${pathEsc}' << '${delimiter}'\n${content}\n${delimiter}\n`
    script += `matugen image '${wallpaper}' --config '${pathEsc}' --mode ${mode} --type ${Settings.data.colorSchemes.matugenSchemeType}`
    script += buildUserTemplateCommand(wallpaper, mode)

    return script + "\n"
  }

  // --------------------------------------------------------------------------------
  // Predefined Scheme Generation
  //  For predefined color schemes, we bypass matugen's generation which do not gives good results.
  //  Instead, we use 'sed' to apply a custom palette to the existing matugen templates.
  // --------------------------------------------------------------------------------
  function generateFromPredefinedScheme(schemeData) {
    if (Settings.data.general.debugMode) {
      Logger.log("AppThemeService", "Generating templates from predefined color scheme")
    }

    // Early return if no scheme data provided
    if (!schemeData) {
      Logger.warn("AppThemeService", "No scheme data provided, skipping template generation")
      return
    }

    handleTerminalThemes()

    const isDarkMode = Settings.data.colorSchemes.darkMode
    const mode = isDarkMode ? "dark" : "light"

    // Check if scheme data has dark/light modes
    if (!schemeData[mode]) {
      Logger.warn("AppThemeService", `No ${mode} mode found in scheme data, skipping template generation`)
      return
    }

    const colors = schemeData[mode]

    const matugenColors = generatePalette(colors.mPrimary, colors.mSecondary, colors.mTertiary, colors.mError, colors.mSurface, isDarkMode)
    const script = processAllTemplates(matugenColors, mode)

    if (Settings.data.general.debugMode) {
      Logger.log("AppThemeService", "Generated script length:", script.length, "chars")
    }

    if (script.trim().length > 0) {
      generateProcess.command = ["bash", "-lc", script]
      generateProcess.running = true
    } else {
      Logger.warn("AppThemeService", "No templates to process (empty script)")
    }
  }

  // Helper function to convert hex to HSL
  function hexToHSL(hex) {
    // Remove # if present
    hex = hex.replace("#", "")

    // Convert hex to RGB
    const r = parseInt(hex.substring(0, 2), 16) / 255
    const g = parseInt(hex.substring(2, 4), 16) / 255
    const b = parseInt(hex.substring(4, 6), 16) / 255

    const max = Math.max(r, g, b)
    const min = Math.min(r, g, b)
    let h, s, l = (max + min) / 2

    if (max === min) {
      h = s = 0 // achromatic
    } else {
      const d = max - min
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min)

      switch (max) {
        case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break
        case g: h = ((b - r) / d + 2) / 6; break
        case b: h = ((r - g) / d + 4) / 6; break
      }
    }

    return {
      h: Math.round(h * 360),
      s: Math.round(s * 100),
      l: Math.round(l * 100)
    }
  }

  function generatePalette(primaryColor, secondaryColor, tertiaryColor, errorColor, backgroundColor, outlineColor, isDarkMode) {
    const c = hex => {
      const hsl = hexToHSL(hex)
      return {
        "default": {
          "hex": hex,
          "hex_stripped": hex.replace("#", ""),
          "hue": String(hsl.h),
          "saturation": String(hsl.s),
          "lightness": String(hsl.l)
        }
      }
    }

    // Generate container colors
    const primaryContainer = ColorsConvert.generateContainerColor(primaryColor, isDarkMode)
    const secondaryContainer = ColorsConvert.generateContainerColor(secondaryColor, isDarkMode)
    const tertiaryContainer = ColorsConvert.generateContainerColor(tertiaryColor, isDarkMode)

    // Generate "on" colors (for text/icons)
    const onPrimary = ColorsConvert.generateOnColor(primaryColor, isDarkMode)
    const onSecondary = ColorsConvert.generateOnColor(secondaryColor, isDarkMode)
    const onTertiary = ColorsConvert.generateOnColor(tertiaryColor, isDarkMode)
    const onBackground = ColorsConvert.generateOnColor(backgroundColor, isDarkMode)

    const onPrimaryContainer = ColorsConvert.generateOnColor(primaryContainer, isDarkMode)
    const onSecondaryContainer = ColorsConvert.generateOnColor(secondaryContainer, isDarkMode)
    const onTertiaryContainer = ColorsConvert.generateOnColor(tertiaryContainer, isDarkMode)

    // Generate error colors (standard red-based)
    const errorContainer = ColorsConvert.generateContainerColor(errorColor, isDarkMode)
    const onError = ColorsConvert.generateOnColor(errorColor, isDarkMode)
    const onErrorContainer = ColorsConvert.generateOnColor(errorContainer, isDarkMode)

    // Surface is same as background in Material Design 3
    const surface = backgroundColor
    const onSurface = onBackground

    // Generate surface variant (slightly different tone)
    const surfaceVariant = ColorsConvert.adjustLightness(backgroundColor, isDarkMode ? 5 : -3)
    const onSurfaceVariant = ColorsConvert.generateOnColor(surfaceVariant, isDarkMode)

    // Generate surface containers (progressive elevation)
    const surfaceContainerLowest = ColorsConvert.generateSurfaceVariant(backgroundColor, 0, isDarkMode)
    const surfaceContainerLow = ColorsConvert.generateSurfaceVariant(backgroundColor, 1, isDarkMode)
    const surfaceContainer = ColorsConvert.generateSurfaceVariant(backgroundColor, 2, isDarkMode)
    const surfaceContainerHigh = ColorsConvert.generateSurfaceVariant(backgroundColor, 3, isDarkMode)
    const surfaceContainerHighest = ColorsConvert.generateSurfaceVariant(backgroundColor, 4, isDarkMode)

    // Generate outline colors (for borders/dividers)
    const outline = isDarkMode ? "#938f99" : "#79747e"
    const outlineVariant = ColorsConvert.adjustLightness(outline, isDarkMode ? -10 : 10)

    // Shadow is always very dark
    const shadow = "#000000"

    return {
      "primary": c(primaryColor),
      "on_primary": c(onPrimary),
      "primary_container": c(primaryContainer),
      "on_primary_container": c(onPrimaryContainer),
      "secondary": c(secondaryColor),
      "on_secondary": c(onSecondary),
      "secondary_container": c(secondaryContainer),
      "on_secondary_container": c(onSecondaryContainer),
      "tertiary": c(tertiaryColor),
      "on_tertiary": c(onTertiary),
      "tertiary_container": c(tertiaryContainer),
      "on_tertiary_container": c(onTertiaryContainer),
      "error": c(errorColor),
      "on_error": c(onError),
      "error_container": c(errorContainer),
      "on_error_container": c(onErrorContainer),
      "background": c(backgroundColor),
      "on_background": c(onBackground),
      "surface": c(surface),
      "on_surface": c(onSurface),
      "surface_variant": c(surfaceVariant),
      "on_surface_variant": c(onSurfaceVariant),
      "surface_container_lowest": c(surfaceContainerLowest),
      "surface_container_low": c(surfaceContainerLow),
      "surface_container": c(surfaceContainer),
      "surface_container_high": c(surfaceContainerHigh),
      "surface_container_highest": c(surfaceContainerHighest),
      "outline": c(outline),
      "outline_variant": c(outlineVariant),
      "shadow": c(shadow)
    }
  }
  function processAllTemplates(colors, mode) {
    let script = ""
    const homeDir = Quickshell.env("HOME")

    // Process built-in templates
    Object.keys(predefinedTemplateConfigs).forEach(appName => {
                                                     if (Settings.data.templates[appName]) {
                                                       script += processTemplate(appName, colors, mode, homeDir)
                                                     }
                                                   })

    // Process user templates from ~/.config/matugen/config.toml
    script += processUserTemplates(colors, mode)

    return script
  }

  function processTemplate(appName, colors, mode, homeDir) {
    const config = predefinedTemplateConfigs[appName]
    const templatePath = `${Quickshell.shellDir}/Assets/MatugenTemplates/${config.input}`
    let script = ""

    config.outputs.forEach(output => {
                             const outputPath = output.path.replace("~", homeDir)
                             const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'))

                             script += `mkdir -p ${outputDir}\n`
                             script += `cp '${templatePath}' '${outputPath}'\n`
                             script += replaceColorsInFile(outputPath, colors)
                           })

    if (config.postProcess) {
      script += config.postProcess(mode)
    }

    return script
  }

  function replaceColorsInFile(filePath, colors) {
    let script = ""
    Object.keys(colors).forEach(colorKey => {
                                  const colorData = colors[colorKey].default
                                  const escapedHex = colorData.hex.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
                                  const escapedHexStripped = colorData.hex_stripped.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
                                  const hue = colorData.hue
                                  const saturation = colorData.saturation
                                  const lightness = colorData.lightness

                                  // Replace hex, hex_stripped, and HSL component patterns
                                  script += `sed -i 's/{{colors\\.${colorKey}\\.default\\.hex}}/${escapedHex}/g' '${filePath}'\n`
                                  script += `sed -i 's/{{colors\\.${colorKey}\\.default\\.hex_stripped}}/${escapedHexStripped}/g' '${filePath}'\n`
                                  script += `sed -i 's/{{colors\\.${colorKey}\\.default\\.hue}}/${hue}/g' '${filePath}'\n`
                                  script += `sed -i 's/{{colors\\.${colorKey}\\.default\\.saturation}}/${saturation}/g' '${filePath}'\n`
                                  script += `sed -i 's/{{colors\\.${colorKey}\\.default\\.lightness}}/${lightness}/g' '${filePath}'\n`
                                })
    return script
  }

  // --------------------------------------------------------------------------------
  // User Templates - Process custom matugen templates from ~/.config/matugen/config.toml
  // --------------------------------------------------------------------------------
  function processUserTemplates(colors, mode) {
    if (!Settings.data.templates.enableUserTemplates) {
      return ""
    }

    if (Settings.data.general.debugMode) {
      Logger.log("AppThemeService", "Processing user templates from", getUserConfigPath())
    }

    const userConfigPath = getUserConfigPath()
    const matugenConfigDir = Quickshell.env("HOME") + "/.config/matugen"
    const homeDir = Quickshell.env("HOME")

    // Generate sed commands for color replacements (hex, hex_stripped, hue, saturation, lightness)
    // Note: We need {{{{ to produce {{ in Python f-string output
    let sedCommands = []
    Object.keys(colors).forEach(colorKey => {
                                  const colorData = colors[colorKey].default
                                  const escapedHex = colorData.hex.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
                                  const escapedHexStripped = colorData.hex_stripped.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
                                  const hue = colorData.hue
                                  const saturation = colorData.saturation
                                  const lightness = colorData.lightness

                                  sedCommands.push(`s/{{{{colors\\\\.${colorKey}\\\\.default\\\\.hex}}}}/${escapedHex}/g`)
                                  sedCommands.push(`s/{{{{colors\\\\.${colorKey}\\\\.default\\\\.hex_stripped}}}}/${escapedHexStripped}/g`)
                                  sedCommands.push(`s/{{{{colors\\\\.${colorKey}\\\\.default\\\\.hue}}}}/${hue}/g`)
                                  sedCommands.push(`s/{{{{colors\\\\.${colorKey}\\\\.default\\\\.saturation}}}}/${saturation}/g`)
                                  sedCommands.push(`s/{{{{colors\\\\.${colorKey}\\\\.default\\\\.lightness}}}}/${lightness}/g`)
                                })
    const sedCommandsStr = sedCommands.join(';')

    // Use Python to parse TOML and generate processing commands
    return `
# Process user templates from ${userConfigPath}
if [ -f '${userConfigPath}' ]; then
  python3 << 'PYTHON_EOF' | bash
import re
import os
import sys

config_path = '${userConfigPath}'
home = '${homeDir}'
config_dir = '${matugenConfigDir}'

try:
    with open(config_path, 'r') as f:
        content = f.read()

    # Simple TOML parsing for [templates.name] blocks
    template_pattern = re.compile(r'\\[templates\\.([^\\]]+)\\]([^\\[]*)', re.MULTILINE)

    for match in template_pattern.finditer(content):
        name = match.group(1)
        block = match.group(2)

        # Extract paths and hook (matches both single and double quotes)
        input_match = re.search(r'''input_path\\s*=\\s*["']([^"']+)["']''', block)
        output_match = re.search(r'''output_path\\s*=\\s*["']([^"']+)["']''', block)
        hook_match = re.search(r'''post_hook\\s*=\\s*["']([^"']+)["']''', block)

        if not input_match or not output_match:
            continue

        input_path = input_match.group(1)
        output_path = output_match.group(1)
        post_hook = hook_match.group(1) if hook_match else None

        # Expand ~ in paths
        input_path = input_path.replace('~', home)
        output_path = output_path.replace('~', home)

        # Resolve relative input paths relative to config dir
        if not input_path.startswith('/'):
            input_path = os.path.join(config_dir, input_path)

        # Check if template exists
        if not os.path.exists(input_path):
            print(f"# Warning: User template '{input_path}' not found, skipping", file=sys.stderr)
            continue

        # Output bash commands
        output_dir = os.path.dirname(output_path)
        print(f"mkdir -p '{output_dir}'")
        print(f"cp '{input_path}' '{output_path}'")
        print(f"sed -i '${sedCommandsStr}' '{output_path}'")

        if post_hook:
            print(post_hook)

except Exception as e:
    print(f"# Warning: Failed to parse user templates: {e}", file=sys.stderr)

PYTHON_EOF
fi
`
  }

  // --------------------------------------------------------------------------------
  // Terminal Themes
  // --------------------------------------------------------------------------------
  function handleTerminalThemes() {
    const commands = []

    Object.keys(terminalPaths).forEach(terminal => {
                                         if (Settings.data.templates[terminal]) {
                                           const outputPath = terminalPaths[terminal]
                                           const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'))
                                           const templatePath = getTerminalColorsTemplate(terminal)

                                           commands.push(`mkdir -p ${outputDir}`)
                                           commands.push(`cp -f ${templatePath} ${outputPath}`)
                                           commands.push(`${colorsApplyScript} ${terminal}`)
                                         }
                                       })

    if (commands.length > 0) {
      copyProcess.command = ["bash", "-lc", commands.join('; ')]
      copyProcess.running = true
    }
  }

  function getTerminalColorsTemplate(terminal) {
    let colorScheme = Settings.data.colorSchemes.predefinedScheme
    const mode = Settings.data.colorSchemes.darkMode ? 'dark' : 'light'

    colorScheme = schemeNameMap[colorScheme] || colorScheme
    const extension = terminal === 'kitty' ? ".conf" : ""

    return `${Quickshell.shellDir}/Assets/ColorScheme/${colorScheme}/terminal/${terminal}/${colorScheme}-${mode}${extension}`
  }

  // --------------------------------------------------------------------------------
  // User Templates
  // --------------------------------------------------------------------------------
  function buildUserTemplateCommand(input, mode) {
    if (!Settings.data.templates.enableUserTemplates) {
      return ""
    }

    const userConfigPath = getUserConfigPath()
    let script = "\n# Execute user config if it exists\n"
    script += `if [ -f '${userConfigPath}' ]; then\n`
    script += `  matugen image '${input}' --config '${userConfigPath}' --mode ${mode} --type ${Settings.data.colorSchemes.matugenSchemeType}\n`
    script += "fi"

    return script
  }

  function getUserConfigPath() {
    return (Quickshell.env("HOME") + "/.config/matugen/config.toml").replace(/'/g, "'\\''")
  }

  // --------------------------------------------------------------------------------
  // Processes
  // --------------------------------------------------------------------------------
  Process {
    id: generateProcess
    workingDirectory: Quickshell.shellDir
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        if (Settings.data.general.debugMode && this.text && this.text.trim().length > 0) {
          Logger.log("AppThemeService", "GenerateProcess stdout:", this.text)
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("AppThemeService", "GenerateProcess stderr:", this.text)
        }
      }
    }

    onExited: function(code) {
      if (code !== 0) {
        Logger.error("AppThemeService", "GenerateProcess exited with code:", code)
      } else if (Settings.data.general.debugMode) {
        Logger.log("AppThemeService", "Template generation completed successfully")
      }
    }
  }

  Process {
    id: copyProcess
    running: false
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("AppThemeService", "CopyProcess stderr:", this.text)
        }
      }
    }
  }
}
