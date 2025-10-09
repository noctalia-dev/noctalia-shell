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
      if (screenName === Screen.name && Settings.data.colorSchemes.useWallpaperColors) {
        generateFromWallpaper()
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
      generateFromWallpaper()
    } else {
      generateFromPredefinedScheme()
    }
  }

  // --------------------------------------------------------------------------------
  // Wallpaper Colors Generation
  // --------------------------------------------------------------------------------
  function generateFromWallpaper() {
    Logger.log("AppThemeService", "Generating from wallpaper on screen:", Screen.name)

    const wp = WallpaperService.getWallpaper(Screen.name).replace(/'/g, "'\\''")
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
    Logger.log("AppThemeService", "Generating templates from predefined color scheme")

    handleTerminalThemes()

    const isDarkMode = Settings.data.colorSchemes.darkMode
    const mode = isDarkMode ? "dark" : "light"
    const colors = schemeData[mode]

    const matugenColors = generatePalette(colors.mPrimary, colors.mSecondary, colors.mTertiary, colors.mError, colors.mSurface, isDarkMode)
    const script = processAllTemplates(matugenColors, mode)

    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  function generatePalette(primaryColor, secondaryColor, tertiaryColor, errorColor, backgroundColor, outlineColor, isDarkMode) {
    const c = hex => ({
                        "default": {
                          "hex": hex
                        }
                      })

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

    Object.keys(predefinedTemplateConfigs).forEach(appName => {
                                                     if (Settings.data.templates[appName]) {
                                                       script += processTemplate(appName, colors, mode, homeDir)
                                                     }
                                                   })

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
                                  const colorValue = colors[colorKey].default.hex
                                  const escapedColor = colorValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
                                  script += `sed -i 's/{{colors\\.${colorKey}\\.default\\.hex}}/${escapedColor}/g' '${filePath}'\n`
                                })
    return script
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
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("AppThemeService", "GenerateProcess stderr:", this.text)
        }
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
