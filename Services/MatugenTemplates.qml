pragma Singleton

import QtQuick
import Quickshell
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
                       "output": "~/.config/ghostty/themes/noctalia"
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

  // --------------------------------
  function addApplicationTemplates(lines, mode) {
    var applications = [{
                          "name": "gtk",
                          "templates": [{
                              "version": "gtk3",
                              "output": "~/.config/gtk-3.0/gtk.css"
                            }, {
                              "version": "gtk4",
                              "output": "~/.config/gtk-4.0/gtk.css"
                            }],
                          "input": "gtk.css",
                          "postHook": "gsettings set org.gnome.desktop.interface color-scheme prefer-" + mode
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
                          "name": "fuzzel",
                          "templates": [{
                              "version": "fuzzel",
                              "output": "~/.config/fuzzel/themes/noctalia"
                            }],
                          "input": "fuzzel.conf",
                          "postHook": AppThemeService.colorsApplyScript + " fuzzel"
                        }, {
                          "name": "pywalfox",
                          "templates": [{
                              "version": "pywalfox",
                              "output": "~/.cache/wal/colors.json"
                            }],
                          "input": "pywalfox.json",
                          "postHook": AppThemeService.colorsApplyScript + " pywalfox"
                        }, {
                          "name": "vesktop",
                          "templates": [{
                              "version": "vesktop",
                              "output": "~/.config/vesktop/themes/noctalia.theme.css"
                            }],
                          "input": "vesktop.css"
                        }]

    applications.forEach(function (app) {
      if (Settings.data.templates[app.name]) {
        app.templates.forEach(function (template) {
          lines.push("\n[templates." + template.version + "]")
          lines.push('input_path = "' + Quickshell.shellDir + '/Assets/MatugenTemplates/' + app.input + '"')
          lines.push('output_path = "' + template.output + '"')
          if (app.postHook) {
            lines.push('post_hook = "' + app.postHook + '"')
          }
        })
      }
    })
  }
}
