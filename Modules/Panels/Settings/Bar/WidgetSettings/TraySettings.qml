import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  // Properties to receive data from parent
  property var widgetData: ({}) // Expected by BarWidgetSettingsDialog
  property var widgetMetadata: ({}) // Expected by BarWidgetSettingsDialog

  // Local state
  property var localBlacklist: widgetData.blacklist || []
  property bool valueColorizeIcons: widgetData.colorizeIcons !== undefined ? widgetData.colorizeIcons : widgetMetadata.colorizeIcons
  property bool valueDrawerEnabled: widgetData.drawerEnabled !== undefined ? widgetData.drawerEnabled : (widgetMetadata.drawerEnabled !== undefined ? widgetMetadata.drawerEnabled : true)

  ListModel {
    id: blacklistModel
  }

  Component.onCompleted: {
    // Populate the ListModel from localBlacklist
    for (var i = 0; i < localBlacklist.length; i++) {
      blacklistModel.append({
                              "rule": localBlacklist[i]
                            })
    }
  }

  spacing: Style.marginM

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.tray.colorize-icons.label")
    description: I18n.tr("bar.widget-settings.tray.colorize-icons.description")
    checked: root.valueColorizeIcons
    onToggled: checked => root.valueColorizeIcons = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.tray.drawer-enabled.label")
    description: I18n.tr("bar.widget-settings.tray.drawer-enabled.description")
    checked: root.valueDrawerEnabled
    onToggled: checked => root.valueDrawerEnabled = checked
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: I18n.tr("settings.bar.tray.blacklist.label")
      description: I18n.tr("settings.bar.tray.blacklist.description")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NTextInputButton {
        id: newRuleInput
        Layout.fillWidth: true
        placeholderText: I18n.tr("settings.bar.tray.blacklist.placeholder")
        buttonIcon: "add"
        onButtonClicked: {
          if (newRuleInput.text.length > 0) {
            var newRule = newRuleInput.text.trim()
            var exists = false
            for (var i = 0; i < blacklistModel.count; i++) {
              if (blacklistModel.get(i).rule === newRule) {
                exists = true
                break
              }
            }
            if (!exists) {
              blacklistModel.append({
                                      "rule": newRule
                                    })
              newRuleInput.text = ""
            }
          }
        }
      }
    }
  }

  // List of current blacklist items
  ListView {
    Layout.fillWidth: true
    Layout.preferredHeight: 150
    Layout.topMargin: Style.marginL // Increased top margin
    clip: true
    model: blacklistModel
    delegate: Item {
      width: ListView.width
      height: 40

      Rectangle {
        id: itemBackground
        anchors.fill: parent
        anchors.margins: Style.marginXS
        color: Color.transparent // Make background transparent
        border.color: Color.mOutline
        border.width: Style.borderS
        radius: Style.radiusS
        visible: model.rule !== undefined && model.rule !== "" // Only visible if rule exists
      }

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.marginS
        anchors.rightMargin: Style.marginS
        spacing: Style.marginS

        NText {
          text: model.rule
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
          Layout.fillWidth: true
        }

        NIconButton {
          width: 16
          height: 16
          icon: "close"
          baseSize: 8
          colorBg: Color.mSurfaceVariant
          colorFg: Color.mOnSurface
          colorBgHover: Color.mError
          colorFgHover: Color.mOnError
          onClicked: {
            blacklistModel.remove(index)
          }
        }
      }
    }
  }

  // This function will be called by the dialog to get the new settings
  function saveSettings() {
    var newBlacklist = []
    for (var i = 0; i < blacklistModel.count; i++) {
      newBlacklist.push(blacklistModel.get(i).rule)
    }

    // Return the updated settings for this widget instance
    var settings = Object.assign({}, widgetData || {})
    settings.blacklist = newBlacklist
    settings.colorizeIcons = root.valueColorizeIcons
    settings.drawerEnabled = root.valueDrawerEnabled
    return settings
  }
}
