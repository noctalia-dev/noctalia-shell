import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."
import qs.Commons
import qs.Services.System
import qs.Services.Theming
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  // Cache for scheme JSON (can be flat or {dark, light})
  property var schemeColorsCache: ({})
  property int cacheVersion: 0 // Increment to trigger UI updates

  // Time dropdown options (00:00 .. 23:30)
  ListModel {
    id: timeOptions
  }
  Component.onCompleted: {
    for (var h = 0; h < 24; h++) {
      for (var m = 0; m < 60; m += 30) {
        var hh = ("0" + h).slice(-2);
        var mm = ("0" + m).slice(-2);
        var key = hh + ":" + mm;
        timeOptions.append({
                             "key": key,
                             "name": key
                           });
      }
    }
  }

  spacing: Style.marginL

  // Helper function to extract scheme name from path
  function extractSchemeName(schemePath) {
    var pathParts = schemePath.split("/");
    var filename = pathParts[pathParts.length - 1];
    var schemeName = filename.replace(".json", "");

    if (schemeName === "Noctalia-default") {
      schemeName = "Noctalia (default)";
    } else if (schemeName === "Noctalia-legacy") {
      schemeName = "Noctalia (legacy)";
    } else if (schemeName === "Tokyo-Night") {
      schemeName = "Tokyo Night";
    } else if (schemeName === "Rosepine") {
      schemeName = "Rose Pine";
    }

    return schemeName;
  }

  // Helper function to get color from scheme file (supports dark/light variants)
  function getSchemeColor(schemeName, colorKey) {
    // Access cache version to create dependency
    var _ = cacheVersion;

    if (schemeColorsCache[schemeName]) {
      var entry = schemeColorsCache[schemeName];
      var variant = entry;

      // Check if scheme has dark/light variants
      if (entry.dark || entry.light) {
        variant = Settings.data.colorSchemes.darkMode ? (entry.dark || entry.light) : (entry.light || entry.dark);
      }

      if (variant && variant[colorKey]) {
        return variant[colorKey];
      }
    }

    // Return visible defaults while loading
    if (colorKey === "mSurface")
      return Color.mSurfaceVariant;
    if (colorKey === "mPrimary")
      return Color.mPrimary;
    if (colorKey === "mSecondary")
      return Color.mSecondary;
    if (colorKey === "mTertiary")
      return Color.mTertiary;
    if (colorKey === "mError")
      return Color.mError;
    return Color.mOnSurfaceVariant;
  }

  // This function is called by the FileView Repeater when a scheme file is loaded
  function schemeLoaded(schemeName, jsonData) {
    var value = jsonData || {};
    schemeColorsCache[schemeName] = value;
    // Force UI update by incrementing cache version
    cacheVersion++;
  }

  // Function to open download popup
  function openDownloadPopup() {
    downloadPopupLoader.open();
  }

  // When the list of available schemes changes, clear the cache
  Connections {
    target: ColorSchemeService
    function onSchemesChanged() {
      schemeColorsCache = {};
      cacheVersion++;
    }
  }

  // Simple process to check if matugen exists
  Process {
    id: matugenCheck
    command: ["which", "matugen"]
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        Settings.data.colorSchemes.useWallpaperColors = true;
        AppThemeService.generate();
        ToastService.showNotice(I18n.tr("toast.wallpaper-colors.label"), I18n.tr("toast.wallpaper-colors.enabled"), "settings-color-scheme");
      } else {
        ToastService.showWarning(I18n.tr("oast.wallpaper-colors.label"), I18n.tr("toast.wallpaper-colors.not-installed"));
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // A non-visual Item to host the Repeater that loads the color scheme files
  Item {
    id: fileLoaders
    visible: false

    Repeater {
      model: ColorSchemeService.schemes
      delegate: Item {
        FileView {
          path: modelData
          blockLoading: false
          onLoaded: {
            var schemeName = root.extractSchemeName(path);

            try {
              var jsonData = JSON.parse(text());
              root.schemeLoaded(schemeName, jsonData);
            } catch (e) {
              Logger.w("ColorSchemeTab", "Failed to parse JSON for scheme:", schemeName, e);
              root.schemeLoaded(schemeName, null);
            }
          }
        }
      }
    }
  }

  // Main Toggles - Dark Mode / Matugen
  NHeader {
    label: I18n.tr("settings.color-scheme.color-source.section.label")
    description: I18n.tr("settings.color-scheme.color-source.section.description")
  }

  // Dark Mode Toggle
  NToggle {
    label: I18n.tr("settings.color-scheme.dark-mode.switch.label")
    description: I18n.tr("settings.color-scheme.dark-mode.switch.description")
    checked: Settings.data.colorSchemes.darkMode
    onToggled: checked => {
                 Settings.data.colorSchemes.darkMode = checked;
                 root.cacheVersion++; // Force UI update for dark/light variants
               }
  }

  NComboBox {
    label: I18n.tr("settings.color-scheme.dark-mode.mode.label")
    description: I18n.tr("settings.color-scheme.dark-mode.mode.description")

    model: [
      {
        "name": I18n.tr("settings.color-scheme.dark-mode.mode.off"),
        "key": "off"
      },
      {
        "name": I18n.tr("settings.color-scheme.dark-mode.mode.manual"),
        "key": "manual"
      },
      {
        "name": I18n.tr("settings.color-scheme.dark-mode.mode.location"),
        "key": "location"
      }
    ]

    currentKey: Settings.data.colorSchemes.schedulingMode

    onSelected: key => {
                  Settings.data.colorSchemes.schedulingMode = key;
                  AppThemeService.generate();
                }
  }

  // Manual scheduling
  ColumnLayout {
    spacing: Style.marginS
    visible: Settings.data.colorSchemes.schedulingMode === "manual"

    NLabel {
      label: I18n.tr("settings.display.night-light.manual-schedule.label")
      description: I18n.tr("settings.display.night-light.manual-schedule.description")
    }

    RowLayout {
      Layout.fillWidth: false
      spacing: Style.marginS

      NText {
        text: I18n.tr("settings.display.night-light.manual-schedule.sunrise")
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
      }

      NComboBox {
        model: timeOptions
        currentKey: Settings.data.colorSchemes.manualSunrise
        placeholder: I18n.tr("settings.display.night-light.manual-schedule.select-start")
        onSelected: key => Settings.data.colorSchemes.manualSunrise = key
        minimumWidth: 120
      }

      Item {
        Layout.preferredWidth: 20
      }

      NText {
        text: I18n.tr("settings.display.night-light.manual-schedule.sunset")
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
      }

      NComboBox {
        model: timeOptions
        currentKey: Settings.data.colorSchemes.manualSunset
        placeholder: I18n.tr("settings.display.night-light.manual-schedule.select-stop")
        onSelected: key => Settings.data.colorSchemes.manualSunset = key
        minimumWidth: 120
      }
    }
  }

  // Use Wallpaper Colors
  NToggle {
    label: I18n.tr("settings.color-scheme.color-source.use-wallpaper-colors.label")
    description: I18n.tr("settings.color-scheme.color-source.use-wallpaper-colors.description")
    enabled: ProgramCheckerService.matugenAvailable
    checked: Settings.data.colorSchemes.useWallpaperColors
    onToggled: checked => {
                 if (checked) {
                   matugenCheck.running = true;
                 } else {
                   Settings.data.colorSchemes.useWallpaperColors = false;
                   ToastService.showNotice(I18n.tr("toast.wallpaper-colors.label"), I18n.tr("toast.wallpaper-colors.disabled"), "settings-color-scheme");

                   if (Settings.data.colorSchemes.predefinedScheme) {
                     ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme);
                   }
                 }
               }
  }

  // Matugen Scheme Type Selection [Descriptions sourced from DankMaterialShell]
  NComboBox {
    label: I18n.tr("settings.color-scheme.color-source.matugen-scheme-type.label")
    description: I18n.tr("settings.color-scheme.color-source.matugen-scheme-type.description." + Settings.data.colorSchemes.matugenSchemeType)
    enabled: Settings.data.colorSchemes.useWallpaperColors
    visible: Settings.data.colorSchemes.useWallpaperColors

    model: [
      {
        "key": "scheme-content",
        "name": "Content"
      },
      {
        "key": "scheme-expressive",
        "name": "Expressive"
      },
      {
        "key": "scheme-fidelity",
        "name": "Fidelity"
      },
      {
        "key": "scheme-fruit-salad",
        "name": "Fruit Salad"
      },
      {
        "key": "scheme-monochrome",
        "name": "Monochrome"
      },
      {
        "key": "scheme-neutral",
        "name": "Neutral"
      },
      {
        "key": "scheme-rainbow",
        "name": "Rainbow"
      },
      {
        "key": "scheme-tonal-spot",
        "name": "Tonal Spot"
      }
    ]

    currentKey: Settings.data.colorSchemes.matugenSchemeType

    onSelected: key => {
                  Settings.data.colorSchemes.matugenSchemeType = key;
                  AppThemeService.generate();
                }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
    visible: !Settings.data.colorSchemes.useWallpaperColors
  }

  // Predefined Color Schemes
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true
    visible: !Settings.data.colorSchemes.useWallpaperColors

    NHeader {
      label: I18n.tr("settings.color-scheme.predefined.section.label")
      description: I18n.tr("settings.color-scheme.predefined.section.description")
      Layout.fillWidth: true
    }

    NButton {
      text: I18n.tr("settings.color-scheme.download.button")
      icon: "download"
      onClicked: root.openDownloadPopup()
      Layout.alignment: Qt.AlignRight
    }

    // Download popup
    Loader {
      id: downloadPopupLoader
      active: false
      sourceComponent: SchemeDownloader {
        parent: Overlay.overlay
      }

      property bool pendingOpen: false

      function open() {
        pendingOpen = true;
        active = true;
        if (item) {
          item.open();
          pendingOpen = false;
        }
      }

      onItemChanged: {
        if (item && pendingOpen) {
          item.open();
          pendingOpen = false;
        }
      }
    }

    // Color Schemes Grid
    GridLayout {
      columns: 2
      rowSpacing: Style.marginM
      columnSpacing: Style.marginM
      Layout.fillWidth: true

      Repeater {
        model: ColorSchemeService.schemes

        Rectangle {
          id: schemeItem

          property string schemePath: modelData
          property string schemeName: root.extractSchemeName(modelData)

          Layout.fillWidth: true
          Layout.alignment: Qt.AlignHCenter
          height: 50 * Style.uiScaleRatio
          radius: Style.radiusS
          color: root.getSchemeColor(schemeName, "mSurface")
          border.width: Style.borderL
          border.color: {
            if (Settings.data.colorSchemes.predefinedScheme === schemeName) {
              return Color.mSecondary;
            }
            if (itemMouseArea.containsMouse) {
              return Color.mHover;
            }
            return Color.mOutline;
          }

          RowLayout {
            id: scheme
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginS

            NText {
              text: schemeItem.schemeName
              pointSize: Style.fontSizeS
              color: Color.mOnSurface
              Layout.fillWidth: true
              elide: Text.ElideRight
              verticalAlignment: Text.AlignVCenter
              wrapMode: Text.WordWrap
              maximumLineCount: 1
            }

            property int diameter: 16 * Style.uiScaleRatio

            Rectangle {
              width: scheme.diameter
              height: scheme.diameter
              radius: scheme.diameter * 0.5
              color: root.getSchemeColor(schemeItem.schemeName, "mPrimary")
            }

            Rectangle {
              width: scheme.diameter
              height: scheme.diameter
              radius: scheme.diameter * 0.5
              color: root.getSchemeColor(schemeItem.schemeName, "mSecondary")
            }

            Rectangle {
              width: scheme.diameter
              height: scheme.diameter
              radius: scheme.diameter * 0.5
              color: root.getSchemeColor(schemeItem.schemeName, "mTertiary")
            }

            Rectangle {
              width: scheme.diameter
              height: scheme.diameter
              radius: scheme.diameter * 0.5
              color: root.getSchemeColor(schemeItem.schemeName, "mError")
            }
          }

          MouseArea {
            id: itemMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              Settings.data.colorSchemes.useWallpaperColors = false;
              Logger.i("ColorSchemeTab", "Disabled wallpaper colors");

              Settings.data.colorSchemes.predefinedScheme = schemeItem.schemeName;
              ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme);
            }
          }

          // Selection indicator
          Rectangle {
            visible: (Settings.data.colorSchemes.predefinedScheme === schemeItem.schemeName)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 0
            anchors.topMargin: -3
            width: 20
            height: 20
            radius: Math.min(Style.radiusL, width / 2)
            color: Color.mSecondary
            border.width: Style.borderS
            border.color: Color.mOnSecondary

            NIcon {
              icon: "check"
              pointSize: Style.fontSizeXS
              color: Color.mOnSecondary
              anchors.centerIn: parent
            }
          }

          Behavior on border.color {
            ColorAnimation {
              duration: Style.animationNormal
            }
          }
        }
      }
    }

    // Generate templates for predefined schemes
    NCheckbox {
      Layout.fillWidth: true
      label: I18n.tr("settings.color-scheme.predefined.generate-templates.label")
      description: I18n.tr("settings.color-scheme.predefined.generate-templates.description")
      checked: Settings.data.colorSchemes.generateTemplatesForPredefined
      onToggled: checked => {
                   Settings.data.colorSchemes.generateTemplatesForPredefined = checked;
                   if (!Settings.data.colorSchemes.useWallpaperColors && Settings.data.colorSchemes.predefinedScheme) {
                     ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme);
                   }
                 }
      Layout.topMargin: Style.marginL
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Template toggles organized by category
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginL
    visible: Settings.data.colorSchemes.useWallpaperColors || Settings.data.colorSchemes.generateTemplatesForPredefined

    NHeader {
      label: I18n.tr("settings.color-scheme.templates.section.label")
      description: I18n.tr("settings.color-scheme.templates.section.description")
    }

    // UI Components
    NCollapsible {
      Layout.fillWidth: true
      label: I18n.tr("settings.color-scheme.templates.ui.label")
      description: I18n.tr("settings.color-scheme.templates.ui.description")
      defaultExpanded: false

      NCheckbox {
        label: "GTK"
        description: I18n.tr("settings.color-scheme.templates.ui.gtk.description", {
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
        description: I18n.tr("settings.color-scheme.templates.ui.qt.description", {
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
        description: I18n.tr("settings.color-scheme.templates.ui.kcolorscheme.description", {
                               "filepath": "~/.local/share/color-schemes/noctalia.colors"
                             })
        checked: Settings.data.templates.kcolorscheme
        onToggled: checked => {
                     Settings.data.templates.kcolorscheme = checked;
                     AppThemeService.generate();
                   }
      }
    }

    // Compositors
    NCollapsible {
      Layout.fillWidth: true
      label: I18n.tr("settings.color-scheme.templates.compositors.label")
      description: I18n.tr("settings.color-scheme.templates.compositors.description")
      defaultExpanded: false

      NCheckbox {
        label: "Niri"
        description: I18n.tr("settings.color-scheme.templates.compositors.niri.description", {
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
        description: I18n.tr("settings.color-scheme.templates.compositors.hyprland.description", {
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
        description: I18n.tr("settings.color-scheme.templates.compositors.mango.description", {
                               "filepath": "~/.config/mango/noctalia.conf"
                             })
        checked: Settings.data.templates.mango
        onToggled: checked => {
                     Settings.data.templates.mango = checked;
                     AppThemeService.generate();
                   }
      }
    }

    // Terminal Emulators
    NCollapsible {
      Layout.fillWidth: true
      label: I18n.tr("settings.color-scheme.templates.terminal.label")
      description: I18n.tr("settings.color-scheme.templates.terminal.description")
      defaultExpanded: false

      NCheckbox {
        label: "Alacritty"
        description: I18n.tr("settings.color-scheme.templates.terminal.alacritty.description", {
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
        description: I18n.tr("settings.color-scheme.templates.terminal.kitty.description", {
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
        description: I18n.tr("settings.color-scheme.templates.terminal.ghostty.description", {
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
        description: I18n.tr("settings.color-scheme.templates.terminal.foot.description", {
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
        description: I18n.tr("settings.color-scheme.templates.terminal.wezterm.description", {
                               "filepath": "~/.config/wezterm/colors/Noctalia.toml"
                             })
        checked: Settings.data.templates.wezterm
        onToggled: checked => {
                     Settings.data.templates.wezterm = checked;
                     AppThemeService.generate();
                   }
      }
    }

    // Applications
    NCollapsible {
      Layout.fillWidth: true
      label: I18n.tr("settings.color-scheme.templates.programs.label")
      description: I18n.tr("settings.color-scheme.templates.programs.description")
      defaultExpanded: false

      NCheckbox {
        label: "Fuzzel"
        description: I18n.tr("settings.color-scheme.templates.programs.fuzzel.description", {
                               "filepath": "~/.config/fuzzel/themes/noctalia"
                             })
        checked: Settings.data.templates.fuzzel
        onToggled: checked => {
                     Settings.data.templates.fuzzel = checked;
                     AppThemeService.generate();
                   }
      }

      // Discord clients - single toggle with dynamic description
      NCheckbox {
        id: discordToggle
        label: "Discord"
        description: {
          if (ProgramCheckerService.availableDiscordClients.length === 0) {
            return I18n.tr("settings.color-scheme.templates.programs.discord.description-missing");
          } else {
            // Show detected clients
            var clientInfo = [];
            for (var i = 0; i < ProgramCheckerService.availableDiscordClients.length; i++) {
              var client = ProgramCheckerService.availableDiscordClients[i];
              clientInfo.push(client.name.charAt(0).toUpperCase() + client.name.slice(1));
            }
            return "Detected: " + clientInfo.join(", ");
          }
        }
        Layout.fillWidth: true
        Layout.preferredWidth: -1
        checked: Settings.data.templates.discord
        enabled: ProgramCheckerService.availableDiscordClients.length > 0
        onToggled: checked => {
                     // Set unified discord property
                     Settings.data.templates.discord = checked;
                     if (ProgramCheckerService.availableDiscordClients.length > 0) {
                       AppThemeService.generate();
                     }
                   }
      }

      NCheckbox {
        label: "Pywalfox"
        description: I18n.tr("settings.color-scheme.templates.programs.pywalfox.description", {
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
        description: I18n.tr("settings.color-scheme.templates.programs.vicinae.description", {
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
        description: I18n.tr("settings.color-scheme.templates.programs.walker.description", {
                               "filepath": "~/.config/walker/style.css"
                             })
        checked: Settings.data.templates.walker
        onToggled: checked => {
                     Settings.data.templates.walker = checked;
                     AppThemeService.generate();
                   }
      }

      // Code clients - single toggle with dynamic description
      NCheckbox {
        id: codeToggle
        label: "Code"
        description: {
          if (ProgramCheckerService.availableCodeClients.length === 0) {
            return I18n.tr("settings.color-scheme.templates.programs.code.description-missing");
          } else {
            // Show detected clients
            var clientInfo = [];
            for (var i = 0; i < ProgramCheckerService.availableCodeClients.length; i++) {
              var client = ProgramCheckerService.availableCodeClients[i];
              // Capitalize first letter and format nicely
              var clientName = client.name === "code" ? "VSCode" : "VSCodium";
              clientInfo.push(clientName);
            }
            return "Applied to default profile. Detected: " + clientInfo.join(", ");
          }
        }
        Layout.fillWidth: true
        Layout.preferredWidth: -1
        checked: Settings.data.templates.code
        enabled: ProgramCheckerService.availableCodeClients.length > 0
        onToggled: checked => {
                     // Set unified code property
                     Settings.data.templates.code = checked;
                     if (ProgramCheckerService.availableCodeClients.length > 0) {
                       if (!checked) {
                         const homeDir = Quickshell.env("HOME");
                         for (var i = 0; i < ProgramCheckerService.availableCodeClients.length; i++) {
                           var client = ProgramCheckerService.availableCodeClients[i];
                         }
                       }
                       AppThemeService.generate();
                     }
                   }
      }

      NCheckbox {
        label: "Spicetify"
        description: I18n.tr("settings.color-scheme.templates.programs.spicetify.description", {
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
        description: I18n.tr("settings.color-scheme.templates.programs.telegram.description", {
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
        description: I18n.tr("settings.color-scheme.templates.programs.cava.description", {
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
        description: I18n.tr("settings.color-scheme.templates.programs.yazi.description", {
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
        description: I18n.tr("settings.color-scheme.templates.programs.zed.description", {
                               "filepath": "~/.config/zed/themes/noctalia.json"
                             })
        checked: Settings.data.templates.zed
        onToggled: checked => {
                     Settings.data.templates.zed = checked;
                     AppThemeService.generate();
                   }
      }

      NCheckbox {
        label: "Emacs"
        description: I18n.tr("settings.color-scheme.templates.programs.emacs.description")
        checked: Settings.data.templates.emacs
        onToggled: checked => {
                     Settings.data.templates.emacs = checked;
                     AppThemeService.generate();
                   }
      }
    }

    // Miscellaneous
    NCollapsible {
      Layout.fillWidth: true
      label: I18n.tr("settings.color-scheme.templates.misc.label")
      description: I18n.tr("settings.color-scheme.templates.misc.description")
      defaultExpanded: false

      NCheckbox {
        label: I18n.tr("settings.color-scheme.templates.misc.user-templates.label")
        description: I18n.tr("settings.color-scheme.templates.misc.user-templates.description")
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

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
