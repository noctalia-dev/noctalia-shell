pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  readonly property string colorsApplyScript: Quickshell.shellDir + '/Bin/colors-apply.sh'

  // Terminal configurations (for wallpaper-based matugen templates)
  readonly property var terminals: [
    {
      "id": "foot",
      "name": "Foot",
      "matugenPath": "Terminal/foot",
      "outputPath": "~/.config/foot/themes/noctalia"
    },
    {
      "id": "ghostty",
      "name": "Ghostty",
      "matugenPath": "Terminal/ghostty",
      "outputPath": "~/.config/ghostty/themes/noctalia",
      "postHook": "bash -c 'pgrep -f ghostty >/dev/null && pkill -SIGUSR2 ghostty || true'"
    },
    {
      "id": "kitty",
      "name": "Kitty",
      "matugenPath": "Terminal/kitty.conf",
      "outputPath": "~/.config/kitty/themes/noctalia.conf"
    },
    {
      "id": "alacritty",
      "name": "Alacritty",
      "matugenPath": "Terminal/alacritty.toml",
      "outputPath": "~/.config/alacritty/themes/noctalia.toml"
    },
    {
      "id": "wezterm",
      "name": "Wezterm",
      "matugenPath": "Terminal/wezterm.toml",
      "outputPath": "~/.config/wezterm/colors/Noctalia.toml",
      "postHook": "touch ~/.config/wezterm/wezterm.lua"
    }
  ]

  // Application configurations - consolidated from MatugenTemplates + AppThemeService
  readonly property var applications: [
    {
      "id": "gtk",
      "name": "GTK",
      "category": "system",
      "input": "gtk.css",
      "outputs": [
        {
          "path": "~/.config/gtk-3.0/gtk.css"
        },
        {
          "path": "~/.config/gtk-4.0/gtk.css"
        }
      ],
      "postProcess": mode => `gsettings set org.gnome.desktop.interface color-scheme prefer-${mode}`
    },
    {
      "id": "qt",
      "name": "Qt",
      "category": "system",
      "input": "qtct.conf",
      "outputs": [
        {
          "path": "~/.config/qt5ct/colors/noctalia.conf"
        },
        {
          "path": "~/.config/qt6ct/colors/noctalia.conf"
        }
      ]
    },
    {
      "id": "kcolorscheme",
      "name": "KColorScheme",
      "category": "system",
      "input": "kcolorscheme.colors",
      "outputs": [
        {
          "path": "~/.local/share/color-schemes/noctalia.colors"
        }
      ]
    },
    {
      "id": "fuzzel",
      "name": "Fuzzel",
      "category": "launcher",
      "input": "fuzzel.conf",
      "outputs": [
        {
          "path": "~/.config/fuzzel/themes/noctalia"
        }
      ],
      "postProcess": () => `${colorsApplyScript} fuzzel`
    },
    {
      "id": "vicinae",
      "name": "Vicinae",
      "category": "launcher",
      "input": "vicinae.toml",
      "outputs": [
        {
          "path": "~/.local/share/vicinae/themes/noctalia.toml"
        }
      ],
      "postProcess": () => `cp --update=none ${Quickshell.shellDir}/Assets/noctalia.svg ~/.local/share/vicinae/themes/noctalia.svg && ${colorsApplyScript} vicinae`
    },
    {
      "id": "walker",
      "name": "Walker",
      "category": "launcher",
      "input": "walker.css",
      "outputs": [
        {
          "path": "~/.config/walker/themes/noctalia/style.css"
        }
      ],
      "postProcess": () => `${colorsApplyScript} walker`,
      "strict": true // Use strict mode for palette generation (preserves custom surface/outline values)
    },
    {
      "id": "pywalfox",
      "name": "Pywalfox",
      "category": "browser",
      "input": "pywalfox.json",
      "outputs": [
        {
          "path": "~/.cache/wal/colors.json"
        }
      ],
      "postProcess": mode => `${colorsApplyScript} pywalfox ${mode}`
    } // CONSOLIDATED DISCORD CLIENTS
    ,
    {
      "id": "discord",
      "name": "Discord",
      "category": "misc",
      "input": "vesktop.css",
      "clients": [
        {
          "name": "vesktop",
          "path": "~/.config/vesktop",
          "requiresThemesFolder": false
        },
        {
          "name": "webcord",
          "path": "~/.config/webcord",
          "requiresThemesFolder": false
        },
        {
          "name": "armcord",
          "path": "~/.config/armcord",
          "requiresThemesFolder": false
        },
        {
          "name": "equibop",
          "path": "~/.config/equibop",
          "requiresThemesFolder": false
        },
        {
          "name": "equicord",
          "path": "~/.config/Equicord",
          "requiresThemesFolder": false
        },
        {
          "name": "lightcord",
          "path": "~/.config/lightcord",
          "requiresThemesFolder": false
        },
        {
          "name": "dorion",
          "path": "~/.config/dorion",
          "requiresThemesFolder": false
        },
        {
          "name": "vencord",
          "path": "~/.config/Vencord",
          "requiresThemesFolder": false
        },
        {
          "name": "betterdiscord",
          "path": "~/.config/BetterDiscord",
          "requiresThemesFolder": false
        }
      ]
    },
    {
      "id": "code",
      "name": "VSCode",
      "category": "editor",
      "input": "code.json",
      "clients": [
        {
          "name": "code",
          "path": "~/.vscode/extensions/noctalia.noctaliatheme-0.0.5/themes/NoctaliaTheme-color-theme.json"
        },
        {
          "name": "codium",
          "path": "~/.vscode-oss/extensions/noctalia.noctaliatheme-0.0.5/themes/NoctaliaTheme-color-theme.json"
        }
      ]
    },
    {
      "id": "zed",
      "name": "Zed",
      "category": "editor",
      "input": "zed.json",
      "outputs": [
        {
          "path": "~/.config/zed/themes/noctalia.json"
        }
      ],
      "dualMode": true // Template contains both dark and light theme patterns
    },
    {
      "id": "helix",
      "name": "Helix",
      "category": "editor",
      "input": "helix.toml",
      "outputs": [
        {
          "path": "~/.config/helix/themes/noctalia.toml"
        }
      ]
    },
    {
      "id": "spicetify",
      "name": "Spicetify",
      "category": "audio",
      "input": "spicetify.ini",
      "outputs": [
        {
          "path": "~/.config/spicetify/Themes/Comfy/color.ini"
        }
      ],
      "postProcess": () => `spicetify -q apply --no-restart`
    },
    {
      "id": "telegram",
      "name": "Telegram",
      "category": "misc",
      "input": "telegram.tdesktop-theme",
      "outputs": [
        {
          "path": "~/.config/telegram-desktop/themes/noctalia.tdesktop-theme"
        }
      ]
    },
    {
      "id": "zenBrowser",
      "name": "Zen Browser",
      "category": "browser",
      "input": "zen-browser/zen-userChrome.css",
      "outputs": [
        {
          "path": "~/.cache/noctalia/zen-browser/zen-userChrome.css"
        },
        {
          "path": "~/.cache/noctalia/zen-browser/zen-userContent.css",
          "input": "zen-browser/zen-userContent.css"
        }
      ],
      "postProcess": ()
                     => "sh -c 'CSS_CHROME=\"$HOME/.cache/noctalia/zen-browser/zen-userChrome.css\"; CSS_CONTENT=\"$HOME/.cache/noctalia/zen-browser/zen-userContent.css\"; LINE_CHROME=\"@import \\\"$CSS_CHROME\\\";\"; LINE_CONTENT=\"@import \\\"$CSS_CONTENT\\\";\"; find \"$HOME/.zen\" -mindepth 2 -maxdepth 2 -type d -name chrome -print0 | while IFS= read -r -d \"\" dir; do USER_CHROME=\"$dir/userChrome.css\"; USER_CONTENT=\"$dir/userContent.css\"; mkdir -p \"$dir\"; touch \"$USER_CHROME\" \"$USER_CONTENT\"; sed -i \"/zen-browser\\/zen-userChrome\\.css/d\" \"$USER_CHROME\"; sed -i \"/zen-browser\\/zen-userContent\\.css/d\" \"$USER_CONTENT\"; if ! grep -Fq \"$LINE_CHROME\" \"$USER_CHROME\"; then printf \"%s\\n\" \"$LINE_CHROME\" >> \"$USER_CHROME\"; fi; if ! grep -Fq \"$LINE_CONTENT\" \"$USER_CONTENT\"; then printf \"%s\\n\" \"$LINE_CONTENT\" >> \"$USER_CONTENT\"; fi; done'"
    },
    {
      "id": "cava",
      "name": "Cava",
      "category": "audio",
      "input": "cava.ini",
      "outputs": [
        {
          "path": "~/.config/cava/themes/noctalia"
        }
      ],
      "postProcess": () => `${colorsApplyScript} cava`
    },
    {
      "id": "yazi",
      "name": "Yazi",
      "category": "misc",
      "input": "yazi.toml",
      "outputs": [
        {
          "path": "~/.config/yazi/flavors/noctalia.yazi/flavor.toml"
        }
      ]
    },
    {
      "id": "emacs",
      "name": "Emacs",
      "category": "editor",
      "input": "emacs.el",
      "outputs": [
        {
          "path": "~/.config/doom/themes/noctalia-theme.el"
        },
        {
          "path": "~/.emacs.d/themes/noctalia-theme.el"
        }
      ],
      "checkDoomFirst": true
    },
    {
      "id": "niri",
      "name": "Niri",
      "category": "compositor",
      "input": "niri.kdl",
      "outputs": [
        {
          "path": "~/.config/niri/noctalia.kdl"
        }
      ],
      "postProcess": () => `${colorsApplyScript} niri`
    },
    {
      "id": "hyprland",
      "name": "Hyprland",
      "category": "compositor",
      "input": "hyprland.conf",
      "outputs": [
        {
          "path": "~/.config/hypr/noctalia/noctalia-colors.conf"
        }
      ],
      "postProcess": () => `${colorsApplyScript} hyprland`
    },
    {
      "id": "mango",
      "name": "Mango",
      "category": "compositor",
      "input": "mango.conf",
      "outputs": [
        {
          "path": "~/.config/mango/noctalia.conf"
        }
      ],
      "postProcess": () => `${colorsApplyScript} mango`
    }
  ]

  // Extract Discord clients for ProgramCheckerService compatibility
  readonly property var discordClients: {
    var clients = [];
    var discordApp = applications.find(app => app.id === "discord");
    if (discordApp && discordApp.clients) {
      discordApp.clients.forEach(client => {
                                   clients.push({
                                                  "name": client.name,
                                                  "configPath": client.path,
                                                  "themePath": `${client.path}/themes/noctalia.theme.css`,
                                                  "requiresThemesFolder": client.requiresThemesFolder || false
                                                });
                                 });
    }
    return clients;
  }

  // Extract Code clients for ProgramCheckerService compatibility
  readonly property var codeClients: {
    var clients = [];
    var codeApp = applications.find(app => app.id === "code");
    if (codeApp && codeApp.clients) {
      codeApp.clients.forEach(client => {
                                // Extract base config directory from theme path
                                var themePath = client.path;
                                var baseConfigDir = "";
                                if (client.name === "code") {
                                  // For VSCode: ~/.vscode/extensions/... -> ~/.vscode
                                  baseConfigDir = "~/.vscode";
                                } else if (client.name === "codium") {
                                  // For VSCodium: ~/.vscode-oss/extensions/... -> ~/.vscode-oss
                                  baseConfigDir = "~/.vscode-oss";
                                }
                                clients.push({
                                               "name": client.name,
                                               "configPath": baseConfigDir,
                                               "themePath": themePath,
                                               "requiresThemesFolder": false
                                             });
                              });
    }
    return clients;
  }

  // Build user templates TOML content
  function buildUserTemplatesToml() {
    var lines = [];
    lines.push("[config]");
    lines.push("");
    lines.push("[templates]");
    lines.push("");
    lines.push("# User-defined templates");
    lines.push("# Add your custom templates below");
    lines.push("# Example:");
    lines.push("# [templates.myapp]");
    lines.push("# input_path = \"~/.config/noctalia/templates/myapp.css\"");
    lines.push("# output_path = \"~/.config/myapp/theme.css\"");
    lines.push("# post_hook = \"myapp --reload-theme\"");
    lines.push("");
    lines.push("# Remove this section and add your own templates");
    lines.push("#[templates.placeholder]");
    lines.push("#input_path = \"" + Quickshell.shellDir + "/Assets/MatugenTemplates/noctalia.json\"");
    lines.push("#output_path = \"" + Settings.cacheDir + "placeholder.json\"");
    lines.push("");

    return lines.join("\n") + "\n";
  }

  // Write user templates TOML file (moved from MatugenTemplates)
  function writeUserTemplatesToml() {
    var userConfigPath = Settings.configDir + "user-templates.toml";

    // Check if file already exists
    fileCheckProcess.command = ["test", "-f", userConfigPath];
    fileCheckProcess.running = true;
  }

  function doWriteUserTemplatesToml() {
    var userConfigPath = Settings.configDir + "user-templates.toml";
    var configContent = buildUserTemplatesToml();
    var userConfigPathEsc = userConfigPath.replace(/'/g, "'\\''");

    // Ensure directory exists (should already exist but just in case)
    Quickshell.execDetached(["mkdir", "-p", Settings.configDir]);

    // Write the config file using heredoc to avoid escaping issues
    var script = `cat > '${userConfigPathEsc}' << 'EOF'\n`;
    script += configContent;
    script += "EOF\n";
    Quickshell.execDetached(["sh", "-c", script]);

    Logger.d("TemplateRegistry", "User templates config written to:", userConfigPath);
  }

  // Process for checking if user templates file exists
  Process {
    id: fileCheckProcess
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        // File exists, skip creation
        Logger.d("TemplateRegistry", "User templates config already exists, skipping creation");
      } else {
        // File doesn't exist, create it
        doWriteUserTemplatesToml();
      }
    }
  }
}
