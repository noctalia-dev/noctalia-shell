import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Popup {
  id: root
  modal: true
  dim: true
  anchors.centerIn: parent

  width: Math.min(600 * Style.uiScaleRatio, parent.width * 0.9)
  height: Math.min(contentLayout.implicitHeight + padding * 2, parent.height * 0.9)
  padding: Style.marginL

  property int editIndex: -1
  property int timeoutValue: 60
  property string commandValue: ""
  property string resumeCommandValue: ""
  property string nameValue: ""
  property bool showCommand: true
  property bool showTimeout: true
  property bool showName: false
  property string titleText: root.editIndex >= 0 ? I18n.tr("panels.idle.custom-entry-edit") : I18n.tr("panels.idle.custom-entry-new")

  signal saved(int timeout, string command, string resumeCommand, string name)

  property var _savedSlot: null

  background: Rectangle {
    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mOutline
    border.width: Style.borderS
  }

  onOpened: {
    nameInput.text = nameValue;
    timeoutSpinBox.value = timeoutValue;
    commandInput.text = commandValue;
    resumeCommandInput.text = resumeCommandValue;
    if (showName) {
      nameInput.forceActiveFocus();
    } else {
      timeoutSpinBox.forceActiveFocus();
    }
  }

  contentItem: ColumnLayout {
    id: contentLayout
    spacing: Style.marginL

    // Header
    RowLayout {
      Layout.fillWidth: true
      NText {
        text: root.titleText
        font.weight: Style.fontWeightBold
        pointSize: Style.fontSizeL
        Layout.fillWidth: true
      }
      NIconButton {
        icon: "close"
        onClicked: root.close()
      }
    }

    // Input Area
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NTextInput {
        id: nameInput
        visible: root.showName
        Layout.fillWidth: true
        label: I18n.tr("panels.idle.custom-entry-name")
        placeholderText: I18n.tr("panels.idle.custom-entry-name-placeholder")
      }

      NSpinBox {
        id: timeoutSpinBox
        visible: root.showTimeout
        Layout.fillWidth: true
        label: I18n.tr("panels.idle.custom-entry-timeout")
        from: 0
        to: 86400
        suffix: "s"
      }

      NTextInput {
        id: commandInput
        visible: root.showCommand
        Layout.fillWidth: true
        label: I18n.tr("panels.idle.custom-entry-command")
        placeholderText: "notify-send \"Idle\""
        fontFamily: Settings.data.ui.fontFixed
      }

      NTextInput {
        id: resumeCommandInput
        Layout.fillWidth: true
        label: I18n.tr("panels.idle.resume-command-label")
        placeholderText: "notify-send \"Welcome back!\""
        fontFamily: Settings.data.ui.fontFixed
      }
    }

    // Action Buttons
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      Item {
        Layout.fillWidth: true
      } // Spacer

      NButton {
        text: I18n.tr("common.cancel")
        outlined: true
        onClicked: root.close()
      }

      NButton {
        text: I18n.tr("common.save")
        icon: "check"
        backgroundColor: Color.mPrimary
        textColor: Color.mOnPrimary
        onClicked: {
          root.saved(timeoutSpinBox.value, commandInput.text, resumeCommandInput.text, nameInput.text);
          root.close();
        }
      }
    }
  }
}
