import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  // Cache for scheme JSON (can be flat or {dark, light})
  property var schemeColorsCache: ({})

  spacing: Style.marginL * scaling

  // Helper function to extract scheme name from path
  function extractSchemeName(schemePath) {
    var pathParts = schemePath.split("/")
    var filename = pathParts[pathParts.length - 1] // Get filename
    var schemeName = filename.replace(".json", "") // Remove .json extension

    // Convert folder names back to display names
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
  function getSchemeColor(schemePath, colorKey) {
    // Extract scheme name from path
    var schemeName = extractSchemeName(schemePath)

    // Try to get from cached data first
    if (schemeColorsCache[schemeName]) {
      var entry = schemeColorsCache[schemeName]
      var variant = entry
      if (entry.dark || entry.light) {
        variant = Settings.data.colorSchemes.darkMode ? (entry.dark || entry.light) : (entry.light || entry.dark)
      }
      if (variant && variant[colorKey])
        return variant[colorKey]
    }

    // Return a default color if not cached yet
    return "#000000"
  }

  // This function is called by the FileView Repeater when a scheme file is loaded
  function schemeLoaded(schemeName, jsonData) {
    var value = jsonData || {}
    var newCache = schemeColorsCache
    newCache[schemeName] = value
    schemeColorsCache = newCache
  }

  // When the list of available schemes changes, clear the cache.
  // The Repeater below will automatically re-create the FileViews.
  Connections {
    target: ColorSchemeService
    function onSchemesChanged() {
      schemeColorsCache = {}
    }
  }

  // Simple process to check if matugen exists
  Process {
    id: matugenCheck
    command: ["which", "matugen"]
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        // Matugen exists, enable it
        Settings.data.colorSchemes.useWallpaperColors = true
        AppThemeService.generate()
        ToastService.showNotice(I18n.tr("settings.color-scheme.color-source.use-wallpaper-colors.label"), I18n.tr("toast.wallpaper-colors.enabled"))
      } else {
        // Matugen not found
        ToastService.showWarning(I18n.tr("settings.color-scheme.color-source.use-wallpaper-colors.label"), I18n.tr("toast.wallpaper-colors.not-installed"))
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // A non-visual Item to host the Repeater that loads the color scheme files.
  Item {
    visible: false
    id: fileLoaders

    Repeater {
      model: ColorSchemeService.schemes

      // The delegate is a Component, which correctly wraps the non-visual FileView
      delegate: Item {
        FileView {
          path: modelData
          blockLoading: true
          onLoaded: {
            // Extract scheme name from path
            var schemeName = extractSchemeName(path)

            try {
              var jsonData = JSON.parse(text())
              root.schemeLoaded(schemeName, jsonData)
            } catch (e) {
              Logger.warn("ColorSchemeTab", "Failed to parse JSON for scheme:", schemeName, e)
              root.schemeLoaded(schemeName, null) // Load defaults on parse error
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

  // Dark Mode Toggle (affects both Matugen and predefined schemes that provide variants)
  NToggle {
    label: I18n.tr("settings.color-scheme.color-source.dark-mode.label")
    description: I18n.tr("settings.color-scheme.color-source.dark-mode.description")
    checked: Settings.data.colorSchemes.darkMode
    enabled: true
    onToggled: checked => Settings.data.colorSchemes.darkMode = checked
  }

  // Use Wallpaper Colors
  NToggle {
    label: I18n.tr("settings.color-scheme.color-source.use-wallpaper-colors.label")
    description: I18n.tr("settings.color-scheme.color-source.use-wallpaper-colors.description")
    checked: Settings.data.colorSchemes.useWallpaperColors
    onToggled: checked => {
                 if (checked) {
                   // Check if matugen is installed
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

  // Matugen Scheme Type Selection
  NComboBox {
    label: I18n.tr("settings.color-scheme.color-source.matugen-scheme-type.label")
    description: I18n.tr("settings.color-scheme.color-source.matugen-scheme-type.description")
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
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
    visible: !Settings.data.colorSchemes.useWallpaperColors
  }

  // Predefined Color Schemes
  ColumnLayout {
    spacing: Style.marginM * scaling
    Layout.fillWidth: true
    visible: !Settings.data.colorSchemes.useWallpaperColors

    NHeader {
      label: I18n.tr("settings.color-scheme.predefined.section.label")
      description: I18n.tr("settings.color-scheme.predefined.section.description")
    }

    // Color Schemes Grid
    GridLayout {
      columns: 3
      rowSpacing: Style.marginM * scaling
      columnSpacing: Style.marginM * scaling
      Layout.fillWidth: true

      Repeater {
        model: ColorSchemeService.schemes

        Rectangle {
          id: schemeItem

          property string schemePath: modelData

          Layout.fillWidth: true
          Layout.alignment: Qt.AlignHCenter
          height: 50 * scaling
          radius: Style.radiusS * scaling
          color: getSchemeColor(modelData, "mSurface")
          border.width: Math.max(1, Style.borderL * scaling)
          border.color: {
            if (Settings.data.colorSchemes.predefinedScheme === extractSchemeName(modelData)) {
              return Color.mSecondary
            }
            if (itemMouseArea.containsMouse) {
              return Color.mTertiary
            }
            return Color.mOutline
          }

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM * scaling
            spacing: Style.marginXS * scaling

            NText {
              text: extractSchemeName(schemePath)
              pointSize: Style.fontSizeS * scaling
              font.weight: Style.fontWeightMedium
              color: Color.mOnSurface
              Layout.fillWidth: true
              // Layout.maximumWidth: 150 * scaling
              elide: Text.ElideRight
              verticalAlignment: Text.AlignVCenter
              wrapMode: Text.WordWrap
              maximumLineCount: 1
            }

            Rectangle {
              width: 14 * scaling
              height: 14 * scaling
              radius: width * 0.5
              color: getSchemeColor(modelData, "mPrimary")
            }

            Rectangle {
              width: 14 * scaling
              height: 14 * scaling
              radius: width * 0.5
              color: getSchemeColor(modelData, "mSecondary")
            }

            Rectangle {
              width: 14 * scaling
              height: 14 * scaling
              radius: width * 0.5
              color: getSchemeColor(modelData, "mTertiary")
            }

            Rectangle {
              width: 14 * scaling
              height: 14 * scaling
              radius: width * 0.5
              color: getSchemeColor(modelData, "mError")
            }
          }

          MouseArea {
            id: itemMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              Settings.data.colorSchemes.useWallpaperColors = false
              Logger.log("ColorSchemeTab", "Disabled wallpaper colors")

              Settings.data.colorSchemes.predefinedScheme = extractSchemeName(schemePath)
              ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme)
            }
          }

          // Selection indicator
          Rectangle {
            visible: (Settings.data.colorSchemes.predefinedScheme === extractSchemeName(schemePath))
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -3 * scaling
            anchors.topMargin: -3 * scaling
            width: 20 * scaling
            height: 20 * scaling
            radius: width * 0.5
            color: Color.mSecondary
            border.width: Math.max(1, Style.borderS * scaling)
            border.color: Color.mOnSecondary

            NIcon {
              icon: "check"
              pointSize: Style.fontSizeXS * scaling
              font.weight: Style.fontWeightBold
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
                   // Re-generate templates if a predefined scheme is currently active
                   if (!Settings.data.colorSchemes.useWallpaperColors && Settings.data.colorSchemes.predefinedScheme) {
                     ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme)
                   }
                 }
      Layout.topMargin: Style.marginL * scaling
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Template toggles organized by category
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginL * scaling

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

      NCheckbox {
        label: "Vesktop"
        description: ProgramCheckerService.vesktopAvailable ? I18n.tr("settings.color-scheme.templates.programs.vesktop.description", {
                                                                        "filepath": "~/.config/vesktop/themes/noctalia.theme.css"
                                                                      }) : I18n.tr("settings.color-scheme.templates.programs.vesktop.description-missing", {
                                                                                     "app": "vesktop"
                                                                                   })
        checked: Settings.data.templates.vesktop
        enabled: ProgramCheckerService.vesktopAvailable
        opacity: ProgramCheckerService.vesktopAvailable ? 1.0 : 0.6
        onToggled: checked => {
                     if (ProgramCheckerService.vesktopAvailable) {
                       Settings.data.templates.vesktop = checked
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
                     AppThemeService.generate()
                   }
      }
    }
  }
}
