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
  property string settingsPath: ""

  property int maxKeybinds: 2
  signal keybindsChanged(var newKeybinds)

  implicitHeight: contentLayout.implicitHeight

  // -1 = not recording, >= 0 = re-recording at index, -2 = adding new
  property int recordingIndex: -1
  property bool hasConflict: false

  onRecordingIndexChanged: {
    PanelService.isKeybindRecording = recordingIndex !== -1;
    if (recordingIndex !== -1) {
      hasConflict = false;
    }
  }

  readonly property real _pillHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio

  function _applyKeybind(keyStr) {
    if (!keyStr)
      return;

    // 1. Internal duplicate check (same action)
    for (let i = 0; i < root.currentKeybinds.length; i++) {
      if (i !== root.recordingIndex && String(root.currentKeybinds[i]).toLowerCase() === keyStr.toLowerCase()) {
        hasConflict = true;
        ToastService.showWarning(I18n.tr("panels.general.keybinds-conflict-title"), I18n.tr("panels.general.keybinds-conflict-description", {
                                                                                              "action": root.label || "This action"
                                                                                            }));
        conflictTimer.restart();
        return;
      }
    }

    // 2. External conflict check (other actions)
    const conflict = Keybinds.getKeybindConflict(keyStr, root.settingsPath, Settings.data);
    if (conflict) {
      hasConflict = true;
      ToastService.showWarning(I18n.tr("panels.general.keybinds-conflict-title"), I18n.tr("panels.general.keybinds-conflict-description", {
                                                                                            "action": conflict
                                                                                          }));
      conflictTimer.restart();
      return;
    }

    var newKeybinds = Array.from(root.currentKeybinds);
    if (recordingIndex >= 0) {
      newKeybinds[recordingIndex] = keyStr;
    }
    // Ensure array is dense and limited to maxKeybinds
    newKeybinds = newKeybinds.filter(k => k !== undefined && k !== "").slice(0, root.maxKeybinds);
    recordingIndex = -1;
    root.keybindsChanged(newKeybinds);
  }

  Timer {
    id: conflictTimer
    interval: 2000
    onTriggered: {
      hasConflict = false;
      recordingIndex = -1;
    }
  }

  RowLayout {
    id: contentLayout
    width: parent.width
    spacing: Style.marginL

    // Label and Description (optional)
    NLabel {
      id: labelContainer
      label: root.label
      description: root.description
      labelColor: root.labelColor
      descriptionColor: root.descriptionColor
      visible: label !== "" || description !== ""
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
    }

    RowLayout {
      id: slotsRow
      spacing: Style.marginS
      Layout.alignment: Qt.AlignVCenter | (labelContainer.visible ? Qt.AlignRight : Qt.AlignLeft)

      Repeater {
        model: root.maxKeybinds
        delegate: MouseArea {
          id: slotArea
          width: Math.round(180 * Style.uiScaleRatio)
          height: root._pillHeight
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor

          readonly property bool isOccupied: index < root.currentKeybinds.length
          readonly property bool isRecordingThis: root.recordingIndex === index
          readonly property string keybindText: isRecordingThis ? I18n.tr("placeholders.keybind-recording") : (isOccupied ? root.currentKeybinds[index] : I18n.tr("placeholders.add-new-keybind"))

          onClicked: {
            if (isRecordingThis) {
              root.recordingIndex = -1;
            } else {
              root.recordingIndex = index;
              keybindInput.forceActiveFocus();
            }
          }

          Rectangle {
            id: slotBg
            anchors.fill: parent
            radius: Style.iRadiusS
            color: root.hasConflict && slotArea.isRecordingThis ? Color.mError : (slotArea.isRecordingThis ? Color.mSecondary : (slotArea.containsMouse ? Qt.alpha(Color.mSecondary, 0.15) : Color.mSurface))
            border.color: root.hasConflict && slotArea.isRecordingThis ? Color.mError : (slotArea.isRecordingThis ? Color.mPrimary : (slotArea.containsMouse ? Color.mSecondary : Color.mOutline))
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
              anchors.rightMargin: Style.marginS
              spacing: Style.marginXS

              NIcon {
                icon: root.hasConflict && slotArea.isRecordingThis ? "alert-circle" : (slotArea.isRecordingThis ? "circle-dot" : "keyboard")
                color: slotArea.isRecordingThis ? Color.mOnSecondary : (slotArea.isOccupied ? Color.mOnSurfaceVariant : Qt.alpha(Color.mOnSurfaceVariant, 0.4))
                opacity: 0.8
                visible: !slotArea.isRecordingThis || root.hasConflict
              }

              NText {
                Layout.fillWidth: true
                text: slotArea.keybindText
                color: slotArea.isRecordingThis ? Color.mOnSecondary : (slotArea.isOccupied ? Color.mOnSurface : Color.mOnSurfaceVariant)
                font.family: slotArea.isOccupied && !slotArea.isRecordingThis ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault
                font.pointSize: slotArea.isOccupied ? Style.fontSizeM : Style.fontSizeS
                font.weight: slotArea.isOccupied ? Style.fontWeightBold : Style.fontWeightRegular
                elide: Text.ElideRight
                opacity: slotArea.isOccupied || slotArea.isRecordingThis ? 1.0 : 0.6
              }

              Item {
                Layout.preferredWidth: Math.round(root._pillHeight * 0.7)
                Layout.fillHeight: true
                visible: slotArea.isOccupied && root.recordingIndex === -1

                NIconButton {
                  anchors.centerIn: parent
                  visible: root.recordingIndex === -1 && (root.currentKeybinds.length > 1 || root.allowEmpty)
                  icon: "x"
                  colorBg: "transparent"
                  colorBgHover: Qt.alpha(Color.mError, 0.1)
                  colorFg: Color.mOnSurfaceVariant
                  colorFgHover: Color.mError
                  border.width: 0
                  baseSize: Style.baseWidgetSize * 0.7
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
      }
    }

    // Hidden Item to capture keys
    Item {
      id: keybindInput
      width: 0
      height: 0
      focus: true

      Keys.onPressed: event => {
                        if (root.recordingIndex === -1 || root.hasConflict)
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
                        } else if (rawText && rawText.length > 0 && rawText.charCodeAt(0) > 31 && rawText.charCodeAt(0) !== 127) {
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
                          // Enforce modifier requirement (Ctrl or Alt) for "normal" keys
                          // Allow Arrows, Nav, Function, and System keys without modifiers
                          const isSpecialKey = (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35) || (event.key >= Qt.Key_Left && event.key <= Qt.Key_Down) || (event.key === Qt.Key_Home || event.key === Qt.Key_End || event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) || (event.key === Qt.Key_Insert || event.key === Qt.Key_Delete || event.key
                                                                                                                                                                                                                                                                                            === Qt.Key_Backspace) || (event.key === Qt.Key_Tab || event.key
                                                                                                                                                                                                                                                                                                                      === Qt.Key_Return || event.key === Qt.Key_Enter
                                                                                                                                                                                                                                                                                                                      || event.key === Qt.Key_Escape || event.key
                                                                                                                                                                                                                                                                                                                      === Qt.Key_Space);

                          const hasModifier = (event.modifiers & Qt.ControlModifier) || (event.modifiers & Qt.AltModifier);

                          if (!hasModifier && !isSpecialKey) {
                            hasConflict = true;
                            ToastService.showWarning(I18n.tr("panels.general.keybinds-modifier-title"), I18n.tr("panels.general.keybinds-modifier-description"));
                            conflictTimer.restart();
                            return;
                          }

                          root._applyKeybind(keyStr + keyName);
                        }
                        event.accepted = true;
                      }
    }
  }
}
