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

  signal settingsChanged(var settings)

  // Local state
  property var localBlacklist: widgetData.blacklist || []
  property bool valueColorizeIcons: widgetData.colorizeIcons !== undefined ? widgetData.colorizeIcons : widgetMetadata.colorizeIcons
  property bool valueDrawerEnabled: widgetData.drawerEnabled !== undefined ? widgetData.drawerEnabled : widgetMetadata.drawerEnabled
  property bool valueHidePassive: widgetData.hidePassive !== undefined ? widgetData.hidePassive : widgetMetadata.hidePassive

  ListModel {
    id: blacklistModel
  }

  Component.onCompleted: {
    // Populate the ListModel from localBlacklist
    for (var i = 0; i < localBlacklist.length; i++) {
      blacklistModel.append({
                              "rule": localBlacklist[i]
                            });
    }
  }

  spacing: Style.marginM

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.tray.colorize-icons-label")
    description: I18n.tr("bar.tray.colorize-icons-description")
    checked: root.valueColorizeIcons
    onToggled: checked => {
                 root.valueColorizeIcons = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.tray.drawer-enabled-label")
    description: I18n.tr("bar.tray.drawer-enabled-description")
    checked: root.valueDrawerEnabled
    onToggled: checked => {
                 root.valueDrawerEnabled = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.tray.hide-passive-label")
    description: I18n.tr("bar.tray.hide-passive-description")
    checked: root.valueHidePassive
    onToggled: checked => {
                 root.valueHidePassive = checked;
                 settingsChanged(saveSettings());
               }
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: I18n.tr("panels.bar.tray-blacklist-label")
      description: I18n.tr("panels.bar.tray-blacklist-description")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NTextInputButton {
        id: newRuleInput
        Layout.fillWidth: true
        placeholderText: I18n.tr("panels.bar.tray-blacklist-placeholder")
        buttonIcon: "add"
        onButtonClicked: {
          if (newRuleInput.text.length > 0) {
            var newRule = newRuleInput.text.trim();
            var exists = false;
            for (var i = 0; i < blacklistModel.count; i++) {
              if (blacklistModel.get(i).rule === newRule) {
                exists = true;
                break;
              }
            }
            if (!exists) {
              blacklistModel.append({
                                      "rule": newRule
                                    });
              newRuleInput.text = "";
              settingsChanged(saveSettings());
            }
          }
        }
      }
    }
  }

  // List of current blacklist items
  NListView {
    Layout.fillWidth: true
    Layout.preferredHeight: 150
    Layout.topMargin: Style.marginL // Increased top margin
    gradientColor: Color.mSurface

    model: blacklistModel
    delegate: Item {
      width: ListView.width
      height: 40

      Rectangle {
        id: itemBackground
        anchors.fill: parent
        anchors.margins: Style.marginXS
        color: "transparent" // Make background transparent
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
          anchors.verticalCenter: parent.verticalCenter
          text: model.rule
          elide: Text.ElideRight
        }

        NIconButton {
          anchors.verticalCenter: parent.verticalCenter
          icon: "close"
          baseSize: 12 * Style.uiScaleRatio
          colorBg: Color.mSurfaceVariant
          colorFg: Color.mOnSurfaceVariant
          colorBgHover: Color.mError
          colorFgHover: Color.mOnError
          onClicked: {
            blacklistModel.remove(index);
            settingsChanged(saveSettings());
          }
        }
      }
    }
  }

  // This function will be called by the dialog to get the new settings
  function saveSettings() {
    var newBlacklist = [];
    for (var i = 0; i < blacklistModel.count; i++) {
      newBlacklist.push(blacklistModel.get(i).rule);
    }

    // Return the updated settings for this widget instance
    var settings = Object.assign({}, widgetData || {});
    settings.blacklist = newBlacklist;
    settings.colorizeIcons = root.valueColorizeIcons;
    settings.drawerEnabled = root.valueDrawerEnabled;
    settings.hidePassive = root.valueHidePassive;
    return settings;
  }
}
