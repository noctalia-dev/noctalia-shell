import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  property var screen
  property string specificFolderMonitorName: ""

  spacing: Style.marginL

  NHeader {
    label: I18n.tr("settings.wallpaper.settings.section.label")
    description: I18n.tr("settings.wallpaper.settings.section.description")
  }

  NToggle {
    label: I18n.tr("settings.wallpaper.settings.enable-management.label")
    description: I18n.tr("settings.wallpaper.settings.enable-management.description")
    checked: Settings.data.wallpaper.enabled
    onToggled: checked => Settings.data.wallpaper.enabled = checked
    Layout.bottomMargin: Style.marginL
    isSettings: true
    defaultValue: Settings.getDefaultValue("wallpaper.enabled")
  }

  NToggle {
    visible: Settings.data.wallpaper.enabled && CompositorService.isNiri
    label: I18n.tr("settings.wallpaper.settings.enable-overview.label")
    description: I18n.tr("settings.wallpaper.settings.enable-overview.description")
    checked: Settings.data.wallpaper.overviewEnabled
    onToggled: checked => Settings.data.wallpaper.overviewEnabled = checked
    Layout.bottomMargin: Style.marginL
    isSettings: true
    defaultValue: Settings.getDefaultValue("wallpaper.overviewEnabled")
  }

  NDivider {
    visible: Settings.data.wallpaper.enabled
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  ColumnLayout {
    visible: Settings.data.wallpaper.enabled
    spacing: Style.marginL
    Layout.fillWidth: true

    NTextInputButton {
      id: wallpaperPathInput
      label: I18n.tr("settings.wallpaper.settings.folder.label")
      description: I18n.tr("settings.wallpaper.settings.folder.description")
      text: Settings.data.wallpaper.directory
      buttonIcon: "folder-open"
      buttonTooltip: I18n.tr("settings.wallpaper.settings.folder.tooltip")
      Layout.fillWidth: true
      onInputEditingFinished: Settings.data.wallpaper.directory = text
      onButtonClicked: mainFolderPicker.open()
    }

    RowLayout {
      NLabel {
        label: I18n.tr("settings.wallpaper.settings.selector.label")
        description: I18n.tr("settings.wallpaper.settings.selector.description")
        Layout.alignment: Qt.AlignTop
      }

      NIconButton {
        icon: "wallpaper-selector"
        tooltipText: I18n.tr("settings.wallpaper.settings.selector.tooltip")
        onClicked: PanelService.getPanel("wallpaperPanel", screen)?.toggle()
      }
    }

    // Recursive search
    NToggle {
      label: I18n.tr("settings.wallpaper.settings.recursive-search.label")
      description: I18n.tr("settings.wallpaper.settings.recursive-search.description")
      checked: Settings.data.wallpaper.recursiveSearch
      onToggled: checked => Settings.data.wallpaper.recursiveSearch = checked
      isSettings: true
      defaultValue: Settings.getDefaultValue("wallpaper.recursiveSearch")
    }

    // Monitor-specific directories
    NToggle {
      label: I18n.tr("settings.wallpaper.settings.monitor-specific.label")
      description: I18n.tr("settings.wallpaper.settings.monitor-specific.description")
      checked: Settings.data.wallpaper.enableMultiMonitorDirectories
      onToggled: checked => Settings.data.wallpaper.enableMultiMonitorDirectories = checked
      isSettings: true
      defaultValue: Settings.getDefaultValue("wallpaper.enableMultiMonitorDirectories")
    }

    NBox {
      visible: Settings.data.wallpaper.enableMultiMonitorDirectories

      Layout.fillWidth: true
      radius: Style.radiusM
      color: Color.mSurface
      border.color: Color.mOutline
      border.width: Style.borderS
      implicitHeight: contentCol.implicitHeight + Style.marginL * 2
      clip: true

      ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM
        Repeater {
          model: Quickshell.screens || []
          delegate: ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NText {
              text: (modelData.name || "Unknown")
              color: Color.mPrimary
              font.weight: Style.fontWeightBold
              pointSize: Style.fontSizeM
            }

            NTextInputButton {
              text: WallpaperService.getMonitorDirectory(modelData.name)
              buttonIcon: "folder-open"
              buttonTooltip: I18n.tr("settings.wallpaper.settings.monitor-specific.tooltip")
              Layout.fillWidth: true
              onInputEditingFinished: WallpaperService.setMonitorDirectory(modelData.name, text)
              onButtonClicked: {
                specificFolderMonitorName = modelData.name;
                monitorFolderPicker.open();
              }
            }
          }
        }
      }
    }

    NComboBox {
      label: I18n.tr("settings.wallpaper.settings.selector-position.label")
      description: I18n.tr("settings.wallpaper.settings.selector-position.description")
      Layout.fillWidth: true
      model: [
        {
          "key": "follow_bar",
          "name": I18n.tr("options.launcher.position.follow_bar")
        },
        {
          "key": "center",
          "name": I18n.tr("options.launcher.position.center")
        },
        {
          "key": "top_center",
          "name": I18n.tr("options.launcher.position.top_center")
        },
        {
          "key": "top_left",
          "name": I18n.tr("options.launcher.position.top_left")
        },
        {
          "key": "top_right",
          "name": I18n.tr("options.launcher.position.top_right")
        },
        {
          "key": "bottom_left",
          "name": I18n.tr("options.launcher.position.bottom_left")
        },
        {
          "key": "bottom_right",
          "name": I18n.tr("options.launcher.position.bottom_right")
        },
        {
          "key": "bottom_center",
          "name": I18n.tr("options.launcher.position.bottom_center")
        }
      ]
      currentKey: Settings.data.wallpaper.panelPosition
      onSelected: key => Settings.data.wallpaper.panelPosition = key
      isSettings: true
      defaultValue: Settings.getDefaultValue("wallpaper.panelPosition")
    }
  }

  NDivider {
    visible: Settings.data.wallpaper.enabled
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  ColumnLayout {
    visible: Settings.data.wallpaper.enabled
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.wallpaper.look-feel.section.label")
    }

    // Fill Mode
    NComboBox {
      label: I18n.tr("settings.wallpaper.look-feel.fill-mode.label")
      description: I18n.tr("settings.wallpaper.look-feel.fill-mode.description")
      model: WallpaperService.fillModeModel
      currentKey: Settings.data.wallpaper.fillMode
      onSelected: key => Settings.data.wallpaper.fillMode = key
      isSettings: true
      defaultValue: Settings.getDefaultValue("wallpaper.fillMode")
    }

    RowLayout {
      NLabel {
        label: I18n.tr("settings.wallpaper.look-feel.fill-color.label")
        description: I18n.tr("settings.wallpaper.look-feel.fill-color.description")
        Layout.alignment: Qt.AlignTop
      }

      NColorPicker {
        screen: root.screen
        selectedColor: Settings.data.wallpaper.fillColor
        onColorSelected: color => Settings.data.wallpaper.fillColor = color
      }
    }

    // Transition Type
    NComboBox {
      label: I18n.tr("settings.wallpaper.look-feel.transition-type.label")
      description: I18n.tr("settings.wallpaper.look-feel.transition-type.description")
      model: WallpaperService.transitionsModel
      currentKey: Settings.data.wallpaper.transitionType
      onSelected: key => Settings.data.wallpaper.transitionType = key
      isSettings: true
      defaultValue: Settings.getDefaultValue("wallpaper.transitionType")
    }

    // Transition Duration
    ColumnLayout {
      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("settings.wallpaper.look-feel.transition-duration.label")
        description: I18n.tr("settings.wallpaper.look-feel.transition-duration.description")
        from: 500
        to: 10000
        stepSize: 100
        value: Settings.data.wallpaper.transitionDuration
        onMoved: value => Settings.data.wallpaper.transitionDuration = value
        text: (Settings.data.wallpaper.transitionDuration / 1000).toFixed(1) + "s"
        isSettings: true
        defaultValue: Settings.getDefaultValue("wallpaper.transitionDuration")
      }
    }

    // Edge Smoothness
    ColumnLayout {
      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("settings.wallpaper.look-feel.edge-smoothness.label")
        description: I18n.tr("settings.wallpaper.look-feel.edge-smoothness.description")
        from: 0.0
        to: 1.0
        value: Settings.data.wallpaper.transitionEdgeSmoothness
        onMoved: value => Settings.data.wallpaper.transitionEdgeSmoothness = value
        text: Math.round(Settings.data.wallpaper.transitionEdgeSmoothness * 100) + "%"
        isSettings: true
        defaultValue: Settings.getDefaultValue("wallpaper.transitionEdgeSmoothness")
      }
    }
  }

  NDivider {
    visible: Settings.data.wallpaper.enabled
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  ColumnLayout {
    visible: Settings.data.wallpaper.enabled
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.wallpaper.automation.section.label")
    }

    // Scheduled change toggle
    NToggle {
      label: I18n.tr("settings.wallpaper.automation.scheduled-change.label")
      description: I18n.tr("settings.wallpaper.automation.scheduled-change.description")
      checked: Settings.data.wallpaper.randomEnabled
      onToggled: checked => Settings.data.wallpaper.randomEnabled = checked
    }

    // Change mode combo box
    NComboBox {
      visible: Settings.data.wallpaper.randomEnabled
      label: I18n.tr("settings.wallpaper.automation.change-mode.label")
      description: I18n.tr("settings.wallpaper.automation.change-mode.description")
      Layout.fillWidth: true
      model: [
        {
          "key": "random",
          "name": I18n.tr("settings.wallpaper.automation.change-mode.random")
        },
        {
          "key": "alphabetical",
          "name": I18n.tr("settings.wallpaper.automation.change-mode.alphabetical")
        }
      ]
      currentKey: Settings.data.wallpaper.wallpaperChangeMode || "random"
      onSelected: key => Settings.data.wallpaper.wallpaperChangeMode = key
      isSettings: true
      defaultValue: Settings.getDefaultValue("wallpaper.transitionType")
    }

    // Interval
    ColumnLayout {
      visible: Settings.data.wallpaper.randomEnabled
      RowLayout {
        NLabel {
          label: I18n.tr("settings.wallpaper.automation.interval.label")
          description: I18n.tr("settings.wallpaper.automation.interval.description")
          Layout.fillWidth: true
        }

        NText {
          // Show friendly H:MM format from current settings
          text: Time.formatVagueHumanReadableDuration(Settings.data.wallpaper.randomIntervalSec)
          Layout.alignment: Qt.AlignBottom | Qt.AlignRight
        }
      }

      // Preset chips using Repeater
      RowLayout {
        id: presetRow
        spacing: Style.marginS

        // Factorized presets data
        property var intervalPresets: [5 * 60, 10 * 60, 15 * 60, 30 * 60, 45 * 60, 60 * 60, 90 * 60, 120 * 60]

        // Whether current interval equals one of the presets
        property bool isCurrentPreset: {
          return intervalPresets.some(seconds => seconds === Settings.data.wallpaper.randomIntervalSec);
        }
        // Allow user to force open the custom input; otherwise it's auto-open when not a preset
        property bool customForcedVisible: false

        function setIntervalSeconds(sec) {
          Settings.data.wallpaper.randomIntervalSec = sec;
          WallpaperService.restartRandomWallpaperTimer();
          // Hide custom when selecting a preset
          customForcedVisible = false;
        }

        // Helper to color selected chip
        function isSelected(sec) {
          return Settings.data.wallpaper.randomIntervalSec === sec;
        }

        // Repeater for preset chips
        Repeater {
          model: presetRow.intervalPresets
          delegate: IntervalPresetChip {
            seconds: modelData
            label: Time.formatVagueHumanReadableDuration(modelData)
            selected: presetRow.isSelected(modelData)
            onClicked: presetRow.setIntervalSeconds(modelData)
          }
        }

        // Custom… opens inline input
        IntervalPresetChip {
          label: customRow.visible ? "Custom" : "Custom…"
          selected: customRow.visible
          onClicked: presetRow.customForcedVisible = !presetRow.customForcedVisible
        }
      }

      // Custom HH:MM inline input
      RowLayout {
        id: customRow
        visible: presetRow.customForcedVisible || !presetRow.isCurrentPreset
        spacing: Style.marginS
        Layout.topMargin: Style.marginS

        NTextInput {
          label: I18n.tr("settings.wallpaper.automation.custom-interval.label")
          description: I18n.tr("settings.wallpaper.automation.custom-interval.description")
          text: {
            const s = Settings.data.wallpaper.randomIntervalSec;
            const h = Math.floor(s / 3600);
            const m = Math.floor((s % 3600) / 60);
            return h + ":" + (m < 10 ? ("0" + m) : m);
          }
          onEditingFinished: {
            const m = text.trim().match(/^(\d{1,2}):(\d{2})$/);
            if (m) {
              let h = parseInt(m[1]);
              let min = parseInt(m[2]);
              if (isNaN(h) || isNaN(min))
                return;
              h = Math.max(0, Math.min(24, h));
              min = Math.max(0, Math.min(59, min));
              Settings.data.wallpaper.randomIntervalSec = (h * 3600) + (min * 60);
              WallpaperService.restartRandomWallpaperTimer();
              // Keep custom visible after manual entry
              presetRow.customForcedVisible = true;
            }
          }
        }
      }
    }
  }

  // Reusable component for interval preset chips
  component IntervalPresetChip: Rectangle {
    property int seconds: 0
    property string label: ""
    property bool selected: false
    signal clicked

    radius: height * 0.5
    color: selected ? Color.mPrimary : Color.mSurfaceVariant
    implicitHeight: Math.max(Style.baseWidgetSize * 0.55, 24)
    implicitWidth: chipLabel.implicitWidth + Style.marginM * 1.5
    border.width: Style.borderS
    border.color: selected ? Color.transparent : Color.mOutline

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.clicked()
    }

    NText {
      id: chipLabel
      anchors.centerIn: parent
      text: parent.label
      pointSize: Style.fontSizeS
      color: parent.selected ? Color.mOnPrimary : Color.mOnSurface
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  NFilePicker {
    id: mainFolderPicker
    selectionMode: "folders"
    title: I18n.tr("settings.wallpaper.settings.select-folder")
    initialPath: Settings.data.wallpaper.directory || Quickshell.env("HOME") + "/Pictures"
    onAccepted: paths => {
                  if (paths.length > 0) {
                    Settings.data.wallpaper.directory = paths[0];
                  }
                }
  }

  NFilePicker {
    id: monitorFolderPicker
    selectionMode: "folders"
    title: I18n.tr("settings.wallpaper.settings.select-monitor-folder")
    initialPath: WallpaperService.getMonitorDirectory(specificFolderMonitorName) || Quickshell.env("HOME") + "/Pictures"
    onAccepted: paths => {
                  if (paths.length > 0) {
                    WallpaperService.setMonitorDirectory(specificFolderMonitorName, paths[0]);
                  }
                }
  }
}
