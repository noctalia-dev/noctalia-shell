import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  spacing: 0

  // Helper function to get color from scheme file (supports dark/light variants)
  function getSchemeColor(schemePath, colorKey) {
    // Extract scheme name from path
    var schemeName = schemePath.split("/").pop().replace(".json", "")

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

  // Cache for scheme JSON (can be flat or {dark, light})
  property var schemeColorsCache: ({})

  // Scale properties for card animations
  property real cardScaleLow: 0.95
  property real cardScaleHigh: 1.0

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
            var schemeName = path.split("/").pop().replace(".json", "")
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

  // UI Code
  ScrollView {
    id: scrollView

    Layout.fillWidth: true
    Layout.fillHeight: true
    padding: Style.marginM * scaling
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.policy: ScrollBar.AsNeeded

    ColumnLayout {
      width: scrollView.availableWidth
      spacing: 0

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 0
      }

      ColumnLayout {
        spacing: Style.marginL * scaling
        Layout.fillWidth: true

        // Dark Mode Toggle (affects both Matugen and predefined schemes that provide variants)
        NToggle {
          label: "Dark Mode"
          description: Settings.data.colorSchemes.useWallpaperColors ? "Generate dark theme colors when using Matugen." : "Use a dark variant if available."
          checked: Settings.data.colorSchemes.darkMode
          enabled: true
          onToggled: checked => {
                       Settings.data.colorSchemes.darkMode = checked
                       if (Settings.data.colorSchemes.useWallpaperColors) {
                         ColorSchemeService.changedWallpaper()
                       } else if (Settings.data.colorSchemes.predefinedScheme) {
                         // Re-apply current scheme to pick the right variant
                         ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme)
                         // Force refresh of previews
                         var tmp = schemeColorsCache
                         schemeColorsCache = {}
                         schemeColorsCache = tmp
                       }
                     }
        }

        // App theming
        NToggle {
          label: "Theme external apps (GTK, Qt & kitty)"
          description: "Writes GTK (gtk.css), Qt5/6 (noctalia.conf) and Kitty (noctalia.conf) themes based on your colors."
          checked: Settings.data.colorSchemes.themeApps
          onToggled: checked => {
                       Settings.data.colorSchemes.themeApps = checked
                       if (Settings.data.colorSchemes.useWallpaperColors) {
                         ColorSchemeService.changedWallpaper()
                       }
                     }
        }

        // Use Matugen
        NToggle {
          label: "Enable Matugen"
          description: "Automatically generate colors based on your active wallpaper."
          checked: Settings.data.colorSchemes.useWallpaperColors
          onToggled: checked => {
                       if (checked) {
                         // Check if matugen is installed
                         matugenCheck.running = true
                       } else {
                         Settings.data.colorSchemes.useWallpaperColors = false
                         ToastService.showNotice("Matugen", "Disabled")
                       }
                     }
        }

        NDivider {
          Layout.fillWidth: true
          Layout.topMargin: Style.marginL * scaling
          Layout.bottomMargin: Style.marginL * scaling
        }

        ColumnLayout {
          spacing: Style.marginXXS * scaling
          Layout.fillWidth: true

          NText {
            text: "Predefined Color Schemes"
            font.pointSize: Style.fontSizeL * scaling
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NText {
            text: "These color schemes only apply when 'Use Matugen' is disabled. When enabled, Matugen will generate colors based on your wallpaper instead. You can toggle between light and dark themes when using Matugen."
            font.pointSize: Style.fontSizeXS * scaling
            color: Color.mOnSurface
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }
        }

        ColumnLayout {
          spacing: Style.marginXS * scaling
          Layout.fillWidth: true
          Layout.topMargin: Style.marginL * scaling

          // Color Schemes Grid
          GridLayout {
            columns: 4
            rowSpacing: Style.marginL * scaling
            columnSpacing: Style.marginL * scaling
            Layout.fillWidth: true

            Repeater {
              model: ColorSchemeService.schemes

              Rectangle {
                id: schemeCard

                property string schemePath: modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 120 * scaling
                radius: Style.radiusM * scaling
                color: getSchemeColor(modelData, "mSurface")
                border.width: Math.max(1, Style.borderL * scaling)
                border.color: Settings.data.colorSchemes.predefinedScheme === modelData ? Color.mPrimary : Color.mOutline
                scale: root.cardScaleLow

                // Mouse area for selection
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    // Disable useWallpaperColors when picking a predefined color scheme
                    Settings.data.colorSchemes.useWallpaperColors = false
                    Logger.log("ColorSchemeTab", "Disabled matugen setting")

                    Settings.data.colorSchemes.predefinedScheme = schemePath
                    ColorSchemeService.applyScheme(schemePath)
                  }
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor

                  onEntered: {
                    schemeCard.scale = root.cardScaleHigh
                  }

                  onExited: {
                    schemeCard.scale = root.cardScaleLow
                  }
                }

                // Card content
                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: Style.marginXL * scaling
                  spacing: Style.marginS * scaling

                  // Scheme name
                  NText {
                    text: {
                      // Remove json and the full path
                      var chunks = schemePath.replace(".json", "").split("/")
                      return chunks[chunks.length - 1]
                    }
                    font.pointSize: Style.fontSizeM * scaling
                    font.weight: Style.fontWeightBold
                    color: getSchemeColor(modelData, "mOnSurface")
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                  }

                  // Color swatches
                  RowLayout {
                    spacing: Style.marginS * scaling
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter

                    // Primary color swatch
                    Rectangle {
                      width: 28 * scaling
                      height: 28 * scaling
                      radius: width * 0.5
                      color: getSchemeColor(modelData, "mPrimary")
                    }

                    // Secondary color swatch
                    Rectangle {
                      width: 28 * scaling
                      height: 28 * scaling
                      radius: width * 0.5
                      color: getSchemeColor(modelData, "mSecondary")
                    }

                    // Tertiary color swatch
                    Rectangle {
                      width: 28 * scaling
                      height: 28 * scaling
                      radius: width * 0.5
                      color: getSchemeColor(modelData, "mTertiary")
                    }

                    // Error color swatch
                    Rectangle {
                      width: 28 * scaling
                      height: 28 * scaling
                      radius: width * 0.5
                      color: getSchemeColor(modelData, "mError")
                    }
                  }
                }

                // Selection indicator
                Rectangle {
                  visible: Settings.data.colorSchemes.predefinedScheme === schemePath
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.marginS * scaling
                  width: 24 * scaling
                  height: 24 * scaling
                  radius: width * 0.5
                  color: Color.mPrimary

                  NText {
                    anchors.centerIn: parent
                    text: "✓"
                    font.pointSize: Style.fontSizeXS * scaling
                    font.weight: Style.fontWeightBold
                    color: Color.mOnPrimary
                  }
                }

                // Smooth animations
                Behavior on scale {
                  NumberAnimation {
                    duration: Style.animationNormal
                    easing.type: Easing.OutCubic
                  }
                }

                Behavior on border.color {
                  ColorAnimation {
                    duration: Style.animationNormal
                  }
                }

                Behavior on border.width {
                  NumberAnimation {
                    duration: Style.animationFast
                  }
                }
              }
            }
          }
        }
      }
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
        ColorSchemeService.changedWallpaper()
        ToastService.showNotice("Matugen", "Enabled!")
      } else {
        // Matugen not found
        ToastService.showWarning("Matugen", "Not installed!")
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }
}
