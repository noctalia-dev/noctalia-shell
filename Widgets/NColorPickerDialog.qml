import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Helpers/ColorList.js" as ColorList
import qs.Commons
import qs.Services.UI
import qs.Widgets

NPopup {
  id: root

  property var screen
  property color selectedColor: "black"

  enum EditMode {
    R,
    G,
    B,
    H,
    S,
    V
  }
  property int editMode: NColorPickerDialog.EditMode.R

  // Code to deal with Hue when color is achromatic
  property real stableHue: 0
  onSelectedColorChanged: {
    if (selectedColor.hsvHue >= 0) {
      stableHue = selectedColor.hsvHue;
    }
    if (liveMode && visible) {
      colorSelected(selectedColor);
    }
  }
  readonly property real displayHue: selectedColor.hsvHue < 0 ? stableHue : selectedColor.hsvHue

  signal colorSelected(color color)

  // When true: hides Cancel/Apply, emits colorSelected on every color change
  property bool liveMode: false

  width: 580
  padding: Style.marginXL

  modal: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  onOpened: {
    // Center on screen after popup is opened and parent position is known
    if (screen && parent) {
      var parentPos = parent.mapToItem(null, 0, 0);
      x = Math.round((screen.width - width) / 2 - parentPos.x);
      y = Math.round((screen.height - height) / 2 - parentPos.y);
    }
  }

  background: Rectangle {
    color: Color.mSurface
    radius: Style.iRadiusS
    border.color: Color.mPrimary
    border.width: Style.borderM
  }

  contentItem: ColumnLayout {
    id: mainContent
    spacing: Style.marginL

    // Header
    RowLayout {
      Layout.fillWidth: true

      RowLayout {
        spacing: Style.marginS

        NIcon {
          icon: "color-picker"
          pointSize: Style.fontSizeXXL
          color: Color.mPrimary
        }

        NText {
          text: I18n.tr("widgets.color-picker.title")
          pointSize: Style.fontSizeXL
          font.weight: Style.fontWeightBold
          color: Color.mPrimary
        }
      }

      Item {
        Layout.fillWidth: true
      }

      NIconButton {
        icon: "close"
        onClicked: root.close()
      }
    }

    // Color preview section
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 80
      radius: Style.iRadiusS
      color: root.selectedColor
      border.color: Color.mOutline
      border.width: Style.borderS

      ColumnLayout {
        spacing: 0
        anchors.fill: parent

        Item {
          Layout.fillHeight: true
        }

        NText {
          text: root.selectedColor.toString().toUpperCase()
          family: Settings.data.ui.fontFixed
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightMedium
          color: root.selectedColor.r + root.selectedColor.g + root.selectedColor.b > 1.5 ? "black" : "white"
          Layout.alignment: Qt.AlignHCenter
        }

        NText {
          text: "RGB(" + Math.round(root.selectedColor.r * 255) + ", " + Math.round(root.selectedColor.g * 255) + ", " + Math.round(root.selectedColor.b * 255) + ")"
          family: Settings.data.ui.fontFixed
          pointSize: Style.fontSizeM
          color: root.selectedColor.r + root.selectedColor.g + root.selectedColor.b > 1.5 ? "black" : "white"
          Layout.alignment: Qt.AlignHCenter
        }

        Item {
          Layout.fillHeight: true
        }
      }
    }

    // Main Box
    NBox {
      Layout.fillWidth: true
      Layout.preferredHeight: controlsOutterColumn.implicitHeight + Style.margin2L

      ButtonGroup {
        id: colorValues
      }

      ColumnLayout {
        id: controlsOutterColumn
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        RowLayout {
          spacing: Style.marginL // Ensure nice gap between Left and Right groups

          // SpinBoxes Column
          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 3

            // --- RED ---
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM

              NRadioButton {
                ButtonGroup.group: colorValues
                text: "R"
                font.weight: Style.fontWeightMedium
                checked: true
                onClicked: root.editMode = NColorPickerDialog.EditMode.R
                Layout.fillWidth: false
              }

              NSpinBox {
                id: redSpinBox
                from: 0
                to: 255

                onValueChanged: {
                  if (!selectedSlider.pressed && !fieldMouse.pressed && !hexInput.activeFocus && value !== Math.round(root.selectedColor.r * 255)) {
                    root.selectedColor = Qt.rgba(value / 255, root.selectedColor.g, root.selectedColor.b, 1);
                  }
                }
                Binding {
                  target: redSpinBox
                  property: "value"
                  value: Math.round(root.selectedColor.r * 255)
                }
              }
            }

            // --- GREEN ---
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM

              NRadioButton {
                ButtonGroup.group: colorValues
                text: "G"
                font.weight: Style.fontWeightMedium
                onClicked: root.editMode = NColorPickerDialog.EditMode.G
                Layout.fillWidth: false
              }

              NSpinBox {
                id: greenSpinBox
                from: 0
                to: 255

                onValueChanged: {
                  if (!selectedSlider.pressed && !fieldMouse.pressed && !hexInput.activeFocus && value !== Math.round(root.selectedColor.g * 255)) {
                    root.selectedColor = Qt.rgba(root.selectedColor.r, value / 255, root.selectedColor.b, 1);
                  }
                }
                Binding {
                  target: greenSpinBox
                  property: "value"
                  value: Math.round(root.selectedColor.g * 255)
                }
              }
            }

            // --- BLUE ---
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM

              NRadioButton {
                ButtonGroup.group: colorValues
                text: "B"
                font.weight: Style.fontWeightMedium
                onClicked: root.editMode = NColorPickerDialog.EditMode.B
                Layout.fillWidth: false
              }

              NSpinBox {
                id: blueSpinBox
                from: 0
                to: 255

                onValueChanged: {
                  if (!selectedSlider.pressed && !fieldMouse.pressed && !hexInput.activeFocus && value !== Math.round(root.selectedColor.b * 255)) {
                    root.selectedColor = Qt.rgba(root.selectedColor.r, root.selectedColor.g, value / 255, 1);
                  }
                }
                Binding {
                  target: blueSpinBox
                  property: "value"
                  value: Math.round(root.selectedColor.b * 255)
                }
              }
            }

            // Spacer
            Item {
              Layout.fillHeight: true
              Layout.fillWidth: true
            }

            // --- HUE ---
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM

              NRadioButton {
                ButtonGroup.group: colorValues
                text: "H"
                font.weight: Style.fontWeightMedium
                checked: true
                onClicked: root.editMode = NColorPickerDialog.EditMode.H
                Layout.fillWidth: false
              }

              NSpinBox {
                id: hueSpinBox
                from: 0
                to: 360

                onValueChanged: {
                  if (!selectedSlider.pressed && !fieldMouse.pressed && !hexInput.activeFocus && value !== Math.round(root.displayHue * 360)) {
                    var newHue = value / 360;
                    root.selectedColor = Qt.hsva(newHue, root.selectedColor.hsvSaturation, root.selectedColor.hsvValue, 1);
                    root.stableHue = newHue;
                  }
                }

                Binding {
                  target: hueSpinBox
                  property: "value"
                  value: Math.round(root.displayHue * 360)
                }
              }
            }

            // --- SATURATION ---
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM

              NRadioButton {
                ButtonGroup.group: colorValues
                text: "S"
                font.weight: Style.fontWeightMedium
                onClicked: root.editMode = NColorPickerDialog.EditMode.S
                Layout.fillWidth: false
              }

              NSpinBox {
                id: satSpinBox
                from: 0
                to: 100

                onValueChanged: {
                  if (!selectedSlider.pressed && !fieldMouse.pressed && !hexInput.activeFocus && value !== Math.round(root.selectedColor.hsvSaturation * 100)) {
                    root.selectedColor = Qt.hsva(root.selectedColor.hsvHue, value / 100, root.selectedColor.hsvValue, 1);
                  }
                }
                Binding {
                  target: satSpinBox
                  property: "value"
                  value: Math.round(root.selectedColor.hsvSaturation * 100)
                }
              }
            }

            // --- VALUE ---
            RowLayout {
              spacing: Style.marginM

              NRadioButton {
                ButtonGroup.group: colorValues
                text: "V"
                font.weight: Style.fontWeightMedium
                onClicked: root.editMode = NColorPickerDialog.EditMode.V
                Layout.fillWidth: false
              }

              NSpinBox {
                id: valSpinBox
                from: 0
                to: 100

                onValueChanged: {
                  if (!selectedSlider.pressed && !fieldMouse.pressed && !hexInput.activeFocus && value !== Math.round(root.selectedColor.hsvValue * 100)) {
                    root.selectedColor = Qt.hsva(root.selectedColor.hsvHue, root.selectedColor.hsvSaturation, value / 100, 1);
                  }
                }
                Binding {
                  target: valSpinBox
                  property: "value"
                  value: Math.round(root.selectedColor.hsvValue * 100)
                }
              }
            }

            // Spacer
            Item {
              Layout.fillHeight: true
              Layout.fillWidth: true
            }

            // Hex input
            RowLayout {
              id: hexInput
              Layout.fillWidth: true
              spacing: Style.marginM

              NLabel {
                label: "Hex:"
                Layout.alignment: Qt.AlignVCenter
              }

              NTextInput {
                text: root.selectedColor.toString().toUpperCase()
                fontFamily: Settings.data.ui.fontFixed
                Layout.fillWidth: true
                Layout.minimumWidth: implicitWidth
                onEditingFinished: {
                  if (/^#[0-9A-F]{6}$/i.test(text)) {
                    root.selectedColor = text;
                  }
                }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 5
            Layout.alignment: Qt.AlignTop
            spacing: Style.marginS

            Layout.topMargin: Math.round(2 * Style.uiScaleRatio) //Shim to try and line up colorField with SpinBoxes

            // --- SLIDER ---
            NColorSlider {
              id: selectedSlider
              Layout.fillHeight: true
              rainbowMode: root.editMode === NColorPickerDialog.EditMode.H
              topColor: {
                if (rainbowMode)
                  return "transparent";
                switch (root.editMode) {
                case NColorPickerDialog.EditMode.R:
                  return "#FF0000";
                case NColorPickerDialog.EditMode.G:
                  return "#00FF00";
                case NColorPickerDialog.EditMode.B:
                  return "#0000FF";
                default:
                  return "#FFFFFF";
                }
              }

              Binding {
                target: selectedSlider
                property: "value"
                when: !selectedSlider.pressed // Only update from model when NOT dragging
                value: {
                  switch (root.editMode) {
                  case NColorPickerDialog.EditMode.R:
                    return root.selectedColor.r;
                  case NColorPickerDialog.EditMode.G:
                    return root.selectedColor.g;
                  case NColorPickerDialog.EditMode.B:
                    return root.selectedColor.b;
                  case NColorPickerDialog.EditMode.H:
                    return root.displayHue;
                  case NColorPickerDialog.EditMode.S:
                    return root.selectedColor.hsvSaturation;
                  case NColorPickerDialog.EditMode.V:
                    return root.selectedColor.hsvValue;
                  default:
                    return 0;
                  }
                }
              }

              onMoved: {
                var v = value;
                switch (root.editMode) {
                case NColorPickerDialog.EditMode.R:
                  root.selectedColor = Qt.rgba(v, root.selectedColor.g, root.selectedColor.b, 1);
                  break;
                case NColorPickerDialog.EditMode.G:
                  root.selectedColor = Qt.rgba(root.selectedColor.r, v, root.selectedColor.b, 1);
                  break;
                case NColorPickerDialog.EditMode.B:
                  root.selectedColor = Qt.rgba(root.selectedColor.r, root.selectedColor.g, v, 1);
                  break;
                case NColorPickerDialog.EditMode.H:
                  root.selectedColor = Qt.hsva(v, root.selectedColor.hsvSaturation, root.selectedColor.hsvValue, 1);
                  root.stableHue = v;
                  break;
                case NColorPickerDialog.EditMode.S:
                  root.selectedColor = Qt.hsva(root.selectedColor.hsvHue, v, root.selectedColor.hsvValue, 1);
                  break;
                case NColorPickerDialog.EditMode.V:
                  root.selectedColor = Qt.hsva(root.selectedColor.hsvHue, root.selectedColor.hsvSaturation, v, 1);
                  break;
                }
              }
            }

            // Color Field
            Rectangle {
              id: colorField
              Layout.fillWidth: true

              Layout.preferredHeight: width
              Layout.alignment: Qt.AlignTop

              radius: 0
              border.color: Color.mOutline
              border.width: Style.borderS
              clip: true

              ShaderEffect {
                anchors.fill: parent
                anchors.margins: 1 // Avoid drawing over the border

                fragmentShader: "../Shaders/qsb/color_picker.frag.qsb"

                // Pass which radio is selected
                readonly property real fixedVal: {
                  switch (root.editMode) {
                  case NColorPickerDialog.EditMode.R:
                    return root.selectedColor.r;
                  case NColorPickerDialog.EditMode.G:
                    return root.selectedColor.g;
                  case NColorPickerDialog.EditMode.B:
                    return root.selectedColor.b;
                  case NColorPickerDialog.EditMode.H:
                    return root.displayHue;
                  case NColorPickerDialog.EditMode.S:
                    return root.selectedColor.hsvSaturation;
                  case NColorPickerDialog.EditMode.V:
                    return root.selectedColor.hsvValue;
                  default:
                    return 0;
                  }
                }

                // Send as one vector because GPUs are so damn picky
                property vector4d params: Qt.vector4d(1.0, fixedVal, root.editMode, 0)
              }

              MouseArea {
                id: fieldMouse
                anchors.fill: parent
                cursorShape: Qt.CrossCursor

                // Update color when clicking or dragging
                function updateColor(mouse) {
                  // Normalize X and Y (0.0 to 1.0)
                  var xVal = Math.max(0, Math.min(1, mouse.x / width));
                  var yVal = Math.max(0, Math.min(1, 1.0 - (mouse.y / height))); // Flip Y (0 at bottom)

                  // Get the current fixed value (from the slider)
                  var fixed = 0.0;

                  switch (root.editMode) {
                  case NColorPickerDialog.EditMode.R:
                    fixed = root.selectedColor.r;
                    root.selectedColor = Qt.rgba(fixed, xVal, yVal, 1);
                    break;
                  case NColorPickerDialog.EditMode.G:
                    fixed = root.selectedColor.g;
                    root.selectedColor = Qt.rgba(xVal, fixed, yVal, 1);
                    break;
                  case NColorPickerDialog.EditMode.B:
                    fixed = root.selectedColor.b;
                    root.selectedColor = Qt.rgba(xVal, yVal, fixed, 1);
                    break;
                  case NColorPickerDialog.EditMode.H:
                    // Use stableHue to prevent flipping to -1
                    fixed = root.displayHue;
                    root.selectedColor = Qt.hsva(fixed, xVal, yVal, 1);
                    root.stableHue = fixed;
                    break;
                  case NColorPickerDialog.EditMode.S:
                    fixed = root.selectedColor.hsvSaturation;
                    root.selectedColor = Qt.hsva(xVal, fixed, yVal, 1);
                    // If we dragged Hue (xVal), update stableHue
                    root.stableHue = yVal;
                    break;
                  case NColorPickerDialog.EditMode.V:
                    fixed = root.selectedColor.hsvValue;
                    root.selectedColor = Qt.hsva(xVal, yVal, fixed, 1);
                    // If we dragged Hue (xVal), update stableHue
                    root.stableHue = xVal;
                    break;
                  }
                }
                onPressed: mouse => updateColor(mouse)
                onPositionChanged: mouse => updateColor(mouse)
              }

              // Color Indicator
              Rectangle {
                width: 10
                height: 10
                radius: Math.min(Style.iRadiusXS, width / 2)
                color: "transparent"
                border.color: root.selectedColor.hsvValue < 0.5 ? "white" : "black"
                border.width: 1

                // Find position based on the current color
                readonly property point selectedPos: {
                  switch (root.editMode) {
                  case NColorPickerDialog.EditMode.R:
                    return Qt.point(root.selectedColor.g, root.selectedColor.b);
                  case NColorPickerDialog.EditMode.G:
                    return Qt.point(root.selectedColor.r, root.selectedColor.b);
                  case NColorPickerDialog.EditMode.B:
                    return Qt.point(root.selectedColor.r, root.selectedColor.g);
                  case NColorPickerDialog.EditMode.H:
                    return Qt.point(root.selectedColor.hsvSaturation, root.selectedColor.hsvValue);
                  case NColorPickerDialog.EditMode.S:
                    return Qt.point(root.displayHue, root.selectedColor.hsvValue);
                  case NColorPickerDialog.EditMode.V:
                    return Qt.point(root.displayHue, root.selectedColor.hsvSaturation);
                  default:
                    return Qt.point(0, 0);
                  }
                }

                // Convert values to pixel position
                x: (selectedPos.x * parent.width) - width / 2
                y: ((1.0 - selectedPos.y) * parent.height) - height / 2
              }

              // Redraw the border in case Color Indicator is near the edge
              Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Color.mOutline
                border.width: Style.borderS
                antialiasing: false
              }
            }
          }
        }

        NLabel {
          label: I18n.tr("widgets.color-picker.palette-label")
          Layout.fillWidth: true
        }

        NScrollView {
          id: paletteScrollView
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(paletteGrid.implicitHeight, 200)
          verticalPolicy: paletteGrid.implicitHeight > 200 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          horizontalPolicy: ScrollBar.AlwaysOff

          GridLayout {
            id: paletteGrid
            width: paletteScrollView.availableWidth
            columns: 17
            columnSpacing: 6
            rowSpacing: 6

            NLabel {
              Layout.columnSpan: 17
              Layout.fillWidth: true
              description: I18n.tr("widgets.color-picker.palette-theme-colors")
            }

            Repeater {
              model: [
                {
                  name: "mPrimary",
                  color: Color.mPrimary
                },
                {
                  name: "mSecondary",
                  color: Color.mSecondary
                },
                {
                  name: "mTertiary",
                  color: Color.mTertiary
                },
                {
                  name: "mError",
                  color: Color.mError
                },
                {
                  name: "mSurface",
                  color: Color.mSurface
                },
                {
                  name: "mSurfaceVariant",
                  color: Color.mSurfaceVariant
                },
                {
                  name: "mOutline",
                  color: Color.mOutline
                }
              ]

              Rectangle {
                width: 24
                height: 24
                radius: Style.iRadiusXXS
                color: modelData.color
                border.color: root.selectedColor.toString() === modelData.color.toString() ? Color.mPrimary : Color.mOutline
                border.width: Math.max(1, root.selectedColor.toString() === modelData.color.toString() ? Style.borderM : Style.borderS)

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  hoverEnabled: true

                  onEntered: {
                    TooltipService.show(parent, modelData.name + "\n" + parent.color.toString().toUpperCase());
                  }
                  onExited: {
                    TooltipService.hide();
                  }
                  onClicked: {
                    root.selectedColor = modelData.color;
                    TooltipService.hide();
                  }
                }
              }
            }

            NDivider {
              Layout.columnSpan: 17
              Layout.fillWidth: true
              Layout.topMargin: Style.marginXS
              Layout.bottomMargin: 0
            }

            NLabel {
              Layout.columnSpan: 17
              Layout.fillWidth: true
              description: I18n.tr("widgets.color-picker.palette-description")
            }

            Repeater {
              model: ColorList.colors

              Rectangle {
                width: 24
                height: 24
                radius: Math.min(Style.iRadiusXS, width / 2)
                color: modelData.color
                border.color: root.selectedColor.toString() === modelData.color.toString() ? Color.mPrimary : Color.mOutline
                border.width: root.selectedColor.toString() === modelData.color.toString() ? 2 : 1

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  hoverEnabled: true

                  onEntered: {
                    TooltipService.show(parent, modelData.name + "\n" + parent.color.toString().toUpperCase(), "auto");
                  }
                  onExited: {
                    TooltipService.hide();
                  }
                  onClicked: {
                    root.selectedColor = modelData.color;
                    TooltipService.hide();
                  }
                }
              }
            }
          }
        }
      }
    }

    RowLayout {
      visible: !root.liveMode
      Layout.fillWidth: true
      Layout.topMargin: 1
      Layout.bottomMargin: 1
      spacing: 10

      Item {
        Layout.fillWidth: true
      }

      NButton {
        id: cancelButton
        text: I18n.tr("common.cancel")
        outlined: cancelButton.hovered ? false : true
        onClicked: {
          root.close();
        }
      }

      NButton {
        text: I18n.tr("common.apply")
        icon: "check"
        onClicked: {
          root.colorSelected(root.selectedColor);
          // Delay close to prevent click propagation to elements behind the dialog
          Qt.callLater(() => {
                         root.close();
                       });
        }
      }
    }
  }
}
