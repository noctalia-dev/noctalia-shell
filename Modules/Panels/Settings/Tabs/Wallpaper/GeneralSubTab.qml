import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var screen

  signal openMainFolderPicker
  signal openMonitorFolderPicker(string monitorName)

  NToggle {
    label: I18n.tr("panels.wallpaper.settings-enable-management-label")
    description: I18n.tr("panels.wallpaper.settings-enable-management-description")
    checked: Settings.data.wallpaper.enabled
    onToggled: checked => Settings.data.wallpaper.enabled = checked
    defaultValue: Settings.getDefaultValue("wallpaper.enabled")
  }

  NToggle {
    visible: Settings.data.wallpaper.enabled && CompositorService.isNiri
    label: I18n.tr("panels.wallpaper.settings-enable-overview-label")
    description: I18n.tr("panels.wallpaper.settings-enable-overview-description")
    checked: Settings.data.wallpaper.overviewEnabled
    onToggled: checked => Settings.data.wallpaper.overviewEnabled = checked
    defaultValue: Settings.getDefaultValue("wallpaper.overviewEnabled")
  }

  ColumnLayout {
    visible: Settings.data.wallpaper.enabled
    spacing: Style.marginL
    Layout.fillWidth: true

    NTextInputButton {
      id: wallpaperPathInput
      label: I18n.tr("panels.wallpaper.settings-folder-label")
      description: I18n.tr("panels.wallpaper.settings-folder-description")
      text: Settings.data.wallpaper.directory
      buttonIcon: "folder-open"
      buttonTooltip: I18n.tr("panels.wallpaper.settings-folder-label")
      Layout.fillWidth: true
      onInputEditingFinished: Settings.data.wallpaper.directory = text
      onButtonClicked: root.openMainFolderPicker()
    }

    RowLayout {
      NLabel {
        label: I18n.tr("tooltips.wallpaper-selector")
        description: I18n.tr("panels.wallpaper.settings-selector-description")
        Layout.alignment: Qt.AlignTop
      }

      NIconButton {
        icon: "wallpaper-selector"
        tooltipText: I18n.tr("tooltips.wallpaper-selector")
        onClicked: PanelService.getPanel("wallpaperPanel", root.screen)?.toggle()
      }
    }

    NToggle {
      label: I18n.tr("panels.wallpaper.settings-recursive-search-label")
      description: I18n.tr("panels.wallpaper.settings-recursive-search-description")
      checked: Settings.data.wallpaper.recursiveSearch
      onToggled: checked => Settings.data.wallpaper.recursiveSearch = checked
      defaultValue: Settings.getDefaultValue("wallpaper.recursiveSearch")
    }

    NToggle {
      label: I18n.tr("panels.wallpaper.settings-monitor-specific-label")
      description: I18n.tr("panels.wallpaper.settings-monitor-specific-description")
      checked: Settings.data.wallpaper.enableMultiMonitorDirectories
      onToggled: checked => Settings.data.wallpaper.enableMultiMonitorDirectories = checked
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
              buttonTooltip: I18n.tr("panels.wallpaper.settings-monitor-specific-tooltip")
              Layout.fillWidth: true
              onInputEditingFinished: WallpaperService.setMonitorDirectory(modelData.name, text)
              onButtonClicked: root.openMonitorFolderPicker(modelData.name)
            }
          }
        }
      }
    }

    NComboBox {
      label: I18n.tr("common.position")
      description: I18n.tr("panels.wallpaper.settings-selector-position-description")
      Layout.fillWidth: true
      model: [
        {
          "key": "follow_bar",
          "name": I18n.tr("positions.follow-bar")
        },
        {
          "key": "center",
          "name": I18n.tr("positions.center")
        },
        {
          "key": "top_center",
          "name": I18n.tr("positions.top-center")
        },
        {
          "key": "top_left",
          "name": I18n.tr("positions.top-left")
        },
        {
          "key": "top_right",
          "name": I18n.tr("positions.top-right")
        },
        {
          "key": "bottom_left",
          "name": I18n.tr("positions.bottom-left")
        },
        {
          "key": "bottom_right",
          "name": I18n.tr("positions.bottom-right")
        },
        {
          "key": "bottom_center",
          "name": I18n.tr("positions.bottom-center")
        }
      ]
      currentKey: Settings.data.wallpaper.panelPosition
      onSelected: key => Settings.data.wallpaper.panelPosition = key
      defaultValue: Settings.getDefaultValue("wallpaper.panelPosition")
    }
  }
}
