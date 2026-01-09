import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Services.Theming
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NText {
    text: I18n.tr("panels.color-scheme.templates-desc")
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  NCollapsible {
    Layout.fillWidth: true
    label: I18n.tr("panels.color-scheme.templates-ui-label")
    description: I18n.tr("panels.color-scheme.templates-ui-description")
    expanded: true

    NCheckbox {
      label: "GTK"
      description: I18n.tr("panels.color-scheme.templates-ui-qt-description", {
                             "filepath": "~/.config/gtk-3.0/gtk.css & ~/.config/gtk-4.0/gtk.css"
                           })
      checked: Settings.data.templates.gtk
      onToggled: checked => {
                   Settings.data.templates.gtk = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Qt"
      description: I18n.tr("panels.color-scheme.templates-ui-qt-description", {
                             "filepath": "~/.config/qt5ct/colors/noctalia.conf & ~/.config/qt6ct/colors/noctalia.conf"
                           })
      checked: Settings.data.templates.qt
      onToggled: checked => {
                   Settings.data.templates.qt = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "KColorScheme"
      description: I18n.tr("panels.color-scheme.templates-ui-qt-description", {
                             "filepath": "~/.local/share/color-schemes/noctalia.colors"
                           })
      checked: Settings.data.templates.kcolorscheme
      onToggled: checked => {
                   Settings.data.templates.kcolorscheme = checked;
                   AppThemeService.generate();
                 }
    }
  }

  NCollapsible {
    Layout.fillWidth: true
    label: I18n.tr("panels.color-scheme.templates-compositors-label")
    description: I18n.tr("panels.color-scheme.templates-compositors-description")
    expanded: true

    NCheckbox {
      label: "Niri"
      description: I18n.tr("panels.color-scheme.templates-compositors-niri-description", {
                             "filepath": "~/.config/niri/noctalia.kdl"
                           })
      checked: Settings.data.templates.niri
      onToggled: checked => {
                   Settings.data.templates.niri = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Hyprland"
      description: I18n.tr("panels.color-scheme.templates-ui-qt-description", {
                             "filepath": "~/.config/hypr/noctalia/noctalia-colors.conf"
                           })
      checked: Settings.data.templates.hyprland
      onToggled: checked => {
                   Settings.data.templates.hyprland = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Mango"
      description: I18n.tr("panels.color-scheme.templates-compositors-mango-description", {
                             "filepath": "~/.config/mango/noctalia.conf"
                           })
      checked: Settings.data.templates.mango
      onToggled: checked => {
                   Settings.data.templates.mango = checked;
                   AppThemeService.generate();
                 }
    }
  }

  NCollapsible {
    Layout.fillWidth: true
    label: I18n.tr("panels.color-scheme.templates-terminal-label")
    description: I18n.tr("panels.color-scheme.templates-terminal-description")
    expanded: false

    NCheckbox {
      label: "Alacritty"
      description: I18n.tr("panels.color-scheme.templates-programs-zed-description", {
                             "filepath": "~/.config/alacritty/themes/noctalia"
                           })
      checked: Settings.data.templates.alacritty
      onToggled: checked => {
                   Settings.data.templates.alacritty = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Kitty"
      description: I18n.tr("panels.color-scheme.templates-programs-zed-description", {
                             "filepath": "~/.config/kitty/themes/noctalia.conf"
                           })
      checked: Settings.data.templates.kitty
      onToggled: checked => {
                   Settings.data.templates.kitty = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Ghostty"
      description: I18n.tr("panels.color-scheme.templates-programs-zed-description", {
                             "filepath": "~/.config/ghostty/themes/noctalia"
                           })
      checked: Settings.data.templates.ghostty
      onToggled: checked => {
                   Settings.data.templates.ghostty = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Foot"
      description: I18n.tr("panels.color-scheme.templates-programs-zed-description", {
                             "filepath": "~/.config/foot/themes/noctalia"
                           })
      checked: Settings.data.templates.foot
      onToggled: checked => {
                   Settings.data.templates.foot = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Wezterm"
      description: I18n.tr("panels.color-scheme.templates-programs-zed-description", {
                             "filepath": "~/.config/wezterm/colors/Noctalia.toml"
                           })
      checked: Settings.data.templates.wezterm
      onToggled: checked => {
                   Settings.data.templates.wezterm = checked;
                   AppThemeService.generate();
                 }
    }
  }

  NCollapsible {
    Layout.fillWidth: true
    label: I18n.tr("panels.color-scheme.templates-programs-label")
    description: I18n.tr("panels.color-scheme.templates-programs-description")
    expanded: false

    NCheckbox {
      label: "Fuzzel"
      description: I18n.tr("panels.color-scheme.templates-programs-zed-description", {
                             "filepath": "~/.config/fuzzel/themes/noctalia"
                           })
      checked: Settings.data.templates.fuzzel
      onToggled: checked => {
                   Settings.data.templates.fuzzel = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      id: discordToggle
      label: "Discord"
      description: {
        if (ProgramCheckerService.availableDiscordClients.length === 0) {
          return I18n.tr("panels.color-scheme.templates-programs-discord-description-missing");
        } else {
          var clientInfo = [];
          for (var i = 0; i < ProgramCheckerService.availableDiscordClients.length; i++) {
            var client = ProgramCheckerService.availableDiscordClients[i];
            clientInfo.push(client.name.charAt(0).toUpperCase() + client.name.slice(1));
          }
          return I18n.tr("panels.color-scheme.templates-programs-discord-description-detected", {
                           "clients": clientInfo.join(", ")
                         });
        }
      }
      Layout.fillWidth: true
      Layout.preferredWidth: -1
      checked: Settings.data.templates.discord
      enabled: ProgramCheckerService.availableDiscordClients.length > 0
      onToggled: checked => {
                   Settings.data.templates.discord = checked;
                   if (ProgramCheckerService.availableDiscordClients.length > 0) {
                     AppThemeService.generate();
                   }
                 }
    }

    NCheckbox {
      label: "Pywalfox"
      description: I18n.tr("panels.color-scheme.templates-programs-pywalfox-description", {
                             "filepath": "~/.cache/wal/colors.json"
                           })
      checked: Settings.data.templates.pywalfox
      onToggled: checked => {
                   Settings.data.templates.pywalfox = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Vicinae"
      description: I18n.tr("panels.color-scheme.templates-programs-zed-description", {
                             "filepath": "~/.local/share/vicinae/themes/matugen.toml"
                           })
      checked: Settings.data.templates.vicinae
      onToggled: checked => {
                   Settings.data.templates.vicinae = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Walker"
      description: I18n.tr("panels.color-scheme.templates-programs-walker-description", {
                             "filepath": "~/.config/walker/style.css"
                           })
      checked: Settings.data.templates.walker
      onToggled: checked => {
                   Settings.data.templates.walker = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      id: codeToggle
      label: "Code"
      description: {
        if (ProgramCheckerService.availableCodeClients.length === 0) {
          return I18n.tr("panels.color-scheme.templates-programs-code-description-missing");
        } else {
          var clientInfo = [];
          for (var i = 0; i < ProgramCheckerService.availableCodeClients.length; i++) {
            var client = ProgramCheckerService.availableCodeClients[i];
            var clientName = client.name === "code" ? "VSCode" : "VSCodium";
            clientInfo.push(clientName);
          }
          return I18n.tr("panels.color-scheme.templates-programs-code-description-detected", {
                           "clients": clientInfo.join(", ")
                         });
        }
      }
      Layout.fillWidth: true
      Layout.preferredWidth: -1
      checked: Settings.data.templates.code
      enabled: ProgramCheckerService.availableCodeClients.length > 0
      onToggled: checked => {
                   Settings.data.templates.code = checked;
                   if (ProgramCheckerService.availableCodeClients.length > 0) {
                     AppThemeService.generate();
                   }
                 }
    }

    NCheckbox {
      label: "Spicetify"
      description: I18n.tr("panels.color-scheme.templates-programs-spicetify-description", {
                             "filepath": "~/.config/spicetify/Themes/Comfy/color.ini"
                           })
      checked: Settings.data.templates.spicetify
      onToggled: checked => {
                   Settings.data.templates.spicetify = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Telegram"
      description: I18n.tr("panels.color-scheme.templates-ui-qt-description", {
                             "filepath": "~/.config/telegram-desktop/themes/noctalia.tdesktop-theme"
                           })
      checked: Settings.data.templates.telegram
      onToggled: checked => {
                   Settings.data.templates.telegram = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Cava"
      description: I18n.tr("panels.color-scheme.templates-ui-qt-description", {
                             "filepath": "~/.config/cava/themes/noctalia"
                           })
      checked: Settings.data.templates.cava
      onToggled: checked => {
                   Settings.data.templates.cava = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Yazi"
      description: I18n.tr("panels.color-scheme.templates-programs-yazi-description", {
                             "filepath": "~/.config/yazi/flavors/noctalia.yazi/flavor.toml"
                           })
      checked: Settings.data.templates.yazi
      onToggled: checked => {
                   Settings.data.templates.yazi = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Zed"
      description: I18n.tr("panels.color-scheme.templates-programs-zed-description", {
                             "filepath": "~/.config/zed/themes/noctalia.json"
                           })
      checked: Settings.data.templates.zed
      onToggled: checked => {
                   Settings.data.templates.zed = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Zen Browser"
      description: I18n.tr("panels.color-scheme.templates-programs-zen-browser-description", {
                             "filepath": "~/.cache/noctalia/zen-browser/zen-userChrome.css"
                           })
      checked: Settings.data.templates.zenBrowser
      onToggled: checked => {
                   Settings.data.templates.zenBrowser = checked;
                   AppThemeService.generate();
                 }
    }

    NCheckbox {
      label: "Emacs"
      description: I18n.tr("panels.color-scheme.templates-programs-emacs-description")
      checked: Settings.data.templates.emacs
      onToggled: checked => {
                   Settings.data.templates.emacs = checked;
                   AppThemeService.generate();
                 }
    }
  }

  NCollapsible {
    Layout.fillWidth: true
    label: I18n.tr("panels.color-scheme.templates-misc-label")
    description: I18n.tr("panels.color-scheme.templates-misc-description")
    expanded: false

    NCheckbox {
      label: I18n.tr("panels.color-scheme.templates-misc-user-templates-label")
      description: I18n.tr("panels.color-scheme.templates-misc-user-templates-description")
      checked: Settings.data.templates.enableUserTemplates
      onToggled: checked => {
                   Settings.data.templates.enableUserTemplates = checked;
                   if (checked) {
                     TemplateRegistry.writeUserTemplatesToml();
                   }
                   AppThemeService.generate();
                 }
    }
  }
}
