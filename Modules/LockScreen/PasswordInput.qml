import QtQuick
import QtQuick.Layouts

import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  property bool enabled: true
  property string password: ""
  property bool passwordVisible: false

  signal activated

  Layout.preferredHeight: 48
  radius: 24
  color: Color.mSurface
  border.color: passwordInput.activeFocus ? Color.mPrimary : Qt.alpha(Color.mOutline, 0.3)
  border.width: passwordInput.activeFocus ? 2 : 1

  Row {
    anchors.left: parent.left
    anchors.leftMargin: 18
    anchors.verticalCenter: parent.verticalCenter
    spacing: 14

    NIcon {
      icon: "lock"
      pointSize: Style.fontSizeL
      color: passwordInput.activeFocus ? Color.mPrimary : Color.mOnSurfaceVariant
      anchors.verticalCenter: parent.verticalCenter
    }

    // Hidden input that receives actual text
    TextInput {
      id: passwordInput
      width: 0
      height: 0
      visible: false
      enabled: root.enabled
      font.pointSize: Style.fontSizeM
      color: Color.mPrimary
      echoMode: root.passwordVisible ? TextInput.Normal : TextInput.Password
      passwordCharacter: "•"
      passwordMaskDelay: 0
      text: root.password
      onTextChanged: root.password = text

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activated()
        }
      }

      Component.onCompleted: forceActiveFocus()
    }

    Row {
      spacing: 0

      Rectangle {
        width: 2
        height: 20
        color: Color.mPrimary
        visible: passwordInput.activeFocus && passwordInput.text.length === 0
        anchors.verticalCenter: parent.verticalCenter

        SequentialAnimation on opacity {
          loops: Animation.Infinite
          running: passwordInput.activeFocus && passwordInput.text.length === 0
          NumberAnimation {
            to: 0
            duration: 530
          }
          NumberAnimation {
            to: 1
            duration: 530
          }
        }
      }

      // Password display - show dots or actual text based on passwordVisible
      Item {
        width: Math.min(passwordDisplayContent.width, 550)
        height: 20
        visible: passwordInput.text.length > 0 && !root.passwordVisible
        anchors.verticalCenter: parent.verticalCenter
        clip: true

        Row {
          id: passwordDisplayContent
          spacing: 6
          anchors.verticalCenter: parent.verticalCenter

          Repeater {
            model: passwordInput.text.length

            NIcon {
              icon: "circle-filled"
              pointSize: Style.fontSizeS
              color: Color.mPrimary
              opacity: 1.0
            }
          }
        }
      }

      NText {
        text: passwordInput.text
        color: Color.mPrimary
        pointSize: Style.fontSizeM
        font.weight: Font.Medium
        visible: passwordInput.text.length > 0 && root.passwordVisible
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 550)
      }

      Rectangle {
        width: 2
        height: 20
        color: Color.mPrimary
        visible: passwordInput.activeFocus && passwordInput.text.length > 0
        anchors.verticalCenter: parent.verticalCenter

        SequentialAnimation on opacity {
          loops: Animation.Infinite
          running: passwordInput.activeFocus && passwordInput.text.length > 0
          NumberAnimation {
            to: 0
            duration: 530
          }
          NumberAnimation {
            to: 1
            duration: 530
          }
        }
      }
    }
  }

  // Eye button to toggle password visibility
  Rectangle {
    anchors.right: submitButton.left
    anchors.rightMargin: 4
    anchors.verticalCenter: parent.verticalCenter
    width: 36
    height: 36
    radius: width * 0.5
    color: eyeButtonArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.1) : "transparent"
    visible: passwordInput.text.length > 0
    enabled: root.enabled

    NIcon {
      anchors.centerIn: parent
      icon: root.passwordVisible ? "eye-off" : "eye"
      pointSize: Style.fontSizeM
      color: Color.mOnSurfaceVariant
    }

    MouseArea {
      id: eyeButtonArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: root.passwordVisible = !root.passwordVisible
    }

    Behavior on color {
      ColorAnimation {
        duration: 200
        easing.type: Easing.OutCubic
      }
    }
  }

  // Submit button
  Rectangle {
    id: submitButton
    anchors.right: parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    width: 36
    height: 36
    radius: width * 0.5
    color: submitButtonArea.containsMouse ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.8)
    border.color: Color.mPrimary
    border.width: 1
    enabled: root.enabled

    NIcon {
      anchors.centerIn: parent
      icon: "arrow-forward"
      pointSize: Style.fontSizeM
      color: Color.mOnPrimary
    }

    MouseArea {
      id: submitButtonArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: root.activated()
    }
  }

  Behavior on border.color {
    ColorAnimation {
      duration: 200
      easing.type: Easing.OutCubic
    }
  }
}
