import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
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
        var hh = ("0" + h).slice(-2)
        var mm = ("0" + m).slice(-2)
        var key = hh + ":" + mm
        timeOptions.append({
                             "key": key,
                             "name": key
                           })
      }
    }
  }

  spacing: Style.marginL

  // Helper function to extract scheme name from path
  function extractSchemeName(schemePath) {
    var pathParts = schemePath.split("/")
    var filename = pathParts[pathParts.length - 1]
    var schemeName = filename.replace(".json", "")

    if (schemeName === "Noctalia-default") {
      schemeName = "Noctalia (default)"
    } else if (schemeName === "Noctalia-legacy") {
      schemeName = "Noctalia (legacy)"
    } else if (schemeName === "Tokyo-Night") {
      schemeName = "Tokyo Night"
    }

    return schemeName
  }

  // Helper function to get color from scheme file (supports dark/light variants)
  function getSchemeColor(schemeName, colorKey) {
    // Access cache version to create dependency
    var _ = cacheVersion

    if (schemeColorsCache[schemeName]) {
      var entry = schemeColorsCache[schemeName]
      var variant = entry

      // Check if scheme has dark/light variants
      if (entry.dark || entry.light) {
        variant = Settings.data.colorSchemes.darkMode ? (entry.dark || entry.light) : (entry.light || entry.dark)
      }

      if (variant && variant[colorKey]) {
        return variant[colorKey]
      }
    }

    // Return visible defaults while loading
    if (colorKey === "mSurface")
      return Color.mSurfaceVariant
    if (colorKey === "mPrimary")
      return Color.mPrimary
    if (colorKey === "mSecondary")
      return Color.mSecondary
    if (colorKey === "mTertiary")
      return Color.mTertiary
    if (colorKey === "mError")
      return Color.mError
    return Color.mOnSurfaceVariant
  }

  // This function is called by the FileView Repeater when a scheme file is loaded
  function schemeLoaded(schemeName, jsonData) {
    var value = jsonData || {}
    schemeColorsCache[schemeName] = value
    // Force UI update by incrementing cache version
    cacheVersion++
  }

  // When the list of available schemes changes, clear the cache
  Connections {
    target: ColorSchemeService
    function onSchemesChanged() {
      schemeColorsCache = {}
      cacheVersion++
    }
  }

  // Simple process to check if matugen exists
  Process {
    id: matugenCheck
    command: ["which", "matugen"]
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        Settings.data.colorSchemes.useWallpaperColors = true
        AppThemeService.generate()
        ToastService.showNotice(I18n.tr("settings.color-scheme.color-source.use-wallpaper-colors.label"), I18n.tr("toast.wallpaper-colors.enabled"))
      } else {
        ToastService.showWarning(I18n.tr("settings.color-scheme.color-source.use-wallpaper-colors.label"), I18n.tr("toast.wallpaper-colors.not-installed"))
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // A non-visual Item to host the Repeater that loads the color scheme files
  Item {
    visible: false
    id: fileLoaders

    Repeater {
      model: ColorSchemeService.schemes

      delegate: Item {
        FileView {
          path: modelData
          blockLoading: false
          onLoaded: {
            var schemeName = root.extractSchemeName(path)

            try {
              var jsonData = JSON.parse(text())
              root.schemeLoaded(schemeName, jsonData)
            } catch (e) {
              Logger.w("ColorSchemeTab", "Failed to parse JSON for scheme:", schemeName, e)
              root.schemeLoaded(schemeName, null)
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
                 Settings.data.colorSchemes.darkMode = checked
                 root.cacheVersion++ // Force UI update for dark/light variants
               }
  }

  NComboBox {
    label: I18n.tr("settings.color-scheme.dark-mode.mode.label")
    description: I18n.tr("settings.color-scheme.dark-mode.mode.description")

    model: [{
        "name": I18n.tr("settings.color-scheme.dark-mode.mode.off"),
        "key": "off"
      }, {
        "name": I18n.tr("settings.color-scheme.dark-mode.mode.manual"),
        "key": "manual"
      }, {
        "name": I18n.tr("settings.color-scheme.dark-mode.mode.location"),
        "key": "location"
      }]

    currentKey: Settings.data.colorSchemes.schedulingMode

    onSelected: key => {
                  Settings.data.colorSchemes.schedulingMode = key
                  AppThemeService.generate()
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
                   matugenCheck.running = true
                 } else {
                   Settings.data.colorSchemes.useWallpaperColors = false
                   ToastService.showNotice(I18n.tr("settings.color-scheme.color-source.use-wallpaper-colors.label"), I18n.tr("toast.wallpaper-colors.disabled"))

                   if (Settings.data.colorSchemes.predefinedScheme) {
                     ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme)
                   }
                 }
               }
  }

  // Matugen Scheme Type Selection [Descriptions sourced from DankMaterialShell]
  NComboBox {
    label: I18n.tr("settings.color-scheme.color-source.matugen-scheme-type.label")
    description: I18n.tr("settings.color-scheme.color-source.matugen-scheme-type.description." + Settings.data.colorSchemes.matugenSchemeType)
    enabled: Settings.data.colorSchemes.useWallpaperColors
    opacity: Settings.data.colorSchemes.useWallpaperColors ? 1.0 : 0.6
    visible: Settings.data.colorSchemes.useWallpaperColors

    model: [{
        "key": "scheme-content",
        "name": "Content"
      }, {
        "key": "scheme-expressive",
        "name": "Expressive"
      }, {
        "key": "scheme-fidelity",
        "name": "Fidelity"
      }, {
        "key": "scheme-fruit-salad",
        "name": "Fruit Salad"
      }, {
        "key": "scheme-monochrome",
        "name": "Monochrome"
      }, {
        "key": "scheme-neutral",
        "name": "Neutral"
      }, {
        "key": "scheme-rainbow",
        "name": "Rainbow"
      }, {
        "key": "scheme-tonal-spot",
        "name": "Tonal Spot"
      }]

    currentKey: Settings.data.colorSchemes.matugenSchemeType

    onSelected: key => {
                  Settings.data.colorSchemes.matugenSchemeType = key
                  AppThemeService.generate()
                }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
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
              return Color.mSecondary
            }
            if (itemMouseArea.containsMouse) {
              return Color.mTertiary
            }
            return Color.mOutline
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
              Settings.data.colorSchemes.useWallpaperColors = false
              Logger.i("ColorSchemeTab", "Disabled wallpaper colors")

              Settings.data.colorSchemes.predefinedScheme = schemeItem.schemeName
              ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme)
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
            radius: width * 0.5
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
                   Settings.data.colorSchemes.generateTemplatesForPredefined = checked
                   if (!Settings.data.colorSchemes.useWallpaperColors && Settings.data.colorSchemes.predefinedScheme) {
                     ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme)
                   }
                 }
      Layout.topMargin: Style.marginL
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }

  // Template toggles organized by category
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginL

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
                     Settings.data.templates.gtk = checked
                     AppThemeService.generate()
                   }
      }

      NCheckbox {
        label: "Qt"
        description: I18n.tr("settings.color-scheme.templates.ui.qt.description", {
                               "filepath": "~/.config/qt5ct/colors/noctalia.conf & ~/.config/qt6ct/colors/noctalia.conf"
                             })
        checked: Settings.data.templates.qt
        onToggled: checked => {
                     Settings.data.templates.qt = checked
                     AppThemeService.generate()
                   }
      }

      NCheckbox {
        label: "KColorScheme"
        description: I18n.tr("settings.color-scheme.templates.ui.kcolorscheme.description", {
                               "filepath": "~/.local/share/color-schemes/noctalia.colors"
                             })
        checked: Settings.data.templates.kcolorscheme
        onToggled: checked => {
                     Settings.data.templates.kcolorscheme = checked
                     AppThemeService.generate()
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
        label: "Kitty"
        description: ProgramCheckerService.kittyAvailable ? I18n.tr("settings.color-scheme.templates.terminal.kitty.description", {
                                                                      "filepath": "~/.config/kitty/themes/noctalia.conf"
                                                                    }) : I18n.tr("settings.color-scheme.templates.terminal.kitty.description-missing", {
                                                                                   "app": "kitty"
                                                                                 })
        checked: Settings.data.templates.kitty
        enabled: ProgramCheckerService.kittyAvailable
        opacity: ProgramCheckerService.kittyAvailable ? 1.0 : 0.6
        onToggled: checked => {
                     if (ProgramCheckerService.kittyAvailable) {
                       Settings.data.templates.kitty = checked
                       AppThemeService.generate()
                     }
                   }
      }

      NCheckbox {
        label: "Ghostty"
        description: ProgramCheckerService.ghosttyAvailable ? I18n.tr("settings.color-scheme.templates.terminal.ghostty.description", {
                                                                        "filepath": "~/.config/ghostty/themes/noctalia"
                                                                      }) : I18n.tr("settings.color-scheme.templates.terminal.ghostty.description-missing", {
                                                                                     "app": "ghostty"
                                                                                   })
        checked: Settings.data.templates.ghostty
        enabled: ProgramCheckerService.ghosttyAvailable
        opacity: ProgramCheckerService.ghosttyAvailable ? 1.0 : 0.6
        onToggled: checked => {
                     if (ProgramCheckerService.ghosttyAvailable) {
                       Settings.data.templates.ghostty = checked
                       AppThemeService.generate()
                     }
                   }
      }

      NCheckbox {
        label: "Foot"
        description: ProgramCheckerService.footAvailable ? I18n.tr("settings.color-scheme.templates.terminal.foot.description", {
                                                                     "filepath": "~/.config/foot/themes/noctalia"
                                                                   }) : I18n.tr("settings.color-scheme.templates.terminal.foot.description-missing", {
                                                                                  "app": "foot"
                                                                                })
        checked: Settings.data.templates.foot
        enabled: ProgramCheckerService.footAvailable
        opacity: ProgramCheckerService.footAvailable ? 1.0 : 0.6
        onToggled: checked => {
                     if (ProgramCheckerService.footAvailable) {
                       Settings.data.templates.foot = checked
                       AppThemeService.generate()
                     }
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
        description: ProgramCheckerService.fuzzelAvailable ? I18n.tr("settings.color-scheme.templates.programs.fuzzel.description", {
                                                                       "filepath": "~/.config/fuzzel/themes/noctalia"
                                                                     }) : I18n.tr("settings.color-scheme.templates.programs.fuzzel.description-missing", {
                                                                                    "app": "fuzzel"
                                                                                  })
        checked: Settings.data.templates.fuzzel
        enabled: ProgramCheckerService.fuzzelAvailable
        opacity: ProgramCheckerService.fuzzelAvailable ? 1.0 : 0.6
        onToggled: checked => {
                     if (ProgramCheckerService.fuzzelAvailable) {
                       Settings.data.templates.fuzzel = checked
                       AppThemeService.generate()
                     }
                   }
      }

      // Discord clients - single toggle with dynamic description
      NCheckbox {
        id: discordToggle
        label: "Discord"
        description: {
          if (ProgramCheckerService.availableDiscordClients.length === 0) {
            return I18n.tr("settings.color-scheme.templates.programs.discord.description-missing")
          } else {
            // Show detected clients
            var clientInfo = []
            for (var i = 0; i < ProgramCheckerService.availableDiscordClients.length; i++) {
              var client = ProgramCheckerService.availableDiscordClients[i]
              clientInfo.push(client.name.charAt(0).toUpperCase() + client.name.slice(1))
            }
            return "Detected: " + clientInfo.join(", ")
          }
        }
        Layout.fillWidth: true
        Layout.preferredWidth: -1
        checked: {
          // Check if any Discord client template is enabled
          var anyEnabled = false
          for (var i = 0; i < ProgramCheckerService.availableDiscordClients.length; i++) {
            var client = ProgramCheckerService.availableDiscordClients[i]
            if (Settings.data.templates["discord_" + client.name]) {
              anyEnabled = true
              break
            }
          }
          return anyEnabled
        }
        enabled: ProgramCheckerService.availableDiscordClients.length > 0
        opacity: ProgramCheckerService.availableDiscordClients.length > 0 ? 1.0 : 0.6
        onToggled: checked => {
                     // Enable/disable all detected Discord clients
                     for (var i = 0; i < ProgramCheckerService.availableDiscordClients.length; i++) {
                       var client = ProgramCheckerService.availableDiscordClients[i]
                       Settings.data.templates["discord_" + client.name] = checked
                     }
                     if (ProgramCheckerService.availableDiscordClients.length > 0) {
                       AppThemeService.generate()
                     }
                   }
      }

      NCheckbox {
        label: "Pywalfox"
        description: ProgramCheckerService.pywalfoxAvailable ? I18n.tr("settings.color-scheme.templates.programs.pywalfox.description", {
                                                                         "filepath": "~/.cache/wal/colors.json"
                                                                       }) : I18n.tr("settings.color-scheme.templates.programs.pywalfox.description-missing", {
                                                                                      "app": "pywalfox"
                                                                                    })
        checked: Settings.data.templates.pywalfox
        enabled: ProgramCheckerService.pywalfoxAvailable
        opacity: ProgramCheckerService.pywalfoxAvailable ? 1.0 : 0.6
        onToggled: checked => {
                     if (ProgramCheckerService.pywalfoxAvailable) {
                       Settings.data.templates.pywalfox = checked
                       AppThemeService.generate()
                     }
                   }
      }
      NCheckbox {
        label: "Vicinae"
        description: ProgramCheckerService.vicinaeAvailable ? I18n.tr("settings.color-scheme.templates.programs.vicinae.description", {
                                                                        "filepath": "~/.local/share/vicinae/themes/matugen.toml"
                                                                      }) : I18n.tr("settings.color-scheme.templates.programs.vicinae.description-missing", {
                                                                                     "app": "vicinae"
                                                                                   })
        checked: Settings.data.templates.vicinae
        enabled: ProgramCheckerService.vicinaeAvailable
        opacity: ProgramCheckerService.vicinaeAvailable ? 1.0 : 0.6
        onToggled: checked => {
                     if (ProgramCheckerService.vicinaeAvailable) {
                       Settings.data.templates.vicinae = checked
                       AppThemeService.generate()
                     }
                   }
      }
      NCheckbox {
        label: "Walker"
        description: ProgramCheckerService.walkerAvailable ? I18n.tr("settings.color-scheme.templates.programs.walker.description", {
                                                                       "filepath": "~/.config/walker/style.css"
                                                                     }) : I18n.tr("settings.color-scheme.templates.programs.walker.description-missing", {
                                                                                    "app": "walker"
                                                                                  })
        checked: Settings.data.templates.walker
        enabled: ProgramCheckerService.walkerAvailable
        opacity: ProgramCheckerService.walkerAvailable ? 1.0 : 0.6
        onToggled: checked => {
                     if (ProgramCheckerService.walkerAvailable) {
                       Settings.data.templates.walker = checked
                       AppThemeService.generate()
                     }
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
                     Settings.data.templates.enableUserTemplates = checked
                     if (checked) {
                       MatugenTemplates.writeUserTemplatesToml()
                     }
                     AppThemeService.generate()
                   }
      }
    }
  }
}
