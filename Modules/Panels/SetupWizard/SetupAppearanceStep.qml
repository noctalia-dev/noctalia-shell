import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Services.System
import qs.Services.Theming
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  function extractSchemeName(path) {
    var basename = path.split('/').pop();
    return basename.replace('.json', '');
  }

  // Cache for scheme colors (mirrors ColorSchemeTab approach)
  property var schemeColorsCache: ({})
  property int cacheVersion: 0

  function getSchemeColor(schemeName, key) {
    try {
      var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
      var data = schemeColorsCache[schemeName];
      if (data && data[mode] && data[mode][key])
        return data[mode][key];
    } catch (e) {}
    return Color.mSurfaceVariant;
  }

  // Match ColorSchemeTab helpers
  function schemeLoaded(schemeName, jsonData) {
    var value = jsonData || {};
    schemeColorsCache[schemeName] = value;
    cacheVersion++;
    Logger.i("SetupAppearanceStep", `Loaded scheme ${schemeName}`);
  }

  Connections {
    target: ColorSchemeService
    function onSchemesChanged() {
      Logger.i("SetupAppearanceStep", `Color schemes changed: ${ColorSchemeService.schemes.length}`);
      schemeColorsCache = {};
      cacheVersion++;
    }
  }

  // Beautiful header with icon
  RowLayout {
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginL
    spacing: Style.marginM

    Rectangle {
      width: 40
      height: 40
      radius: Style.radiusL
      color: Color.mSurfaceVariant
      opacity: 0.6

      NIcon {
        icon: "palette"
        pointSize: Style.fontSizeL
        color: Color.mPrimary
        anchors.centerIn: parent
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: I18n.tr("common.appearance")
        pointSize: Style.fontSizeXL
        font.weight: Style.fontWeightBold
        color: Color.mPrimary
      }

      NText {
        text: I18n.tr("setup.appearance.subheader")
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
      }
    }
  }

  ScrollView {
    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true
    contentWidth: availableWidth
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.policy: ScrollBar.AsNeeded

    ColumnLayout {
      width: parent.width
      spacing: Style.marginM

      // Dark Mode Toggle
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        Rectangle {
          width: 28
          height: 28
          radius: Style.radiusM
          color: Color.mSurface

          NIcon {
            icon: "moon"
            pointSize: Style.fontSizeL
            color: Color.mPrimary
            anchors.centerIn: parent
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          NText {
            text: I18n.tr("tooltips.switch-to-dark-mode")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
          }

          NText {
            text: I18n.tr("panels.color-scheme.dark-mode-switch-description")
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }

        NToggle {
          checked: Settings.data.colorSchemes.darkMode
          onToggled: checked => Settings.data.colorSchemes.darkMode = checked
        }
      }

      // Divider
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.2
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
      }

      // Wallpaper Colors Toggle
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        Rectangle {
          width: 28
          height: 28
          radius: Style.radiusM
          color: Color.mSurface

          NIcon {
            icon: ProgramCheckerService.matugenAvailable ? "color-picker" : "alert-triangle"
            pointSize: Style.fontSizeL
            color: Color.mPrimary
            anchors.centerIn: parent
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          NText {
            text: I18n.tr("panels.color-scheme.color-source-use-wallpaper-colors-label")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
          }

          NText {
            text: I18n.tr("panels.color-scheme.color-source-use-wallpaper-colors-description")
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }

        NToggle {
          enabled: ProgramCheckerService.matugenAvailable
          checked: Settings.data.colorSchemes.useWallpaperColors && ProgramCheckerService.matugenAvailable
          onToggled: checked => {
                       if (!ProgramCheckerService.matugenAvailable)
                       return;
                       if (checked) {
                         Settings.data.colorSchemes.useWallpaperColors = true;
                         AppThemeService.generate();
                       } else {
                         Settings.data.colorSchemes.useWallpaperColors = false;
                         if (Settings.data.colorSchemes.predefinedScheme) {
                           ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme);
                         }
                       }
                     }
        }
      }

      // Matugen scheme type (visible when wallpaper colors enabled and matugen available)
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        visible: Settings.data.colorSchemes.useWallpaperColors && ProgramCheckerService.matugenAvailable

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          Rectangle {
            width: 28
            height: 28
            radius: Style.radiusM
            color: Color.mSurface

            NIcon {
              icon: "wand"
              pointSize: Style.fontSizeL
              color: Color.mPrimary
              anchors.centerIn: parent
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            NText {
              text: I18n.tr("panels.color-scheme.color-source-matugen-scheme-type-label")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
            }

            NText {
              text: I18n.tr("panels.color-scheme.color-source-matugen-scheme-type-description")
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
          }
        }

        // Matugen scheme options styled like bar position buttons
        GridLayout {
          Layout.fillWidth: true
          columns: 2
          rowSpacing: Style.marginS
          columnSpacing: Style.marginS

          Repeater {
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
            delegate: Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 48
              radius: Style.radiusM
              border.width: Style.borderS

              property bool isActive: Settings.data.colorSchemes.matugenSchemeType === modelData.key

              color: (hoverHandler.hovered || isActive) ? Color.mPrimary : Color.mSurfaceVariant
              border.color: (hoverHandler.hovered || isActive) ? Color.mPrimary : Color.mOutline
              opacity: (hoverHandler.hovered || isActive) ? 1.0 : 0.8

              NText {
                text: modelData.name
                pointSize: Style.fontSizeM
                font.weight: (hoverHandler.hovered || parent.isActive) ? Style.fontWeightBold : Style.fontWeightMedium
                color: (hoverHandler.hovered || parent.isActive) ? Color.mOnPrimary : Color.mOnSurface
                anchors.centerIn: parent
              }

              HoverHandler {
                id: hoverHandler
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Settings.data.colorSchemes.matugenSchemeType = modelData.key;
                  AppThemeService.generate();
                }
              }

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
              Behavior on border.color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
            }
          }
        }
      }

      // Divider
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.2
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
        visible: !Settings.data.colorSchemes.useWallpaperColors
      }

      // Predefined schemes section (visible when wallpaper colors disabled)
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        visible: !Settings.data.colorSchemes.useWallpaperColors

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          Rectangle {
            width: 28
            height: 28
            radius: Style.radiusM
            color: Color.mSurface

            NIcon {
              icon: "palette"
              pointSize: Style.fontSizeL
              color: Color.mPrimary
              anchors.centerIn: parent
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            NText {
              text: I18n.tr("panels.color-scheme.predefined-title")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
            }

            NText {
              text: I18n.tr("panels.color-scheme.predefined-desc")
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
          }
        }

        // Predefined schemes Grid (matches ColorSchemeTab)
        GridLayout {
          id: schemesGrid
          columns: Math.max(2, Math.floor((parent.width - Style.marginM * 2) / 180))
          rowSpacing: Style.marginM
          columnSpacing: Style.marginM
          Layout.fillWidth: true

          Repeater {
            model: ColorSchemeService.schemes

            delegate: Rectangle {
              id: schemeItem

              property string schemePath: modelData
              property string schemeName: root.extractSchemeName(modelData)

              Layout.fillWidth: true
              Layout.alignment: Qt.AlignHCenter
              height: 50
              radius: Style.radiusS
              color: root.cacheVersion >= 0 ? root.getSchemeColor(schemeName, "mSurface") : root.getSchemeColor(schemeName, "mSurface")
              border.width: Style.borderL
              border.color: itemMouseArea.containsMouse ? Color.mHover : (Settings.data.colorSchemes.predefinedScheme === schemeName ? Color.mSecondary : Color.mOutline)

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.marginL
                spacing: Style.marginXS

                NText {
                  text: schemeItem.schemeName
                  pointSize: Style.fontSizeS
                  font.weight: Style.fontWeightMedium
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                  wrapMode: Text.WordWrap
                  maximumLineCount: 1
                }

                Rectangle {
                  width: 14
                  height: 14
                  radius: width * 0.5
                  color: root.cacheVersion >= 0 ? (function () {
                    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
                    var cached = root.schemeColorsCache[schemeItem.schemeName];
                    return (cached && cached[mode] && cached[mode].mPrimary) || root.getSchemeColor(schemeItem.schemeName, "mPrimary");
                  })() : Color.mPrimary
                }
                Rectangle {
                  width: 14
                  height: 14
                  radius: width * 0.5
                  color: root.cacheVersion >= 0 ? (function () {
                    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
                    var cached = root.schemeColorsCache[schemeItem.schemeName];
                    return (cached && cached[mode] && cached[mode].mSecondary) || root.getSchemeColor(schemeItem.schemeName, "mSecondary");
                  })() : Color.mSecondary
                }
                Rectangle {
                  width: 14
                  height: 14
                  radius: width * 0.5
                  color: root.cacheVersion >= 0 ? (function () {
                    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
                    var cached = root.schemeColorsCache[schemeItem.schemeName];
                    return (cached && cached[mode] && cached[mode].mTertiary) || root.getSchemeColor(schemeItem.schemeName, "mTertiary");
                  })() : Color.mTertiary
                }
                Rectangle {
                  width: 14
                  height: 14
                  radius: width * 0.5
                  color: root.cacheVersion >= 0 ? (function () {
                    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";
                    var cached = root.schemeColorsCache[schemeItem.schemeName];
                    return (cached && cached[mode] && cached[mode].mError) || root.getSchemeColor(schemeItem.schemeName, "mError");
                  })() : Color.mError
                }
              }

              MouseArea {
                id: itemMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Settings.data.colorSchemes.useWallpaperColors = false;
                  Settings.data.colorSchemes.predefinedScheme = schemeItem.schemeName;
                  ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme);
                }
              }
            }
          }
        }
      }

      // Bottom spacer
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.marginL
      }
    }
  }

  // Hidden loader to populate schemeColorsCache from files
  Item {
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
              root.schemeLoaded(schemeName, null);
            }
          }
        }
      }
    }
  }
}
