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
  property var currentKeybinds: []
  property string defaultKeybind: ""
  property bool allowEmpty: false
  property color labelColor: Color.mOnSurface
  property color descriptionColor: Color.mOnSurfaceVariant

  signal keybindsChanged(var newKeybinds)

  implicitHeight: contentLayout.implicitHeight

  // -1 = not recording, >= 0 = re-recording at index, -2 = adding new
  property int recordingIndex: -1

  onRecordingIndexChanged: PanelService.isKeybindRecording = recordingIndex !== -1

  readonly property real _pillHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio

  function _applyKeybind(keyStr) {
    var newKeybinds = Array.from(root.currentKeybinds);
    if (recordingIndex >= 0) {
      newKeybinds[recordingIndex] = keyStr;
    } else if (recordingIndex === -2) {
      newKeybinds.push(keyStr);
    }
    recordingIndex = -1;
    root.keybindsChanged(newKeybinds);
  }

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

    Flow {
      Layout.fillWidth: true
      spacing: Style.marginS

      // Existing keybind pills
      Repeater {
        model: root.currentKeybinds

        delegate: MouseArea {
          id: pillArea
          width: pillBg.width
          height: root._pillHeight
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor

          property bool isRecordingThis: root.recordingIndex === index

          onClicked: {
            if (isRecordingThis) {
              root.recordingIndex = -1;
            } else {
              root.recordingIndex = index;
              keybindInput.forceActiveFocus();
            }
          }

          Rectangle {
            id: pillBg
            width: Math.max(root._pillHeight * 2, pillRow.implicitWidth + Style.marginM * 2)
            height: parent.height
            radius: Style.iRadiusS
            color: pillArea.isRecordingThis ? Color.mSecondary : (pillArea.containsMouse ? Qt.alpha(Color.mSecondary, 0.15) : Color.mSurface)
            border.color: pillArea.isRecordingThis ? Color.mPrimary : (pillArea.containsMouse ? Color.mSecondary : Color.mOutline)
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
              id: pillRow
              anchors.centerIn: parent
              spacing: Style.marginXS

              NIcon {
                icon: pillArea.isRecordingThis ? "circle-dot" : "keyboard"
                color: pillArea.isRecordingThis ? Color.mOnSecondary : Color.mOnSurfaceVariant
                opacity: 0.8
              }

              NText {
                text: pillArea.isRecordingThis ? I18n.tr("panels.session-menu.entry-settings-keybind-recording") : modelData
                color: pillArea.isRecordingThis ? Color.mOnSecondary : Color.mOnSurface
                font.family: Settings.data.ui.fontFixed
                font.weight: Style.fontWeightBold
              }

              // Remove button (hidden if only one keybind or while recording)
              NIconButton {
                visible: (root.currentKeybinds.length > 1 || root.allowEmpty) && root.recordingIndex === -1
                icon: "x"
                colorBg: "transparent"
                colorBgHover: Qt.alpha(Color.mError, 0.1)
                colorFg: Color.mOnSurfaceVariant
                colorFgHover: Color.mError
                border.width: 0
                tooltipText: I18n.tr("common.delete")
                onClicked: {
                  var newKeybinds = Array.from(root.currentKeybinds);
                  newKeybinds.splice(index, 1);
                  root.keybindsChanged(newKeybinds);
                }
              }
            }
          }
        }
      }

      // Recording indicator for new keybind
      MouseArea {
        visible: root.recordingIndex === -2
        width: addRecordingBg.width
        height: root._pillHeight
        cursorShape: Qt.PointingHandCursor
        onClicked: root.recordingIndex = -1

        Rectangle {
          id: addRecordingBg
          width: addRecordingRow.implicitWidth + Style.marginM * 2
          height: parent.height
          radius: Style.iRadiusS
          color: Color.mSecondary
          border.color: Color.mPrimary
          border.width: Style.borderS

          RowLayout {
            id: addRecordingRow
            anchors.centerIn: parent
            spacing: Style.marginXS

            NIcon {
              icon: "circle-dot"
              color: Color.mOnSecondary
              opacity: 0.8
            }

            NText {
              text: I18n.tr("panels.session-menu.entry-settings-keybind-recording")
              color: Color.mOnSecondary
              pointSize: Style.fontSizeS
            }
          }
        }
      }

      // Add button
      Item {
        visible: root.recordingIndex === -1
        width: addBtn.width
        height: root._pillHeight

        NIconButton {
          id: addBtn
          anchors.verticalCenter: parent.verticalCenter
          icon: "plus"
          baseSize: Style.baseWidgetSize * 0.8
          tooltipText: I18n.tr("common.add")
          onClicked: {
            root.recordingIndex = -2;
            keybindInput.forceActiveFocus();
          }
        }
      }

      // Reset button
      Item {
        visible: root.recordingIndex === -1 && root.defaultKeybind !== ""
        width: resetBtn.width
        height: root._pillHeight

        NIconButton {
          id: resetBtn
          anchors.verticalCenter: parent.verticalCenter
          icon: "restore"
          baseSize: Style.baseWidgetSize * 0.8
          tooltipText: I18n.tr("common.reset-to-default")
          onClicked: root.keybindsChanged([root.defaultKeybind])
        }
      }
    }

    // Hidden Item to capture keys
    Item {
      id: keybindInput
      width: 0
      height: 0
      focus: true

      Keys.onPressed: event => {
                        if (root.recordingIndex === -1)
                        return;

                        // Handle Escape specifically to ensure it doesn't close the panel
                        if (event.key === Qt.Key_Escape) {
                          event.accepted = true;
                          root._applyKeybind("Esc");
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
                          root._applyKeybind(keyStr + keyName);
                        }
                        event.accepted = true;
                      }
    }
  }
}
