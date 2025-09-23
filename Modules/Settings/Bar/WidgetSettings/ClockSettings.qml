import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM * scaling
  width: 700 * scaling

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property bool valueUsePrimaryColor: widgetData.usePrimaryColor !== undefined ? widgetData.usePrimaryColor : widgetMetadata.usePrimaryColor
  property bool valueUseMonospacedFont: widgetData.useMonospacedFont !== undefined ? widgetData.useMonospacedFont : widgetMetadata.useMonospacedFont
  property string valueFormatHorizontal: widgetData.formatHorizontal !== undefined ? widgetData.formatHorizontal : widgetMetadata.formatHorizontal
  property string valueFormatVertical: widgetData.formatVertical !== undefined ? widgetData.formatVertical : widgetMetadata.formatVertical
  property int valueFontSize: widgetData.fontSize !== undefined ? widgetData.fontSize : widgetMetadata.fontSize

  // Track the currently focused input field
  property var focusedInput: null
  property int focusedLineIndex: -1

  readonly property var now: Time.date

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.usePrimaryColor = valueUsePrimaryColor
    settings.useMonospacedFont = valueUseMonospacedFont
    settings.formatHorizontal = valueFormatHorizontal.trim()
    settings.formatVertical = valueFormatVertical.trim()
    settings.fontSize = valueFontSize
    return settings
  }

  // Function to insert token at cursor position in the focused input
  function insertToken(token) {
    if (!focusedInput || !focusedInput.inputItem) {
      // If no input is focused, default to horiz
      if (inputHoriz.inputItem) {
        inputHoriz.inputItem.focus = true
        focusedInput = inputHoriz
      }
    }

    if (focusedInput && focusedInput.inputItem) {
      var input = focusedInput.inputItem
      var cursorPos = input.cursorPosition
      var currentText = input.text

      // Insert token at cursor position
      var newText = currentText.substring(0, cursorPos) + token + currentText.substring(cursorPos)
      input.text = newText + " "

      // Move cursor after the inserted token
      input.cursorPosition = cursorPos + token.length + 1

      // Ensure the input keeps focus
      input.focus = true
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: "Use primary color"
    description: "When enabled, this applies the primary color for emphasis."
    checked: valueUsePrimaryColor
    onToggled: checked => valueUsePrimaryColor = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: "Use monospaced font"
    description: "When enabled, the clock will use the monospaced font."
    checked: valueUseMonospacedFont
    onToggled: checked => valueUseMonospacedFont = checked
  }

  NSpinBox {
    label: "Font size"
    description: "Set the base font size for the clock display in points."
    value: valueFontSize
    from: 6
    to: 16
    stepSize: 1
    onValueChanged: valueFontSize = value
  }

  NDivider {
    Layout.fillWidth: true
  }

  NHeader {
    label: "Clock display"
    description: "Customize your clock's display by adding tokens from the list below. To use the 12-hour format, you must include the 'AP' token."
  }

  RowLayout {
    id: main

    spacing: Style.marginL * scaling
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop

    ColumnLayout {
      spacing: Style.marginM * scaling

      Layout.fillWidth: true
      Layout.preferredWidth: 1 // Equal sizing hint
      Layout.alignment: Qt.AlignHCenter | Qt.AlignTop

      NTextInput {
        id: inputHoriz
        Layout.fillWidth: true
        label: "Horizontal bar"
        description: "Tip: Use \\n to create a line break."
        placeholderText: "HH:mm ddd, MMM dd"
        text: valueFormatHorizontal
        onTextChanged: valueFormatHorizontal = text
        Component.onCompleted: {
          if (inputItem) {
            inputItem.onActiveFocusChanged.connect(function () {
              if (inputItem.activeFocus) {
                root.focusedInput = inputHoriz
              }
            })
          }
        }
      }

      Item {
        Layout.fillHeight: true
      }

      NTextInput {
        id: inputVert
        Layout.fillWidth: true
        label: "Vertical bar"
        description: "Use a space to separate each part onto a new line."
        placeholderText: "HH mm dd MM"
        text: valueFormatVertical
        onTextChanged: valueFormatVertical = text
        Component.onCompleted: {
          if (inputItem) {
            inputItem.onActiveFocusChanged.connect(function () {
              if (inputItem.activeFocus) {
                root.focusedInput = inputVert
              }
            })
          }
        }
      }
    }

    // --------------
    // Preview
    ColumnLayout {
      Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
      Layout.fillWidth: false

      NLabel {
        label: "Preview"
        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
      }

      Rectangle {
        Layout.preferredWidth: 420 * scaling
        Layout.preferredHeight: 220 * scaling // Increased height for larger font sizes

        color: Color.mSurfaceVariant
        radius: Style.radiusM * scaling
        border.color: Color.mSecondary
        border.width: Math.max(1, Style.borderS * scaling)

        Behavior on border.color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        ColumnLayout {
          spacing: Style.marginM * scaling
          anchors.centerIn: parent

          ColumnLayout {
            spacing: -2 * scaling
            Layout.alignment: Qt.AlignHCenter

            // Horizontal
            Repeater {
              Layout.topMargin: Style.marginM * scaling
              model: Qt.formatDateTime(now, valueFormatHorizontal.trim()).split("\\n")
              delegate: NText {
                visible: text !== ""
                text: modelData
                font.family: valueUseMonospacedFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault
                font.pointSize: valueFontSize * scaling
                font.weight: Style.fontWeightBold
                color: valueUsePrimaryColor ? Color.mPrimary : Color.mOnSurface
                wrapMode: Text.WordWrap
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }
              }
            }
          }

          NDivider {
            Layout.fillWidth: true
          }

          // Vertical
          ColumnLayout {
            spacing: -2 * scaling
            Layout.alignment: Qt.AlignHCenter

            Repeater {
              Layout.topMargin: Style.marginM * scaling
              model: Qt.formatDateTime(now, valueFormatVertical.trim()).split(" ")
              delegate: NText {
                visible: text !== ""
                text: modelData
                font.family: valueUseMonospacedFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault
                font.pointSize: valueFontSize * scaling
                font.weight: Style.fontWeightBold
                color: valueUsePrimaryColor ? Color.mPrimary : Color.mOnSurface
                wrapMode: Text.WordWrap
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  NDivider {
    Layout.topMargin: Style.marginM * scaling
    Layout.bottomMargin: Style.marginM * scaling
  }

  NDateTimeTokens {
    Layout.fillWidth: true
    height: 200 * scaling

    // Connect to token clicked signal if NDateTimeTokens provides it
    onTokenClicked: token => root.insertToken(token)
  }
}
