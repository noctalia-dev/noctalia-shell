import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property string label: ""
  property string description: ""
  property string currentKeybind: ""
  property string defaultKeybind: ""
  property color labelColor: Color.mOnSurface
  property color descriptionColor: Color.mOnSurfaceVariant

  signal keybindChanged(string newKeybind)

  implicitHeight: contentLayout.implicitHeight

  ColumnLayout {
    id: contentLayout
    width: parent.width
    spacing: Style.marginS

    // Label and Description (optional)
    NLabel {
      label: root.label
      description: root.description
      labelColor: root.labelColor
      descriptionColor: root.descriptionColor
      visible: label !== "" || description !== ""
      Layout.fillWidth: true
      Layout.bottomMargin: -Style.marginXS // Match other widgets spacing
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      // Keybind display pill
      Rectangle {
        id: displayPill
        Layout.fillWidth: true
        Layout.preferredHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio
        radius: Style.iRadiusM
        color: keybindInput.listening ? Color.mSecondary : Color.mSurface
        border.color: keybindInput.listening ? Color.mPrimary : (pillMouseArea.containsMouse ? Color.mSecondary : Color.mOutline)
        border.width: Style.borderS

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

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.marginM
          anchors.rightMargin: Style.marginM
          spacing: Style.marginS

          NIcon {
            icon: keybindInput.listening ? "circle-dot" : "keyboard"
            color: keybindInput.listening ? Color.mOnSecondary : Color.mOnSurfaceVariant
            opacity: 0.8
          }

          NText {
            Layout.fillWidth: true
            text: {
              if (keybindInput.listening)
                return I18n.tr("panels.session-menu.entry-settings-keybind-recording");
              if (root.currentKeybind === "")
                return I18n.tr("panels.session-menu.entry-settings-keybind-placeholder");
              return root.currentKeybind;
            }
            color: keybindInput.listening ? Color.mOnSecondary : (root.currentKeybind === "" ? Qt.alpha(Color.mOnSurfaceVariant, 0.6) : Color.mOnSurface)
            font.family: Settings.data.ui.fontFixed
            font.weight: root.currentKeybind !== "" ? Style.fontWeightBold : Style.fontWeightRegular
            elide: Text.ElideRight
          }
        }

        // MouseArea to trigger recording when clicking the pill
        MouseArea {
          id: pillMouseArea
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
            if (keybindInput.listening) {
              keybindInput.listening = false;
            } else {
              keybindInput.listening = true;
            }
          }
          cursorShape: Qt.PointingHandCursor
        }

        // Hidden Item to capture keys
        Item {
          id: keybindInput
          focus: true
          property bool listening: false

          onListeningChanged: {
            if (listening) {
              PanelService.isKeybindRecording = true;
              forceActiveFocus();
            } else {
              PanelService.isKeybindRecording = false;
            }
          }

          Keys.onPressed: event => {
                            if (!listening)
                            return;

                            // Handle Escape specifically to ensure it doesn't close the panel
                            if (event.key === Qt.Key_Escape) {
                              event.accepted = true;
                              root.currentKeybind = "Esc";
                              root.keybindChanged("Esc");
                              keybindInput.listening = false;
                              return;
                            }

                            // Ignore modifier keys by themselves
                            if (event.key === Qt.Key_Control || event.key === Qt.Key_Shift || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) {
                              event.accepted = true; // Consume modifiers too while listening
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

                              // Handle shifted digits
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
                                if (shiftMap[keyName])
                                keyName = shiftMap[keyName];
                              }
                            } else {
                              switch (event.key) {
                                case Qt.Key_Return:
                                keyName = "Return";
                                break;
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
                              var newBind = keyStr + keyName;
                              root.currentKeybind = newBind;
                              root.keybindChanged(newBind);
                              listening = false;
                            }
                            event.accepted = true;
                          }
        }
      }

      NIconButton {
        id: clearButton
        Layout.alignment: Qt.AlignVCenter
        visible: !keybindInput.listening && root.currentKeybind !== ""
        icon: "circle-x"

        colorBg: "transparent"
        colorBgHover: Qt.alpha(Color.mError, 0.1)
        colorFg: Color.mOnSurfaceVariant
        colorFgHover: Color.mError
        border.width: 0

        tooltipText: root.defaultKeybind !== "" ? I18n.tr("common.reset-to-default") : I18n.tr("common.clear")
        onClicked: {
          var newValue = root.defaultKeybind;
          root.currentKeybind = newValue;
          root.keybindChanged(newValue);
        }
      }
    }
  }
}
