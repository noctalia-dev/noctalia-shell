pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  readonly property string templateApplyScript: Quickshell.shellDir + '/Scripts/bash/template-apply.sh'
  readonly property string gtkRefreshScript: Quickshell.shellDir + '/Scripts/python/src/theming/gtk-refresh.py'
  readonly property string vscodeHelperScript: Quickshell.shellDir + '/Scripts/python/src/theming/vscode-helper.py'

  // Dynamically resolved VSCode extension theme paths (all matching noctalia extensions)
  property var resolvedCodePaths: []
  property var resolvedCodiumPaths: []

  // Terminal configurations (for wallpaper-based templates)
  // Each terminal must define a postHook that sets up config includes and triggers reload
  readonly property var terminals: [
    {
      "id": "foot",
      "name": "Foot",
      "templatePath": "terminal/foot",
      "outputPath": "~/.config/foot/themes/noctalia",
      "postHook": `${templateApplyScript} foot`
    },
    {
      "id": "ghostty",
      "name": "Ghostty",
      "templatePath": "terminal/ghostty",
      "outputPath": "~/.config/ghostty/themes/noctalia",
      "postHook": `${templateApplyScript} ghostty`
    },
    {
      "id": "kitty",
      "name": "Kitty",
      "templatePath": "terminal/kitty.conf",
      "outputPath": "~/.config/kitty/themes/noctalia.conf",
      "postHook": `${templateApplyScript} kitty`
    },
    {
      "id": "alacritty",
      "name": "Alacritty",
      "templatePath": "terminal/alacritty.toml",
      "outputPath": "~/.config/alacritty/themes/noctalia.toml",
      "postHook": `${templateApplyScript} alacritty`
    },
    {
      "id": "wezterm",
      "name": "Wezterm",
      "templatePath": "terminal/wezterm.toml",
      "outputPath": "~/.config/wezterm/colors/Noctalia.toml",
      "postHook": `${templateApplyScript} wezterm`
    }
  ]

  // Application configurations - consolidated from Theming + AppThemeService
  readonly property var applications: [
    {
      "id": "gtk",
      "name": "GTK",
      "category": "system",
      "input": "gtk.css",
      "outputs": [
        {
          "path": "~/.config/gtk-3.0/noctalia.css"
        },
        {
          "path": "~/.config/gtk-4.0/noctalia.css"
        }
      ],
      "postProcess": mode => `python3 ${gtkRefreshScript} ${mode}`
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
      ],
      "postProcess": () => "if command -v plasma-apply-colorscheme >/dev/null 2>&1; then plasma-apply-colorscheme BreezeDark; sleep 0.5; plasma-apply-colorscheme noctalia; fi"
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
      "postProcess": () => `${templateApplyScript} fuzzel`
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
      "postProcess": () => `cp --update=none ${Quickshell.shellDir}/Assets/noctalia.svg ~/.local/share/vicinae/themes/noctalia.svg && ${templateApplyScript} vicinae`
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
      "postProcess": () => `${templateApplyScript} walker`,
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
      "postProcess": mode => `${templateApplyScript} pywalfox ${mode}`
    } // CONSOLIDATED DISCORD CLIENTS
    ,
    {
      "id": "discord",
      "name": "Discord",
      "category": "misc",
      "input": ["discord-midnight.css", "discord-material.css"],
      "clients": [
        {
          "name": "vesktop",
          "path": "~/.config/vesktop"
        },
        {
          "name": "webcord",
          "path": "~/.config/webcord"
        },
        {
          "name": "armcord",
          "path": "~/.config/armcord"
        },
        {
          "name": "equibop",
          "path": "~/.config/equibop"
        },
        {
          "name": "equicord",
          "path": "~/.config/Equicord"
        },
        {
          "name": "lightcord",
          "path": "~/.config/lightcord"
        },
        {
          "name": "dorion",
          "path": "~/.config/dorion"
        },
        {
          "name": "vencord",
          "path": "~/.config/Vencord"
        },
        {
          "name": "betterdiscord",
          "path": "~/.config/BetterDiscord"
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
          "path": "~/.vscode-oss/extensions/noctalia.noctaliatheme-0.0.5-universal/themes/NoctaliaTheme-color-theme.json"
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
                     => "sh -c 'CSS_CHROME=\"$HOME/.cache/noctalia/zen-browser/zen-userChrome.css\"; CSS_CONTENT=\"$HOME/.cache/noctalia/zen-browser/zen-userContent.css\"; LINE_CHROME=\"@import \\\"$CSS_CHROME\\\";\"; LINE_CONTENT=\"@import \\\"$CSS_CONTENT\\\";\"; find \"$HOME/.config/zen\" \"$HOME/.zen\" -mindepth 2 -maxdepth 2 -type d -name chrome -print0 2>/dev/null | while IFS= read -r -d \"\" dir; do USER_CHROME=\"$dir/userChrome.css\"; USER_CONTENT=\"$dir/userContent.css\"; mkdir -p \"$dir\"; touch \"$USER_CHROME\" \"$USER_CONTENT\"; sed -i \"/zen-browser\\/zen-userChrome\\.css/d\" \"$USER_CHROME\"; sed -i \"/zen-browser\\/zen-userContent\\.css/d\" \"$USER_CONTENT\"; if ! grep -Fq \"$LINE_CHROME\" \"$USER_CHROME\"; then printf \"%s\\n\" \"$LINE_CHROME\" >> \"$USER_CHROME\"; fi; if ! grep -Fq \"$LINE_CONTENT\" \"$USER_CONTENT\"; then printf \"%s\\n\" \"$LINE_CONTENT\" >> \"$USER_CONTENT\"; fi; done'"
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
      "postProcess": () => `${templateApplyScript} cava`
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
      ],
      "postProcess": () => `${templateApplyScript} yazi`
    },
    {
      "id": "emacs",
      "name": "Emacs",
      "category": "editor",
      "input": "emacs.el"
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
      "postProcess": () => `${templateApplyScript} niri`
    },
    {
      "id": "sway",
      "name": "Sway",
      "category": "compositor",
      "input": "sway",
      "outputs": [
        {
          "path": "~/.config/sway/noctalia"
        }
      ],
      "postProcess": () => `${templateApplyScript} sway`
    },
    {
      "id": "scroll",
      "name": "Scroll",
      "category": "compositor",
      "input": "sway",
      "outputs": [
        {
          "path": "~/.config/scroll/noctalia"
        }
      ],
      "postProcess": () => `${templateApplyScript} scroll`
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
      "postProcess": () => `${templateApplyScript} hyprland`
    },
    {
      "id": "hyprtoolkit",
      "name": "Hyprtoolkit",
      "category": "system",
      "input": "hyprtoolkit.conf",
      "outputs": [
        {
          "path": "~/.config/hypr/hyprtoolkit.conf"
        }
      ]
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
      "postProcess": () => `${templateApplyScript} mango`
    },
    {
      "id": "btop",
      "name": "btop",
      "category": "misc",
      "input": "btop.theme",
      "outputs": [
        {
          "path": "~/.config/btop/themes/noctalia.theme"
        }
      ],
      "postProcess": () => `${templateApplyScript} btop`
    },
    {
      "id": "zathura",
      "name": "Zathura",
      "category": "misc",
      "input": "zathurarc",
      "outputs": [
        {
          "path": "~/.config/zathura/noctaliarc"
        }
      ],
      "postProcess": () => `${templateApplyScript} zathura`
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
                                                  "themePath": `${client.path}/themes/noctalia.theme.css`
                                                });
                                 });
    }
    return clients;
  }

  // Get resolved theme paths for a code client (returns array of all matching paths)
  function resolvedCodeClientPaths(clientName) {
    if (clientName === "code")
      return resolvedCodePaths;
    if (clientName === "codium")
      return resolvedCodiumPaths;
    return [];
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
                                               "themePath": "" // resolved dynamically via resolvedCodeClientPaths()
                                             });
                              });
    }
    return clients;
  }

  // Resolve VSCode extension paths dynamically
  Process {
    id: codeResolverProcess
    command: ["python3", vscodeHelperScript, "~/.vscode/extensions"]
    running: true
    property var paths: []
    stdout: SplitParser {
      onRead: data => {
        var line = data.trim();
        if (line)
        codeResolverProcess.paths.push(line);
      }
    }
    onExited: {
      root.resolvedCodePaths = paths;
    }
  }

  Process {
    id: codiumResolverProcess
    command: ["python3", vscodeHelperScript, "~/.vscode-oss/extensions"]
    running: true
    property var paths: []
    stdout: SplitParser {
      onRead: data => {
        var line = data.trim();
        if (line)
        codiumResolverProcess.paths.push(line);
      }
    }
    onExited: {
      root.resolvedCodiumPaths = paths;
    }
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
    lines.push("#input_path = \"" + Quickshell.shellDir + "/Assets/Templates/noctalia.json\"");
    lines.push("#output_path = \"" + Settings.cacheDir + "placeholder.json\"");
    lines.push("");

    return lines.join("\n") + "\n";
  }

  // Write user templates TOML file (moved from Theming)
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

  // Extract Emacs clients for ProgramCheckerService compatibility
  readonly property var emacsClients: [
    {
      "name": "doom",
      "path": "~/.config/doom"
    },
    {
      "name": "modern",
      "path": "~/.config/emacs"
    },
    {
      "name": "traditional",
      "path": "~/.emacs.d"
    }
  ]

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
