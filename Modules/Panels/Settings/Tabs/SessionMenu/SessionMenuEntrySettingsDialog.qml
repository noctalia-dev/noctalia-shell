import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Session Menu Entry Settings Dialog Component
Popup {
  id: root

  property int entryIndex: -1
  property var entryData: null
  property string entryId: ""
  property string entryText: ""

  signal updateEntryProperties(int index, var properties)

  // Default commands mapping
  readonly property var defaultCommands: {
    "lock": I18n.tr("panels.session-menu.entry-settings-default-command-lock"),
    "suspend": "systemctl suspend || loginctl suspend",
    "hibernate": "systemctl hibernate || loginctl hibernate",
    "reboot": "systemctl reboot || loginctl reboot",
    "logout": I18n.tr("panels.session-menu.entry-settings-default-command-logout"),
    "shutdown": "systemctl poweroff || loginctl poweroff"
  }

  readonly property string defaultCommand: defaultCommands[entryId] || ""

  width: Math.max(content.implicitWidth + padding * 2, 500)
  height: content.implicitHeight + padding * 2
  padding: Style.marginXL
  modal: true
  dim: false
  anchors.centerIn: parent

  onOpened: {
    // Load command when popup opens
    if (entryData) {
      commandInput.text = entryData.command || "";
      keybindInput.text = entryData.keybind || "";
    }
    // Request focus to ensure keyboard input works
    forceActiveFocus();
  }

  function save() {
    root.updateEntryProperties(root.entryIndex, {
                                 "command": commandInput.text,
                                 "keybind": keybindInput.text
                               });
  }

  background: Rectangle {
    id: bgRect

    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mPrimary
    border.width: Style.borderM
  }

  contentItem: FocusScope {
    id: focusScope
    focus: true

    ColumnLayout {
      id: content
      anchors.fill: parent
      spacing: Style.marginM

      // Title
      RowLayout {
        Layout.fillWidth: true

        NText {
          text: I18n.tr("panels.session-menu.entry-settings-title", {
                          "entry": root.entryText
                        })
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mPrimary
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "close"
          tooltipText: I18n.tr("common.close")
          onClicked: {
            root.save();
            root.close();
          }
        }
      }

      // Separator
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
      }

      // Command input
      NTextInput {
        id: commandInput
        Layout.fillWidth: true
        label: I18n.tr("common.command")
        description: I18n.tr("panels.session-menu.entry-settings-command-description")
        placeholderText: I18n.tr("panels.session-menu.entry-settings-command-placeholder")
        onTextChanged: root.save()
      }

      // Default command info
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS

        NLabel {
          label: I18n.tr("panels.session-menu.entry-settings-default-info-label")
          description: I18n.tr("panels.session-menu.entry-settings-default-info-description")
          Layout.fillWidth: true
        }

        // Default command display
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: defaultCommandText.implicitHeight + Style.marginXL
          radius: Style.radiusM
          color: Color.mSurfaceVariant
          border.color: Color.mOutline
          border.width: Style.borderS

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginS

            NIcon {
              icon: "info"
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeM
            }

            NText {
              id: defaultCommandText
              Layout.fillWidth: true
              text: root.defaultCommand
              color: Color.mOnSurfaceVariant
              font.family: "monospace"
              font.pointSize: Style.fontSizeS
              wrapMode: Text.Wrap
            }
          }
        }
      }

      // Keybind input
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NTextInput {
          id: keybindInput
          Layout.fillWidth: true
          label: I18n.tr("common.keybind")
          description: I18n.tr("panels.session-menu.entry-settings-keybind-description")
          placeholderText: listening ? I18n.tr("panels.session-menu.entry-settings-keybind-recording") : I18n.tr("panels.session-menu.entry-settings-keybind-placeholder")
          inputIconName: listening ? "circle-dot" : ""
          readOnly: true

          property bool listening: false

          // Clear text when starting to listen to show it's active
          onListeningChanged: {
            if (listening) {
              text = "";
            }
          }

          Keys.onPressed: event => {
                            if (!listening)
                            return;

                            // Ignore modifier keys by themselves
                            if (event.key === Qt.Key_Control || event.key === Qt.Key_Shift || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) {
                              return;
                            }

                            let keyStr = "";
                            if (event.modifiers & Qt.ControlModifier)
                            keyStr += "Ctrl+";
                            if (event.modifiers & Qt.AltModifier)
                            keyStr += "Alt+";
                            if (event.modifiers & Qt.ShiftModifier)
                            keyStr += "Shift+";

                            let keyName = "";
                            let rawText = event.text;

                            if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z || event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                              keyName = String.fromCharCode(event.key);
                            } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) {
                              keyName = "F" + (event.key - Qt.Key_F1 + 1);
                            } else if (rawText && rawText.length > 0 && rawText.charCodeAt(0) > 31) {
                              keyName = rawText.toUpperCase();

                              // Handle shifted digits for common layouts (e.g., German, US)
                              // If shift is pressed and we get a symbol, try to map it back to the base key
                              if (event.modifiers & Qt.ShiftModifier) {
                                const shiftMap = {
                                  "!": "1",
                                  "\"": "2",
                                  "§": "3",
                                  "$": "4",
                                  "%": "5",
                                  "&": "6",
                                  "/": "7",
                                  "(": "8",
                                  ")": "9",
                                  "=": "0",
                                  "@": "2",
                                  "#": "3",
                                  "^": "6",
                                  "*": "8"
                                };
                                if (shiftMap[keyName]) {
                                  keyName = shiftMap[keyName];
                                }
                              }
                            } else {
                              // Fallback for non-printable keys like Esc, Enter, etc.
                              switch (event.key) {
                                case Qt.Key_Escape:
                                keyName = "Esc";
                                break;
                                case Qt.Key_Space:
                                keyName = "Space";
                                break;
                                case Qt.Key_Return:
                                case Qt.Key_Enter:
                                keyName = "Enter";
                                break;
                                case Qt.Key_Tab:
                                keyName = "Tab";
                                break;
                                case Qt.Key_Backspace:
                                keyName = "Backspace";
                                break;
                                case Qt.Key_Delete:
                                keyName = "Del";
                                break;
                                case Qt.Key_Insert:
                                keyName = "Ins";
                                break;
                                case Qt.Key_Home:
                                keyName = "Home";
                                break;
                                case Qt.Key_End:
                                keyName = "End";
                                break;
                                case Qt.Key_PageUp:
                                keyName = "PgUp";
                                break;
                                case Qt.Key_PageDown:
                                keyName = "PgDn";
                                break;
                                case Qt.Key_Left:
                                keyName = "Left";
                                break;
                                case Qt.Key_Right:
                                keyName = "Right";
                                break;
                                case Qt.Key_Up:
                                keyName = "Up";
                                break;
                                case Qt.Key_Down:
                                keyName = "Down";
                                break;
                              }
                            }

                            if (keyName) {
                              keybindInput.text = keyStr + keyName;
                              listening = false;
                              focusScope.focus = true;
                              root.save();
                            }
                          }
        }

        NIconButton {
          id: clearButton
          Layout.alignment: Qt.AlignBottom
          Layout.bottomMargin: Math.round(4 * Style.uiScaleRatio)
          visible: !keybindInput.listening && keybindInput.text !== ""
          icon: "circle-x"

          colorBg: "transparent"
          colorBgHover: Qt.alpha(Color.mError, 0.1)
          colorFg: Color.mOnSurfaceVariant
          colorFgHover: Color.mError
          border.width: 0

          tooltipText: I18n.tr("common.clear")
          onClicked: {
            keybindInput.text = "";
            root.save();
          }
        }

        NIconButton {
          id: recordButton
          Layout.alignment: Qt.AlignBottom
          Layout.bottomMargin: Math.round(4 * Style.uiScaleRatio)
          Layout.rightMargin: Style.marginS
          icon: keybindInput.listening ? "x" : "circle-dot"

          // Standard colors when not listening, distinctive when listening
          colorBg: keybindInput.listening ? Color.mError : Color.mSurfaceVariant
          colorFg: keybindInput.listening ? Color.mOnError : Color.mPrimary
          colorBgHover: keybindInput.listening ? Color.mError : Color.mHover
          colorFgHover: keybindInput.listening ? Color.mOnError : Color.mOnHover

          // Match NButton radius
          customRadius: Style.iRadiusS
          border.width: 0

          Behavior on colorBg {
            ColorAnimation {
              duration: Style.animationFast
            }
          }

          SequentialAnimation {
            id: recordingPulse
            running: keybindInput.listening
            loops: Animation.Infinite

            NumberAnimation {
              target: recordButton
              property: "opacity"
              from: 1.0
              to: 0.6
              duration: 500
              easing.type: Easing.InOutSine
            }
            NumberAnimation {
              target: recordButton
              property: "opacity"
              from: 0.6
              to: 1.0
              duration: 500
              easing.type: Easing.InOutSine
            }
          }

          tooltipText: keybindInput.listening ? I18n.tr("common.cancel") : I18n.tr("common.record")
          onClicked: {
            if (keybindInput.listening) {
              keybindInput.listening = false;
              focusScope.focus = true;
            } else {
              keybindInput.listening = true;
              keybindInput.forceActiveFocus();
            }
          }
        }
      }

      // Bottom spacer to maintain padding
      Item {
        Layout.preferredHeight: Style.marginS
      }
    }
  }
}
