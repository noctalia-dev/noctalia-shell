pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import Quickshell.Io
import qs.Commons
import qs.Services.System
import qs.Services.Theming
import qs.Services.UI

Singleton {
  id: root

  readonly property string dynamicConfigPath: Settings.cacheDir + "matugen.dynamic.toml"

  readonly property var schemeNameMap: ({
                                          "Noctalia (default)": "Noctalia-default",
                                          "Noctalia (legacy)": "Noctalia-legacy",
                                          "Tokyo Night": "Tokyo-Night",
                                          "Rose Pine": "Rosepine"
                                        })

  readonly property var terminalPaths: ({
                                          "foot": "~/.config/foot/themes/noctalia",
                                          "ghostty": "~/.config/ghostty/themes/noctalia",
                                          "kitty": "~/.config/kitty/themes/noctalia.conf",
                                          "alacritty": "~/.config/alacritty/themes/noctalia.toml",
                                          "wezterm": "~/.config/wezterm/colors/Noctalia.toml"
                                        })

  /**
  * Process wallpaper colors using matugen CLI
  * Dual-path architecture (wallpaper uses matugen CLI)
  */
  function processWallpaperColors(wallpaperPath, mode) {
    const content = buildMatugenConfig();
    if (!content)
      return;
    const wp = wallpaperPath.replace(/'/g, "'\\''");
    const script = buildMatugenScript(content, wp, mode);

    generateProcess.generator = "matugen";
    generateProcess.command = ["bash", "-lc", script];
    generateProcess.running = true;
  }

  /**
  * Process predefined color scheme using sed scripts
  * Dual-path architecture (predefined uses sed scripts)
  */
  function processPredefinedScheme(schemeData, mode) {
    handleTerminalThemes(mode);

    const colors = schemeData[mode];
    let script = processAllTemplates(colors, mode, schemeData);

    // Add user templates if enabled (requirement #1)
    script += buildUserTemplateCommandForPredefined(schemeData, mode);

    generateProcess.generator = "predefined";
    generateProcess.command = ["bash", "-lc", script];
    generateProcess.running = true;
  }

  // ================================================================================
  // WALLPAPER-BASED GENERATION (matugen CLI)
  // ================================================================================
  function buildMatugenConfig() {
    var lines = [];
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";

    if (Settings.data.colorSchemes.useWallpaperColors) {
      addWallpaperTemplates(lines, mode);
    }

    addApplicationTemplates(lines, mode);

    if (lines.length > 0) {
      return ["[config]"].concat(lines).join("\n") + "\n";
    }
    return "";
  }

  function addWallpaperTemplates(lines, mode) {
    // Noctalia colors JSON
    lines.push("[templates.noctalia]");
    lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/noctalia.json"');
    lines.push('output_path = "' + Settings.configDir + 'colors.json"');

    // Terminal templates
    TemplateRegistry.terminals.forEach(terminal => {
                                         if (Settings.data.templates[terminal.id]) {
                                           lines.push(`\n[templates.${terminal.id}]`);
                                           lines.push(`input_path = "${Quickshell.shellDir}/Assets/MatugenTemplates/${terminal.matugenPath}"`);
                                           lines.push(`output_path = "${terminal.outputPath}"`);
                                           const postHook = terminal.postHook || `${TemplateRegistry.colorsApplyScript} ${terminal.id}`;
                                           lines.push(`post_hook = "${postHook}"`);
                                         }
                                       });
  }

  function addApplicationTemplates(lines, mode) {
    TemplateRegistry.applications.forEach(app => {
                                            if (app.id === "discord") {
                                              // Handle Discord clients specially
                                              if (Settings.data.templates.discord) {
                                                app.clients.forEach(client => {
                                                                      // Check if this specific client is detected
                                                                      if (isDiscordClientEnabled(client.name)) {
                                                                        lines.push(`\n[templates.discord_${client.name}]`);
                                                                        lines.push(`input_path = "${Quickshell.shellDir}/Assets/MatugenTemplates/${app.input}"`);
                                                                        lines.push(`output_path = "${client.path}/themes/noctalia.theme.css"`);
                                                                      }
                                                                    });
                                              }
                                            } else if (app.id === "code") {
                                              // Handle Code clients specially
                                              if (Settings.data.templates.code) {
                                                const homeDir = Quickshell.env("HOME");
                                                app.clients.forEach(client => {
                                                                      // Check if this specific client is detected
                                                                      if (isCodeClientEnabled(client.name)) {
                                                                        lines.push(`\n[templates.code_${client.name}]`);
                                                                        lines.push(`input_path = "${Quickshell.shellDir}/Assets/MatugenTemplates/${app.input}"`);
                                                                        const expandedPath = client.path.replace("~", homeDir);
                                                                        lines.push(`output_path = "${expandedPath}"`);
                                                                      }
                                                                    });
                                              }
                                            } else if (app.id === "emacs" && app.checkDoomFirst) {
                                              if (Settings.data.templates.emacs) {
                                                const homeDir = Quickshell.env("HOME");
                                                const doomPathTemplate = app.outputs[0].path; // ~/.config/doom/themes/noctalia-theme.el
                                                const standardPathTemplate = app.outputs[1].path; // ~/.emacs.d/themes/noctalia-theme.el
                                                const doomPath = doomPathTemplate.replace("~", homeDir);
                                                const standardPath = standardPathTemplate.replace("~", homeDir);
                                                const doomConfigDir = `${homeDir}/.config/doom`;
                                                const doomDir = doomPath.substring(0, doomPath.lastIndexOf('/'));

                                                lines.push(`\n[templates.emacs]`);
                                                lines.push(`input_path = "${Quickshell.shellDir}/Assets/MatugenTemplates/${app.input}"`);
                                                lines.push(`output_path = "${standardPathTemplate}"`);
                                                // Move to doom if doom exists, then remove empty .emacs.d/themes and .emacs.d directories
                                                // Check directories are empty before removing
                                                lines.push(`post_hook = "sh -c 'if [ -d \\"${doomConfigDir}\\" ] && [ -f \\"${standardPath}\\" ]; then mkdir -p \\"${doomDir}\\" && mv \\"${standardPath}\\" \\"${doomPath}\\" && rmdir \\"${homeDir}/.emacs.d/themes\\" 2>/dev/null && rmdir \\"${homeDir}/.emacs.d\\" 2>/dev/null || true; fi'"`);
                                              }
                                            } else {
                                              // Handle regular apps
                                              if (Settings.data.templates[app.id]) {
                                                app.outputs.forEach((output, idx) => {
                                                                      lines.push(`\n[templates.${app.id}_${idx}]`);
                                                                      lines.push(`input_path = "${Quickshell.shellDir}/Assets/MatugenTemplates/${app.input}"`);
                                                                      lines.push(`output_path = "${output.path}"`);
                                                                      if (app.postProcess) {
                                                                        lines.push(`post_hook = "${app.postProcess(mode)}"`);
                                                                      }
                                                                    });
                                              }
                                            }
                                          });
  }

  function isDiscordClientEnabled(clientName) {
    // Check ProgramCheckerService to see if client is detected
    for (var i = 0; i < ProgramCheckerService.availableDiscordClients.length; i++) {
      if (ProgramCheckerService.availableDiscordClients[i].name === clientName) {
        return true;
      }
    }
    return false;
  }

  function isCodeClientEnabled(clientName) {
    // Check ProgramCheckerService to see if client is detected
    for (var i = 0; i < ProgramCheckerService.availableCodeClients.length; i++) {
      if (ProgramCheckerService.availableCodeClients[i].name === clientName) {
        return true;
      }
    }
    return false;
  }

  function buildMatugenScript(content, wallpaper, mode) {
    const delimiter = "MATUGEN_CONFIG_EOF_" + Math.random().toString(36).substr(2, 9);
    const pathEsc = dynamicConfigPath.replace(/'/g, "'\\''");
    const wpDelimiter = "WALLPAPER_PATH_EOF_" + Math.random().toString(36).substr(2, 9);

    // Use heredoc for wallpaper path to avoid all escaping issues
    let script = `cat > '${pathEsc}' << '${delimiter}'\n${content}\n${delimiter}\n`;
    script += `NOCTALIA_WP_PATH=$(cat << '${wpDelimiter}'\n${wallpaper}\n${wpDelimiter}\n)\n`;
    script += `matugen image "$NOCTALIA_WP_PATH" --config '${pathEsc}' --mode ${mode} --type ${Settings.data.colorSchemes.matugenSchemeType}`;
    script += buildUserTemplateCommand("$NOCTALIA_WP_PATH", mode);

    return script + "\n";
  }

  // ================================================================================
  // PREDEFINED SCHEME GENERATION (sed scripts)
  // ================================================================================
  function processAllTemplates(colors, mode, schemeData) {
    let script = "";
    const homeDir = Quickshell.env("HOME");

    TemplateRegistry.applications.forEach(app => {
                                            if (app.id === "discord") {
                                              if (Settings.data.templates.discord) {
                                                script += processDiscordClients(app, colors, mode, homeDir);
                                              }
                                            } else if (app.id === "code") {
                                              if (Settings.data.templates.code) {
                                                script += processCodeClients(app, colors, mode, homeDir);
                                              }
                                            } else {
                                              if (Settings.data.templates[app.id]) {
                                                script += processTemplate(app, colors, mode, homeDir, schemeData);
                                              }
                                            }
                                          });
    return script;
  }

  function processDiscordClients(discordApp, colors, mode, homeDir) {
    let script = "";
    const palette = ColorPaletteGenerator.generatePalette(colors, Settings.data.colorSchemes.darkMode, false);

    discordApp.clients.forEach(client => {
                                 if (!isDiscordClientEnabled(client.name))
                                 return;
                                 const templatePath = `${Quickshell.shellDir}/Assets/MatugenTemplates/${discordApp.input}`;
                                 const outputPath = `${client.path}/themes/noctalia.theme.css`.replace("~", homeDir);
                                 const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'));
                                 const baseConfigDir = outputDir.replace("/themes", "");

                                 script += `\n`;
                                 script += `if [ -d "${baseConfigDir}" ]; then\n`;
                                 script += `  mkdir -p ${outputDir}\n`;
                                 script += `  cp '${templatePath}' '${outputPath}'\n`;
                                 script += `  ${replaceColorsInFile(outputPath, palette)}`;
                                 script += `else\n`;
                                 script += `  echo "Discord client ${client.name} not found at ${baseConfigDir}, skipping"\n`;
                                 script += `fi\n`;
                               });

    return script;
  }

  function processCodeClients(codeApp, colors, mode, homeDir) {
    let script = "";
    const palette = ColorPaletteGenerator.generatePalette(colors, Settings.data.colorSchemes.darkMode, false);

    codeApp.clients.forEach(client => {
                              if (!isCodeClientEnabled(client.name))
                              return;
                              const templatePath = `${Quickshell.shellDir}/Assets/MatugenTemplates/${codeApp.input}`;
                              const outputPath = client.path.replace("~", homeDir);
                              const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'));

                              // Extract base config directory for checking
                              var baseConfigDir = "";
                              if (client.name === "code") {
                                baseConfigDir = "~/.vscode".replace("~", homeDir);
                              } else if (client.name === "codium") {
                                baseConfigDir = "~/.vscode-oss".replace("~", homeDir);
                              }

                              script += `\n`;
                              script += `if [ -d "${baseConfigDir}" ]; then\n`;
                              script += `  mkdir -p ${outputDir}\n`;
                              script += `  cp '${templatePath}' '${outputPath}'\n`;
                              script += `  ${replaceColorsInFile(outputPath, palette)}`;
                              script += `else\n`;
                              script += `  echo "Code client ${client.name} not found at ${baseConfigDir}, skipping"\n`;
                              script += `fi\n`;
                            });

    return script;
  }

  function processTemplate(app, colors, mode, homeDir, schemeData) {
    const palette = ColorPaletteGenerator.generatePalette(colors, Settings.data.colorSchemes.darkMode, app.strict || false);

    // For templates with both dark and light patterns (like zed.json), generate both palettes
    const hasDualModePatterns = app.dualMode || false;
    let darkPalette, lightPalette;
    if (hasDualModePatterns && schemeData) {
      darkPalette = ColorPaletteGenerator.generatePalette(schemeData.dark, true, app.strict || false);
      lightPalette = ColorPaletteGenerator.generatePalette(schemeData.light, false, app.strict || false);
    }

    let script = "";

    if (app.id === "emacs" && app.checkDoomFirst) {
      const doomPath = app.outputs[0].path.replace("~", homeDir);
      const doomDir = doomPath.substring(0, doomPath.lastIndexOf('/'));
      const doomConfigDir = doomDir.substring(0, doomDir.lastIndexOf('/')); // ~/.config/doom
      const standardPath = app.outputs[1].path.replace("~", homeDir);
      const standardDir = standardPath.substring(0, standardPath.lastIndexOf('/'));
      const templatePath = `${Quickshell.shellDir}/Assets/MatugenTemplates/${app.input}`;

      script += `\n`;
      script += `if [ -d "${doomConfigDir}" ]; then\n`;
      script += `  mkdir -p ${doomDir}\n`;
      script += `  cp '${templatePath}' '${doomPath}'\n`;
      script += replaceColorsInFile(doomPath, palette);
      script += `else\n`;
      script += `  mkdir -p ${standardDir}\n`;
      script += `  cp '${templatePath}' '${standardPath}'\n`;
      script += replaceColorsInFile(standardPath, palette);
      script += `fi\n`;
    } else {
      app.outputs.forEach(output => {
                            const templatePath = `${Quickshell.shellDir}/Assets/MatugenTemplates/${app.input}`;
                            const outputPath = output.path.replace("~", homeDir);
                            const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'));

                            script += `\n`;
                            script += `mkdir -p ${outputDir}\n`;
                            script += `cp '${templatePath}' '${outputPath}'\n`;
                            script += replaceColorsInFile(outputPath, palette);
                            if (hasDualModePatterns && darkPalette && lightPalette) {
                              script += replaceColorsInFileWithMode(outputPath, darkPalette, lightPalette);
                            }
                            script += `\n`;
                          });
    }

    if (app.postProcess) {
      script += app.postProcess(mode);
    }

    return script;
  }

  function replaceColorsInFile(filePath, colors) {
    let expressions = [];

    Object.keys(colors).forEach(colorKey => {
                                  const hexValue = colors[colorKey].default.hex;
                                  const hexStrippedValue = colors[colorKey].default.hex_stripped;

                                  const escapedHex = hexValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                                  const escapedHexStripped = hexStrippedValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

                                  // Batch all replacements into a single sed command to avoid ARG_MAX limits
                                  expressions.push(`-e 's/{{colors\\.${colorKey}\\.default\\.hex_stripped}}/${escapedHexStripped}/g'`);
                                  expressions.push(`-e 's/{{colors\\.${colorKey}\\.default\\.hex}}/${escapedHex}/g'`);
                                });
    return `sed -i ${expressions.join(' ')} '${filePath}'\n`;
  }

  function replaceColorsInFileWithMode(filePath, darkColors, lightColors) {
    let expressions = [];

    // Replace dark mode patterns
    Object.keys(darkColors).forEach(colorKey => {
                                      const hexValue = darkColors[colorKey].default.hex;
                                      const hexStrippedValue = darkColors[colorKey].default.hex_stripped;
                                      const escapedHex = hexValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                                      const escapedHexStripped = hexStrippedValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

                                      expressions.push(`-e 's/{{colors\\.${colorKey}\\.dark\\.hex_stripped}}/${escapedHexStripped}/g'`);
                                      expressions.push(`-e 's/{{colors\\.${colorKey}\\.dark\\.hex}}/${escapedHex}/g'`);
                                    });

    // Replace light mode patterns
    Object.keys(lightColors).forEach(colorKey => {
                                       const hexValue = lightColors[colorKey].default.hex;
                                       const hexStrippedValue = lightColors[colorKey].default.hex_stripped;
                                       const escapedHex = hexValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                                       const escapedHexStripped = hexStrippedValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

                                       expressions.push(`-e 's/{{colors\\.${colorKey}\\.light\\.hex_stripped}}/${escapedHexStripped}/g'`);
                                       expressions.push(`-e 's/{{colors\\.${colorKey}\\.light\\.hex}}/${escapedHex}/g'`);
                                     });

    // Batch all replacements into a single sed command to avoid ARG_MAX limits
    return `sed -i ${expressions.join(' ')} '${filePath}'\n`;
  }

  // ================================================================================
  // TERMINAL THEMES (predefined schemes use pre-rendered files)
  // ================================================================================
  function escapeShellPath(path) {
    // Escape single quotes by ending the quoted string, adding an escaped quote, and starting a new quoted string
    return "'" + path.replace(/'/g, "'\\''") + "'";
  }

  function handleTerminalThemes(mode) {
    const commands = [];
    const homeDir = Quickshell.env("HOME");

    Object.keys(terminalPaths).forEach(terminal => {
                                         if (Settings.data.templates[terminal]) {
                                           const outputPath = terminalPaths[terminal].replace("~", homeDir);
                                           const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'));
                                           const templatePaths = getTerminalColorsTemplate(terminal, mode);

                                           commands.push(`mkdir -p ${escapeShellPath(outputDir)}`);
                                           // Try hyphen first (most common), then space (for schemes like "Rosey AMOLED")
                                           const hyphenPath = escapeShellPath(templatePaths.hyphen);
                                           const spacePath = escapeShellPath(templatePaths.space);
                                           commands.push(`if [ -f ${hyphenPath} ]; then cp -f ${hyphenPath} ${escapeShellPath(outputPath)}; elif [ -f ${spacePath} ]; then cp -f ${spacePath} ${escapeShellPath(outputPath)}; else echo "ERROR: Template file not found for ${terminal} (tried both hyphen and space patterns)"; fi`);
                                           commands.push(`${TemplateRegistry.colorsApplyScript} ${terminal}`);
                                         }
                                       });

    if (commands.length > 0) {
      copyProcess.command = ["bash", "-lc", commands.join('; ')];
      copyProcess.running = true;
    }
  }

  function getTerminalColorsTemplate(terminal, mode) {
    let colorScheme = Settings.data.colorSchemes.predefinedScheme;
    colorScheme = schemeNameMap[colorScheme] || colorScheme;

    let extension = "";
    if (terminal === 'kitty') {
      extension = ".conf";
    } else if (terminal === 'wezterm') {
      extension = ".toml";
    }

    // Support both naming conventions: "SchemeName-dark" (hyphen) and "SchemeName dark" (space)
    const fileNameHyphen = `${colorScheme}-${mode}${extension}`;
    const fileNameSpace = `${colorScheme} ${mode}${extension}`;
    const relativePathHyphen = `terminal/${terminal}/${fileNameHyphen}`;
    const relativePathSpace = `terminal/${terminal}/${fileNameSpace}`;

    // Try to find the scheme in the loaded schemes list to determine which directory it's in
    for (let i = 0; i < ColorSchemeService.schemes.length; i++) {
      const schemeJsonPath = ColorSchemeService.schemes[i];
      // Check if this is the scheme we're looking for
      if (schemeJsonPath.indexOf(`/${colorScheme}/`) !== -1 || schemeJsonPath.indexOf(`/${colorScheme}.json`) !== -1) {
        // Extract the scheme directory from the JSON path
        // JSON path is like: /path/to/scheme/SchemeName/SchemeName.json
        // We need: /path/to/scheme/SchemeName/terminal/...
        const schemeDir = schemeJsonPath.substring(0, schemeJsonPath.lastIndexOf('/'));
        return {
          hyphen: `${schemeDir}/${relativePathHyphen}`,
          space: `${schemeDir}/${relativePathSpace}`
        };
      }
    }

    // Fallback: try downloaded first, then preinstalled
    const downloadedPathHyphen = `${ColorSchemeService.downloadedSchemesDirectory}/${colorScheme}/${relativePathHyphen}`;
    const downloadedPathSpace = `${ColorSchemeService.downloadedSchemesDirectory}/${colorScheme}/${relativePathSpace}`;
    const preinstalledPathHyphen = `${ColorSchemeService.schemesDirectory}/${colorScheme}/${relativePathHyphen}`;
    const preinstalledPathSpace = `${ColorSchemeService.schemesDirectory}/${colorScheme}/${relativePathSpace}`;

    return {
      hyphen: preinstalledPathHyphen,
      space: preinstalledPathSpace
    };
  }

  // ================================================================================
  // USER TEMPLATES, advanced usage
  // ================================================================================
  function buildUserTemplateCommand(input, mode) {
    if (!Settings.data.templates.enableUserTemplates)
      return "";

    const userConfigPath = getUserConfigPath();
    let script = "\n# Execute user config if it exists\n";
    script += `if [ -f '${userConfigPath}' ]; then\n`;
    // If input is a shell variable (starts with $), use double quotes to allow expansion
    // Otherwise, use single quotes for safety with file paths
    const inputQuoted = input.startsWith("$") ? `"${input}"` : `'${input.replace(/'/g, "'\\''")}'`;
    script += `  matugen image ${inputQuoted} --config '${userConfigPath}' --mode ${mode} --type ${Settings.data.colorSchemes.matugenSchemeType}\n`;
    script += "fi";

    return script;
  }

  function buildUserTemplateCommandForPredefined(schemeData, mode) {
    if (!Settings.data.templates.enableUserTemplates)
      return "";

    const userConfigPath = getUserConfigPath();
    const colors = schemeData[mode];
    const palette = ColorPaletteGenerator.generatePalette(colors, Settings.data.colorSchemes.darkMode, false);

    const tempJsonPath = Settings.cacheDir + "predefined-colors.json";
    const tempJsonPathEsc = tempJsonPath.replace(/'/g, "'\\''");

    let script = "\n# Execute user templates with predefined scheme colors\n";
    script += `if [ -f '${userConfigPath}' ]; then\n`;
    script += `  cat > '${tempJsonPathEsc}' << 'EOF'\n`;
    script += JSON.stringify({
                               "colors": palette
                             }, null, 2) + "\n";
    script += "EOF\n";
    script += `  matugen json '${tempJsonPathEsc}' --config '${userConfigPath}' --mode ${mode} --type ${Settings.data.colorSchemes.matugenSchemeType}\n`;
    script += "fi";

    return script;
  }

  function getUserConfigPath() {
    return (Settings.configDir + "user-templates.toml").replace(/'/g, "'\\''");
  }

  // ================================================================================
  // PROCESSES
  // ================================================================================
  Process {
    id: generateProcess
    workingDirectory: Quickshell.shellDir
    running: false

    // Error reporting helpers
    property string generator: ""

    function buildErrorMessage() {
      const description = (stderr.text && stderr.text.trim() !== "") ? stderr.text.trim() : ((stdout.text && stdout.text.trim() !== "") ? stdout.text.trim() : I18n.tr("toast.theming-processor-failed.desc-generic"));
      const title = I18n.tr(`toast.theming-processor-failed.title-${generator}`);
      return description;
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        const description = generateProcess.buildErrorMessage();
        Logger.e("TemplateProcessor", "Process failed with exit code", exitCode, description);
      }
    }

    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text)
        Logger.d("TemplateProcessor", "stdout:", this.text);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {}
    }
  }

  // ------------
  Process {
    id: copyProcess
    workingDirectory: Quickshell.shellDir
    running: false
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.e("TemplateProcessor", "copyProcess stderr:", this.text);
        }
      }
    }
  }
}
