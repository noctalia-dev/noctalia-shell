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
                                                      "kcolorscheme": {
                                                        "input": "kcolorscheme.colors",
                                                        "outputs": [{
                                                            "path": "~/.local/share/color-schemes/noctalia.colors"
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
                                                      "discord_vesktop": {
                                                        "input": "vesktop.css",
                                                        "outputs": [{
                                                            "path": "~/.config/vesktop/themes/noctalia.theme.css"
                                                          }]
                                                      },
                                                      "discord_webcord": {
                                                        "input": "vesktop.css",
                                                        "outputs": [{
                                                            "path": "~/.config/webcord/themes/noctalia.theme.css"
                                                          }]
                                                      },
                                                      "discord_armcord": {
                                                        "input": "vesktop.css",
                                                        "outputs": [{
                                                            "path": "~/.config/armcord/themes/noctalia.theme.css"
                                                          }]
                                                      },
                                                      "discord_equibop": {
                                                        "input": "vesktop.css",
                                                        "outputs": [{
                                                            "path": "~/.config/equibop/themes/noctalia.theme.css"
                                                          }]
                                                      },
                                                      "discord_lightcord": {
                                                        "input": "vesktop.css",
                                                        "outputs": [{
                                                            "path": "~/.config/lightcord/themes/noctalia.theme.css"
                                                          }]
                                                      },
                                                      "discord_dorion": {
                                                        "input": "vesktop.css",
                                                        "outputs": [{
                                                            "path": "~/.config/dorion/themes/noctalia.theme.css"
                                                          }]
                                                      },
                                                      "discord_vencord": {
                                                        "input": "vesktop.css",
                                                        "outputs": [{
                                                            "path": "~/.config/discord/themes/noctalia.theme.css"
                                                          }]
                                                      },
                                                      "vicinae": {
                                                        "input": "vicinae.toml",
                                                        "outputs": [{
                                                            "path": "~/.local/share/vicinae/themes/matugen.toml"
                                                          }],
                                                        "postProcess": () => `cp -n ${Quickshell.shellDir}/Assets/noctalia.svg ~/.local/share/vicinae/themes/noctalia.svg && ${colorsApplyScript} vicinae\n`
                                                      },
                                                      "walker": {
                                                        "input": "walker.css",
                                                        "outputs": [{
                                                            "path": "~/.config/walker/themes/noctalia/style.css"
                                                          }],
                                                        "postProcess": () => `${colorsApplyScript} walker\n`,
                                                        "strict": true
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
      Logger.i("AppThemeService", "Detected dark mode change")
      AppThemeService.generate()
    }
  }

  // --------------------------------------------------------------------------------
  function init() {
    Logger.i("AppThemeService", "Service started")
  }

  // --------------------------------------------------------------------------------
  function generate() {
    if (Settings.data.colorSchemes.useWallpaperColors) {
      generateFromWallpaper()
    } else {
      // Re-apply the scheme, this is the best way to regenerate all templates too.
      ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme)
    }
  }

  // --------------------------------------------------------------------------------
  // Wallpaper Colors Generation
  // --------------------------------------------------------------------------------
  function generateFromWallpaper() {

    // Logger.i("AppThemeService", "Generating from wallpaper on screen:", Screen.name)
    const wp = WallpaperService.getWallpaper(Screen.name).replace(/'/g, "'\\''")
    if (!wp) {
      Logger.e("AppThemeService", "No wallpaper found")
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
    Logger.i("AppThemeService", "Generating templates from predefined color scheme")

    handleTerminalThemes()

    const mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    const colors = schemeData[mode]
    let script = processAllTemplates(colors, mode)

    // Add user templates if enabled
    script += buildUserTemplateCommandForPredefined(schemeData, mode)

    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  function generatePalette(colors, isDarkMode, isStrict) {
    const c = hex => ({
                        "default": {
                          "hex": hex,
                          "hex_stripped": hex.replace(/^#/, "")
                        }
                      })

    // Generate container colors
    const primaryContainer = ColorsConvert.generateContainerColor(colors.mPrimary, isDarkMode)
    const secondaryContainer = ColorsConvert.generateContainerColor(colors.mSecondary, isDarkMode)
    const tertiaryContainer = ColorsConvert.generateContainerColor(colors.mTertiary, isDarkMode)

    // Generate "on" colors
    const onPrimary = ColorsConvert.generateOnColor(colors.mPrimary, isDarkMode)
    const onSecondary = ColorsConvert.generateOnColor(colors.mSecondary, isDarkMode)
    const onTertiary = ColorsConvert.generateOnColor(colors.mTertiary, isDarkMode)

    const onPrimaryContainer = ColorsConvert.generateOnColor(primaryContainer, isDarkMode)
    const onSecondaryContainer = ColorsConvert.generateOnColor(secondaryContainer, isDarkMode)
    const onTertiaryContainer = ColorsConvert.generateOnColor(tertiaryContainer, isDarkMode)

    // Generate error colors (standard red-based)
    const errorContainer = ColorsConvert.generateContainerColor(colors.mError, isDarkMode)
    const onError = ColorsConvert.generateOnColor(colors.mError, isDarkMode)
    const onErrorContainer = ColorsConvert.generateOnColor(errorContainer, isDarkMode)

    // Surface is same as background in Material Design 3
    const surface = colors.mSurface
    const onSurface = isStrict ? colors.mOnSurface : ColorsConvert.generateOnColor(colors.mSurface, isDarkMode)

    // Generate surface variant (slightly different tone)
    const surfaceVariant = isStrict ? colors.mSurfaceVariant : ColorsConvert.adjustLightness(colors.mSurface, isDarkMode ? 5 : -3)
    const onSurfaceVariant = isStrict ? colors.mOnSurfaceVariant : ColorsConvert.generateOnColor(surfaceVariant, isDarkMode)

    // Generate surface containers (progressive elevation)
    const surfaceContainerLowest = ColorsConvert.generateSurfaceVariant(surface, 0, isDarkMode)
    const surfaceContainerLow = ColorsConvert.generateSurfaceVariant(surface, 1, isDarkMode)
    const surfaceContainer = ColorsConvert.generateSurfaceVariant(surface, 2, isDarkMode)
    const surfaceContainerHigh = ColorsConvert.generateSurfaceVariant(surface, 3, isDarkMode)
    const surfaceContainerHighest = ColorsConvert.generateSurfaceVariant(surface, 4, isDarkMode)

    // Generate outline colors (for borders/dividers)
    const outline = isStrict ? colors.mOutline : (isDarkMode ? "#938f99" : "#79747e")
    const outlineVariant = ColorsConvert.adjustLightness(outline, isDarkMode ? -10 : 10)

    // Shadow is always very dark
    const shadow = "#000000"

    return {
      "primary": c(colors.mPrimary),
      "on_primary": c(onPrimary),
      "primary_container": c(primaryContainer),
      "on_primary_container": c(onPrimaryContainer),
      "secondary": c(colors.mSecondary),
      "on_secondary": c(onSecondary),
      "secondary_container": c(secondaryContainer),
      "on_secondary_container": c(onSecondaryContainer),
      "tertiary": c(colors.mTertiary),
      "on_tertiary": c(onTertiary),
      "tertiary_container": c(tertiaryContainer),
      "on_tertiary_container": c(onTertiaryContainer),
      "error": c(colors.mError),
      "on_error": c(onError),
      "error_container": c(errorContainer),
      "on_error_container": c(onErrorContainer),
      "background": c(surface),
      "on_background": c(onSurface),
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

    const palette = generatePalette(colors, Settings.data.colorSchemes.darkMode, config.strict || false)

    config.outputs.forEach(output => {

                             const outputPath = output.path.replace("~", homeDir)
                             const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'))

                             // For Discord clients, check if the base config directory exists
                             if (appName.startsWith("discord_")) {
                               const baseConfigDir = outputDir.replace("/themes", "")
                               script += `if [ -d "${baseConfigDir}" ]; then\n`
                               script += `  mkdir -p ${outputDir}\n`
                               script += `  cp '${templatePath}' '${outputPath}'\n`
                               script += `  ${replaceColorsInFile(outputPath, palette)}\n`
                               script += `else\n`
                               script += `  echo "Discord client ${appName} not found at ${baseConfigDir}, skipping theme generation"\n`
                               script += `fi\n`
                             } else {
                               script += `mkdir -p ${outputDir}\n`
                               script += `cp '${templatePath}' '${outputPath}'\n`
                               script += replaceColorsInFile(outputPath, palette)
                             }
                           })

    if (config.postProcess) {
      script += config.postProcess(mode)
    }

    return script
  }

  function replaceColorsInFile(filePath, colors) {
    // This handle both ".hex" and ".hex_stripped" the EXACT same way. Our predefined color schemes are
    // always RRGGBB without alpha so this is fine and keeps compatibility with matugen.
    let script = ""
    Object.keys(colors).forEach(colorKey => {
                                  const colorValue = colors[colorKey].default.hex
                                  const escapedColor = colorValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
                                  script += `sed -i 's/{{colors\\.${colorKey}\\.default\\.hex\\(_stripped\\)\\?}}/${escapedColor}/g' '${filePath}'\n`
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

  function buildUserTemplateCommandForPredefined(schemeData, mode) {
    if (!Settings.data.templates.enableUserTemplates) {
      return ""
    }

    const userConfigPath = getUserConfigPath()
    const isDarkMode = Settings.data.colorSchemes.darkMode
    const colors = schemeData[mode]

    // Generate the matugen palette JSON
    const palette = generatePalette(colors, isDarkMode, false)

    // Create a temporary JSON file with the color palette
    const tempJsonPath = Settings.cacheDir + "predefined-colors.json"
    const homeDir = Quickshell.env("HOME")
    const tempJsonPathEsc = tempJsonPath.replace(/'/g, "'\\''")

    let script = "\n# Execute user templates with predefined scheme colors\n"
    script += `if [ -f '${userConfigPath}' ]; then\n`

    // Write the color palette to a temp JSON file
    script += `  cat > '${tempJsonPathEsc}' << 'EOF'\n`
    script += JSON.stringify({
                               "colors": palette
                             }, null, 2) + "\n"
    script += "EOF\n"

    // Use matugen json subcommand with the color palette
    script += `  matugen json '${tempJsonPathEsc}' --config '${userConfigPath}' --mode ${mode}\n`
    script += "fi"

    return script
  }

  function getUserConfigPath() {
    return (Settings.configDir + "user-templates.toml").replace(/'/g, "'\\''")
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
        if (this.text) {
          Logger.d("AppThemeService", "GenerateProcess stdout:", this.text)
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.d("AppThemeService", "GenerateProcess stderr:", this.text)
        }
      }
    }
  }

  Process {
    id: copyProcess
    workingDirectory: Quickshell.shellDir
    running: false
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.d("AppThemeService", "CopyProcess stderr:", this.text)
        }
      }
    }
  }
}
