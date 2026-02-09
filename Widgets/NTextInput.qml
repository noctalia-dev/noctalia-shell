import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property string label: ""
  property string description: ""
  property string inputIconName: ""
  property bool readOnly: false
  property color labelColor: Color.mOnSurface
  property color descriptionColor: Color.mOnSurfaceVariant
  property string fontFamily: Settings.data.ui.fontDefault
  property real fontSize: Style.fontSizeS
  property int fontWeight: Style.fontWeightRegular
  property var defaultValue: undefined
  property string settingsPath: ""
  property real minimumInputWidth: 80 * Style.uiScaleRatio
  property bool showClearButton: true

  property alias text: input.text
  property alias placeholderText: input.placeholderText
  property alias inputMethodHints: input.inputMethodHints
  property alias horizontalAlignment: input.horizontalAlignment
  property alias inputItem: input

  signal editingFinished
  signal accepted

  opacity: enabled ? 1.0 : 0.3
  spacing: Style.marginS

  readonly property bool isValueChanged: (defaultValue !== undefined) && (text !== defaultValue)
  readonly property string indicatorTooltip: defaultValue !== undefined ? I18n.tr("panels.indicator.default-value", {
                                                                                    "value": defaultValue === "" ? "(empty)" : String(defaultValue)
                                                                                  }) : ""

  NLabel {
    label: root.label
    description: root.description
    labelColor: root.labelColor
    descriptionColor: root.descriptionColor
    visible: root.label !== "" || root.description !== ""
    Layout.fillWidth: true
    showIndicator: root.isValueChanged
    indicatorTooltip: root.indicatorTooltip
  }

  // An active control that blocks input, to avoid events leakage and dragging stuff in the background.
  Control {
    id: frameControl

    Layout.fillWidth: true
    Layout.minimumWidth: root.minimumInputWidth
    implicitHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio

    // This is important - makes the control accept focus
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true

    background: Rectangle {
      id: frame

      radius: Style.iRadiusM
      color: Color.mSurface
      border.color: input.activeFocus ? Color.mSecondary : Color.mOutline
      border.width: Style.borderS

      Behavior on border.color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }
    }

    contentItem: Item {
      // Invisible background that captures ALL mouse events
      MouseArea {
        id: backgroundCapture
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        preventStealing: true
        propagateComposedEvents: false

        onPressed: mouse => {
                     mouse.accepted = true;
                     // Focus the input and position cursor
                     input.forceActiveFocus();
                     var inputPos = mapToItem(inputContainer, mouse.x, mouse.y);
                     if (inputPos.x >= 0 && inputPos.x <= inputContainer.width) {
                       var textPos = inputPos.x - Style.marginM;
                       if (textPos >= 0 && textPos <= input.width) {
                         input.cursorPosition = input.positionAt(textPos, input.height / 2);
                       }
                     }
                   }

        onReleased: mouse => {
                      mouse.accepted = true;
                    }
        onDoubleClicked: mouse => {
                           mouse.accepted = true;
                           input.selectAll();
                         }
        onPositionChanged: mouse => {
                             mouse.accepted = true;
                           }
        onWheel: wheel => {
                   wheel.accepted = true;
                 }
      }

      // Container for the actual text field
      Item {
        id: inputContainer
        anchors.fill: parent
        anchors.leftMargin: Style.marginM
        anchors.rightMargin: Style.marginM
        clip: true
        z: 1

        RowLayout {
          anchors.fill: parent
          spacing: 0

          NIcon {
            id: inputIcon
            icon: root.inputIconName

            visible: root.inputIconName !== ""
            enabled: false

            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: visible ? Style.marginS : 0
          }

          TextField {
            id: input

            Layout.fillWidth: true
            Layout.fillHeight: true

            verticalAlignment: TextInput.AlignVCenter

            echoMode: TextInput.Normal
            readOnly: root.readOnly
            placeholderTextColor: Qt.alpha(Color.mOnSurfaceVariant, 0.6)
            color: enabled ? Color.mOnSurface : Qt.alpha(Color.mOnSurface, 0.4)

            selectByMouse: true

            topPadding: 0
            bottomPadding: 0
            leftPadding: 0
            rightPadding: 0

            background: null

            font.family: root.fontFamily
            font.pointSize: root.fontSize * Style.uiScaleRatio
            font.weight: root.fontWeight

            onEditingFinished: root.editingFinished()
            onAccepted: root.accepted()

            // Override mouse handling to prevent propagation
            MouseArea {
              id: textFieldMouse
              anchors.fill: parent
              acceptedButtons: Qt.AllButtons
              preventStealing: true
              propagateComposedEvents: false
              cursorShape: Qt.IBeamCursor

              property int selectionStart: 0

              onPressed: mouse => {
                           mouse.accepted = true;
                           input.forceActiveFocus();
                           var pos = input.positionAt(mouse.x, mouse.y);
                           input.cursorPosition = pos;
                           selectionStart = pos;
                         }

              onPositionChanged: mouse => {
                                   if (mouse.buttons & Qt.LeftButton) {
                                     mouse.accepted = true;
                                     var pos = input.positionAt(mouse.x, mouse.y);
                                     input.select(selectionStart, pos);
                                   }
                                 }

              onDoubleClicked: mouse => {
                                 mouse.accepted = true;
                                 input.selectAll();
                               }

              onReleased: mouse => {
                            mouse.accepted = true;
                          }
              onWheel: wheel => {
                         wheel.accepted = true;
                       }
            }
          }
          NIconButton {
            id: clearButton
            icon: "x"
            tooltipText: (input.text.length > 0 && !root.readOnly && root.enabled) ? I18n.tr("common.clear") : ""

            Layout.alignment: Qt.AlignVCenter
            border.width: 0

            colorBg: "transparent"
            colorBgHover: "transparent"
            colorFg: Color.mOnSurface
            colorFgHover: Color.mError

            visible: root.showClearButton && input.text.length > 0 && !root.readOnly
            enabled: input.text.length > 0 && !root.readOnly && root.enabled

            onClicked: {
              input.clear();
              input.forceActiveFocus();
            }
          }
        }
      }
    }
  }
}
