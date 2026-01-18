import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "."
import qs.Commons
import qs.Services.System
import qs.Services.Theming
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var timeOptions
  property var schemeColorsCache: ({})
  property int cacheVersion: 0

  signal openDownloadPopup

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

  function getSchemeColor(schemeName, colorKey) {
    var _ = cacheVersion;

    if (schemeColorsCache[schemeName]) {
      var entry = schemeColorsCache[schemeName];
      var variant = entry;

      if (entry.dark || entry.light) {
        variant = Settings.data.colorSchemes.darkMode ? (entry.dark || entry.light) : (entry.light || entry.dark);
      }

      if (variant && variant[colorKey]) {
        return variant[colorKey];
      }
    }

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

  function schemeLoaded(schemeName, jsonData) {
    var value = jsonData || {};
    schemeColorsCache[schemeName] = value;
    cacheVersion++;
  }

  Connections {
    target: ColorSchemeService
    function onSchemesChanged() {
      root.schemeColorsCache = {};
      root.cacheVersion++;
    }
  }

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

  NToggle {
    label: I18n.tr("tooltips.switch-to-dark-mode")
    description: I18n.tr("panels.color-scheme.dark-mode-switch-description")
    checked: Settings.data.colorSchemes.darkMode
    onToggled: checked => {
                 Settings.data.colorSchemes.darkMode = checked;
                 root.cacheVersion++;
               }
  }

  NComboBox {
    label: I18n.tr("panels.color-scheme.dark-mode-mode-label")
    description: I18n.tr("panels.color-scheme.dark-mode-mode-description")

    model: [
      {
        "name": I18n.tr("panels.color-scheme.dark-mode-mode-off"),
        "key": "off"
      },
      {
        "name": I18n.tr("panels.color-scheme.dark-mode-mode-manual"),
        "key": "manual"
      },
      {
        "name": I18n.tr("common.location"),
        "key": "location"
      }
    ]

    currentKey: Settings.data.colorSchemes.schedulingMode

    onSelected: key => {
                  Settings.data.colorSchemes.schedulingMode = key;
                  AppThemeService.generate();
                }
  }

  ColumnLayout {
    spacing: Style.marginS
    visible: Settings.data.colorSchemes.schedulingMode === "manual"

    NLabel {
      label: I18n.tr("panels.display.night-light-manual-schedule-label")
      description: I18n.tr("panels.display.night-light-manual-schedule-description")
    }

    RowLayout {
      Layout.fillWidth: false
      spacing: Style.marginS

      NText {
        text: I18n.tr("panels.display.night-light-manual-schedule-sunrise")
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
      }

      NComboBox {
        model: root.timeOptions
        currentKey: Settings.data.colorSchemes.manualSunrise
        placeholder: I18n.tr("panels.display.night-light-manual-schedule-select-start")
        onSelected: key => Settings.data.colorSchemes.manualSunrise = key
        minimumWidth: 120
      }

      Item {
        Layout.preferredWidth: 20
      }

      NText {
        text: I18n.tr("panels.display.night-light-manual-schedule-sunset")
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
      }

      NComboBox {
        model: root.timeOptions
        currentKey: Settings.data.colorSchemes.manualSunset
        placeholder: I18n.tr("panels.display.night-light-manual-schedule-select-stop")
        onSelected: key => Settings.data.colorSchemes.manualSunset = key
        minimumWidth: 120
      }
    }
  }

  NToggle {
    label: I18n.tr("panels.color-scheme.color-source-use-wallpaper-colors-label")
    description: I18n.tr("panels.color-scheme.color-source-use-wallpaper-colors-description")
    checked: Settings.data.colorSchemes.useWallpaperColors
    onToggled: checked => {
                 Settings.data.colorSchemes.useWallpaperColors = checked;
                 if (checked) {
                   AppThemeService.generate();
                 } else {
                   ToastService.showNotice(I18n.tr("toast.wallpaper-colors.label"), I18n.tr("toast.wallpaper-colors.disabled"), "settings-color-scheme");
                   if (Settings.data.colorSchemes.predefinedScheme) {
                     ColorSchemeService.applyScheme(Settings.data.colorSchemes.predefinedScheme);
                   }
                 }
               }
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.color-scheme.wallpaper-method-label")
    description: I18n.tr("panels.color-scheme.wallpaper-method-description")
    enabled: Settings.data.colorSchemes.useWallpaperColors
    visible: Settings.data.colorSchemes.useWallpaperColors
    model: [
      {
        "key": "default",
        "name": I18n.tr("common.default")
      },
      {
        "key": "material",
        "name": "Material Design" // Do not translate
      }
    ]
    currentKey: Settings.data.colorSchemes.extractionMethod
    onSelected: key => {
                  Settings.data.colorSchemes.extractionMethod = key;
                  AppThemeService.generate();
                }
  }

  NDivider {
    Layout.fillWidth: true
    visible: !Settings.data.colorSchemes.useWallpaperColors
  }

  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true
    visible: !Settings.data.colorSchemes.useWallpaperColors

    NHeader {
      label: I18n.tr("panels.color-scheme.predefined-title")
      description: I18n.tr("panels.color-scheme.predefined-desc")
      Layout.fillWidth: true
    }

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

    NButton {
      text: I18n.tr("panels.color-scheme.download-button")
      icon: "download"
      onClicked: root.openDownloadPopup()
      Layout.alignment: Qt.AlignRight
      Layout.topMargin: Style.marginS
    }
  }
}
