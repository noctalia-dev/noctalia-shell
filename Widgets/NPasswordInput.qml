import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  width: 600
  height: 48

  radius: Style.iRadiusL
  color: Color.mSurface
  border.color: passwordInput.activeFocus ? Color.mPrimary : Qt.alpha(Color.mOutline, 0.3)
  border.width: passwordInput.activeFocus ? 2 : 1

  property bool passwordVisible: false
  property var lockContext: null
  property bool timerActive: false
  property alias text: passwordInput.text
  property bool passwordFocused: false

  signal submitted
  signal cancelled

  function forceActiveFocus() {
    passwordInput.forceActiveFocus();
  }

  Behavior on border.color {
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  // Hidden input that receives actual text
  TextInput {
    id: passwordInput
    anchors.left: parent.left
    anchors.leftMargin: -1000
    width: 0
    height: 0
    visible: false
    enabled: !root.lockContext || !root.lockContext.unlockInProgress
    echoMode: TextInput.Password
    passwordMaskDelay: 0

    onActiveFocusChanged: root.passwordFocused = activeFocus

    // Bidirectional sync with lockContext — avoids declarative binding that breaks on input
    onTextChanged: {
      if (root.lockContext && lockContext.currentText !== text)
        lockContext.currentText = text;
    }

    Connections {
      target: root.lockContext
      function onCurrentTextChanged() {
        if (root.lockContext && passwordInput.text !== lockContext.currentText)
          passwordInput.text = lockContext.currentText;
      }
    }

    Keys.onPressed: function(event) {
      if (Keybinds.checkKey(event, 'enter', Settings)) {
        root.submitted();
        event.accepted = true;
      }
      if (Keybinds.checkKey(event, 'escape', Settings) && root.timerActive) {
        root.cancelled();
        event.accepted = true;
      }
    }

    Component.onCompleted: forceActiveFocus()
  }

  // Ctrl + A to select all
  Shortcut {
    sequence: StandardKey.SelectAll
    enabled: passwordInput.activeFocus
    onActivated: passwordInput.selectAll()
  }

  // Esc to clear selection
  Shortcut {
    sequences: [StandardKey.Cancel]
    enabled: passwordInput.activeFocus && passwordInput.selectionStart !== passwordInput.selectionEnd
    onActivated: passwordInput.deselect()
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: 18
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.marginL

    NIcon {
      icon: "login-2"
      pointSize: Style.fontSizeL
      color: passwordInput.activeFocus ? Color.mPrimary : Color.mOnSurfaceVariant
      anchors.verticalCenter: parent.verticalCenter
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
          NumberAnimation { to: 0; duration: 530 }
          NumberAnimation { to: 1; duration: 530 }
        }
      }

      // Host for dots / plain text and the caret
      Item {
        id: passwordVisualHost
        height: 20
        width: root.passwordVisible
            ? Math.min(visiblePasswordPlainText.implicitWidth, 550)
            : Math.min(passwordDisplayContent.width, 550)
        anchors.verticalCenter: parent.verticalCenter

        readonly property real caretVisualX: {
          const len = passwordInput.text.length;
          if (len <= 0) return 0;
          if (root.passwordVisible) {
            const adv = passwordCaretFontMetrics.advanceWidth(
                passwordInput.text.substring(0, passwordInput.cursorPosition));
            return Math.max(0, Math.min(adv, width));
          }
          const w = passwordDisplayContent.width;
          if (w <= 0) return 0;
          return Math.max(0, Math.min((passwordInput.cursorPosition / len) * w, width));
        }

        // Password dots display with selection support
        Item {
          width: Math.min(passwordDisplayContent.width, 550)
          height: 20
          visible: passwordInput.text.length > 0 && !root.passwordVisible
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          clip: true

          // Proportional selection highlight behind the dots
          Rectangle {
            visible: passwordInput.selectionStart !== passwordInput.selectionEnd && passwordInput.text.length > 0
            color: Qt.alpha(Color.mPrimary, 0.8)
            height: parent.height + Style.marginS
            anchors.verticalCenter: parent.verticalCenter
            x: (passwordInput.selectionStart / passwordInput.text.length) * passwordDisplayContent.width
            width: ((passwordInput.selectionEnd - passwordInput.selectionStart) / passwordInput.text.length) * passwordDisplayContent.width
          }

          Row {
            id: passwordDisplayContent
            spacing: Style.marginXXXS
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
              id: iconRepeater
              model: ScriptModel {
                values: Array(passwordInput.text.length)
              }

              property list<string> passwordChars: [
                "circle-filled", "pentagon-filled", "michelin-star-filled",
                "square-rounded-filled", "guitar-pick-filled",
                "blob-filled", "triangle-filled"
              ]

              NIcon {
                id: icon
                required property int index

                property bool drawCustomChar: index >= 0 && Settings.data.general.passwordChars
                property bool isSelected: index >= 0
                    && passwordInput.selectionStart !== passwordInput.selectionEnd
                    && index >= passwordInput.selectionStart
                    && index < passwordInput.selectionEnd

                icon: drawCustomChar
                    ? iconRepeater.passwordChars[index % iconRepeater.passwordChars.length]
                    : "circle-filled"
                pointSize: Style.fontSizeL
                color: isSelected ? Color.mOnPrimary : Color.mPrimary
                opacity: 1.0
              }
            }
          }

          // Mouse area for click-to-position and drag-to-select
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor

            property int dragStartPos: 0
            property bool pendingSelectAll: false

            Timer {
              id: doubleClickResetTimer
              interval: 600
              onTriggered: parent.pendingSelectAll = false
            }

            function charIndexFromX(mouseX) {
              if (passwordInput.text.length === 0) return 0;
              var charWidth = passwordDisplayContent.width / passwordInput.text.length;
              return Math.max(0, Math.min(
                  passwordInput.text.length - 1, Math.floor(mouseX / charWidth)));
            }

            onPressed: function(mouse) {
              doubleClickResetTimer.stop();
              passwordInput.forceActiveFocus();
              dragStartPos = charIndexFromX(mouse.x);
              passwordInput.cursorPosition = dragStartPos;
            }

            onPositionChanged: function(mouse) {
              pendingSelectAll = false;
              var curPos = charIndexFromX(mouse.x);
              if (curPos <= dragStartPos) {
                passwordInput.select(curPos, dragStartPos + 1);
              } else {
                passwordInput.select(dragStartPos, curPos + 1);
              }
            }

            onDoubleClicked: function(mouse) {
              passwordInput.forceActiveFocus();
              if (pendingSelectAll) {
                passwordInput.selectAll();
                pendingSelectAll = false;
              } else {
                var pos = charIndexFromX(mouse.x);
                passwordInput.select(pos, Math.min(pos + 1, passwordInput.text.length));
                pendingSelectAll = true;
                doubleClickResetTimer.restart();
              }
            }
          }
        }

        // Plain text display when password is visible
        NText {
          id: visiblePasswordPlainText
          text: passwordInput.text
          color: Color.mOnSurface
          pointSize: Style.fontSizeM
          visible: passwordInput.text.length > 0 && root.passwordVisible
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          width: Math.min(implicitWidth, 550)
        }

        // Caret for when text is entered
        Rectangle {
          width: 2
          height: 20
          x: passwordVisualHost.caretVisualX
          color: Color.mPrimary
          visible: passwordInput.activeFocus
                && passwordInput.text.length > 0
                && passwordInput.selectionStart === passwordInput.selectionEnd
          anchors.verticalCenter: parent.verticalCenter

          SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: passwordInput.activeFocus
                && passwordInput.text.length > 0
                && passwordInput.selectionStart === passwordInput.selectionEnd
            NumberAnimation { to: 0; duration: 530 }
            NumberAnimation { to: 1; duration: 530 }
          }
        }
      }
    }
  }

  // Eye button to toggle password visibility
  Rectangle {
    anchors.right: parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    width: 36
    height: 36
    radius: Math.min(Style.iRadiusL, width / 2)
    color: eyeButtonArea.containsMouse ? Color.mPrimary : "transparent"
    visible: passwordInput.text.length > 0
    enabled: !root.lockContext || !root.lockContext.unlockInProgress

    NIcon {
      anchors.centerIn: parent
      icon: root.passwordVisible ? "eye-off" : "eye"
      pointSize: Style.fontSizeM
      color: eyeButtonArea.containsMouse ? Color.mOnPrimary : Color.mOnSurfaceVariant

      Behavior on color {
        ColorAnimation {
          duration: Style.animationFast
          easing.type: Easing.OutCubic
        }
      }
    }

    MouseArea {
      id: eyeButtonArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.passwordVisible = !root.passwordVisible
    }

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCubic
      }
    }
  }

  FontMetrics {
    id: passwordCaretFontMetrics
    font: visiblePasswordPlainText.font
  }
}
