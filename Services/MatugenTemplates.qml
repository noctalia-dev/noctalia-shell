pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Central place to define which templates we generate and where they write.
// Users can extend it by dropping additional templates into:
//  - Assets/MatugenTemplates/ (built-in templates)
//  - ~/.config/matugen/ (user-defined templates when enableUserTemplates is true)
// User templates are automatically executed after the main matugen command
// if enableUserTemplates is enabled in settings.
Singleton {
  id: root

  // Build the base TOML using current settings
  function buildConfigToml() {
    var lines = []
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"

    if (Settings.data.colorSchemes.useWallpaperColors) {
      addWallpaperBasedTemplates(lines, mode)
    }

    addApplicationTemplates(lines, mode)

    if (lines.length > 0) {
      const config = ["[config]"].concat(lines)
      return config.join("\n") + "\n"
    }

    return ""
  }

  // Build user templates TOML for ~/.config/noctalia/user-templates.toml
  function buildUserTemplatesToml() {
    var lines = []
    lines.push("[config]")
    lines.push("")
    lines.push("# User-defined templates")
    lines.push("# Add your custom templates below")
    lines.push("# Example:")
    lines.push("# [templates.myapp]")
    lines.push("# input_path = \"~/.config/noctalia/templates/myapp.css\"")
    lines.push("# output_path = \"~/.config/myapp/theme.css\"")
    lines.push("# post_hook = \"myapp --reload-theme\"")
    lines.push("")
    lines.push("# Remove this section and add your own templates")
    lines.push("#[templates.placeholder]")
    lines.push("#input_path = \"" + Quickshell.shellDir + "/Assets/MatugenTemplates/noctalia.json\"")
    lines.push("#output_path = \"" + Settings.cacheDir + "placeholder.json\"")
    lines.push("")

    return lines.join("\n") + "\n"
  }

  // Write user templates TOML to ~/.config/noctalia/user-templates.toml
  function writeUserTemplatesToml() {
    var userConfigPath = Settings.configDir + "user-templates.toml"

    // Check if file already exists
    fileCheckProcess.command = ["test", "-f", userConfigPath]
    fileCheckProcess.running = true
  }

  function doWriteUserTemplatesToml() {
    var userConfigPath = Settings.configDir + "user-templates.toml"
    var configContent = buildUserTemplatesToml()

    // Ensure directory exists (should already exist but just in case)
    Quickshell.execDetached(["mkdir", "-p", Settings.configDir])

    // Write the config file
    Quickshell.execDetached(["sh", "-c", `echo '${configContent.replace(/'/g, "'\\''")}' > '${userConfigPath}'`])

    Logger.d("MatugenTemplates", "User templates config written to:", userConfigPath)
  }

  // --------------------------------
  function addWallpaperBasedTemplates(lines, mode) {
    // Noctalia colors
    lines.push("[templates.noctalia]")
    lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/noctalia.json"')
    lines.push('output_path = "' + Settings.configDir + 'colors.json"')

    // Terminal templates (only for wallpaper-based colors)
    addTerminalTemplates(lines)
  }

  // --------------------------------
  function addTerminalTemplates(lines) {
    var terminals = [{
                       "name": "foot",
                       "path": "Terminal/foot",
                       "output": "~/.config/foot/themes/noctalia"
                     }, {
                       "name": "ghostty",
                       "path": "Terminal/ghostty",
                       "output": "~/.config/ghostty/themes/noctalia",
                       "post_hook": "pkill -SIGUSR2 ghostty"
                     }, {
                       "name": "kitty",
                       "path": "Terminal/kitty.conf",
                       "output": "~/.config/kitty/themes/noctalia.conf"
                     }]

    terminals.forEach(function (terminal) {
      if (Settings.data.templates[terminal.name]) {
        lines.push("\n[templates." + terminal.name + "]")
        lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/' + terminal.path + '"')
        lines.push('output_path = "' + terminal.output + '"')
        lines.push('post_hook = "' + AppThemeService.colorsApplyScript + " " + terminal.name + '"')
      }
    })
  }

  // Applications configuration
  readonly property var applications: [{
      "name": "gtk",
      "templates": [{
          "version": "gtk3",
          "output": "~/.config/gtk-3.0/gtk.css"
        }, {
          "version": "gtk4",
          "output": "~/.config/gtk-4.0/gtk.css"
        }],
      "input": "gtk.css",
      "postHook": "gsettings set org.gnome.desktop.interface color-scheme prefer-{mode}"
    }, {
      "name": "qt",
      "templates": [{
          "version": "qt5",
          "output": "~/.config/qt5ct/colors/noctalia.conf"
        }, {
          "version": "qt6",
          "output": "~/.config/qt6ct/colors/noctalia.conf"
        }],
      "input": "qtct.conf"
    }, {
      "name": "kcolorscheme",
      "templates": [{
          "version": "kcolorscheme",
          "output": "~/.local/share/color-schemes/noctalia.colors"
        }],
      "input": "kcolorscheme.colors"
    }, {
      "name": "fuzzel",
      "templates": [{
          "version": "fuzzel",
          "output": "~/.config/fuzzel/themes/noctalia"
        }],
      "input": "fuzzel.conf",
      "postHook": AppThemeService.colorsApplyScript + " fuzzel"
    }, {
      "name": "vicinae",
      "templates": [{
          "version": "vicinae",
          "output": "~/.local/share/vicinae/themes/matugen.toml"
        }],
      "input": "vicinae.toml",
      "postHook": "cp -n " + Quickshell.shellDir + "/Assets/noctalia.svg ~/.local/share/vicinae/themes/noctalia.svg && " + AppThemeService.colorsApplyScript + " vicinae"
    }, {
      "name": "walker",
      "templates": [{
          "version": "walker",
          "output": "~/.config/walker/themes/noctalia/style.css"
        }],
      "input": "walker.css"
    }, {
      "name": "pywalfox",
      "templates": [{
          "version": "pywalfox",
          "output": "~/.cache/wal/colors.json"
        }],
      "input": "pywalfox.json",
      "postHook": AppThemeService.colorsApplyScript + " pywalfox"
    }, {
      "name": "discord_vesktop",
      "templates": [{
          "version": "discord_vesktop",
          "output": "~/.config/vesktop/themes/noctalia.theme.css"
        }],
      "input": "vesktop.css"
    }, {
      "name": "discord_webcord",
      "templates": [{
          "version": "discord_webcord",
          "output": "~/.config/webcord/themes/noctalia.theme.css"
        }],
      "input": "vesktop.css"
    }, {
      "name": "discord_armcord",
      "templates": [{
          "version": "discord_armcord",
          "output": "~/.config/armcord/themes/noctalia.theme.css"
        }],
      "input": "vesktop.css"
    }, {
      "name": "discord_equibop",
      "templates": [{
          "version": "discord_equibop",
          "output": "~/.config/equibop/themes/noctalia.theme.css"
        }],
      "input": "vesktop.css"
    }, {
      "name": "discord_lightcord",
      "templates": [{
          "version": "discord_lightcord",
          "output": "~/.config/lightcord/themes/noctalia.theme.css"
        }],
      "input": "vesktop.css"
    }, {
      "name": "discord_dorion",
      "templates": [{
          "version": "discord_dorion",
          "output": "~/.config/dorion/themes/noctalia.theme.css"
        }],
      "input": "vesktop.css"
    }, {
      "name": "discord_vencord",
      "templates": [{
          "version": "discord_vencord",
          "output": "~/.config/discord/themes/noctalia.theme.css"
        }],
      "input": "vesktop.css",
      "requiresThemesFolder": true
    }]

  // --------------------------------
  function addApplicationTemplates(lines, mode) {
    applications.forEach(function (app) {
      // Check if app has a condition and if it's met
      var shouldInclude = true
      if (app.condition !== undefined) {
        shouldInclude = app.condition
      }

      if (Settings.data.templates[app.name] && shouldInclude) {
        app.templates.forEach(function (template) {
          lines.push("\n[templates." + template.version + "]")
          lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/' + app.input + '"')
          lines.push('output_path = "' + template.output + '"')
          if (app.postHook) {
            var postHook = app.postHook.replace("{mode}", mode)
            lines.push('post_hook = "' + postHook + '"')
          }
        })
      }
    })
  }

  // Extract Discord clients from applications array
  readonly property var discordClients: {
    var clients = []
    for (var i = 0; i < applications.length; i++) {
      var app = applications[i]
      if (app.name && app.name.startsWith("discord_")) {
        var clientName = app.name.replace("discord_", "")
        var themePath = app.templates[0].output
        var configPath = themePath.replace("/themes/noctalia.theme.css", "")
        clients.push({
                       "name": clientName,
                       "configPath": configPath,
                       "themePath": themePath,
                       "requiresThemesFolder": app.requiresThemesFolder || false
                     })
      }
    }
    return clients
  }

  // Process for checking if user templates file exists
  Process {
    id: fileCheckProcess
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        // File exists, skip creation
        Logger.d("MatugenTemplates", "User templates config already exists, skipping creation")
      } else {
        // File doesn't exist, create it
        doWriteUserTemplatesToml()
      }
    }
  }
}
