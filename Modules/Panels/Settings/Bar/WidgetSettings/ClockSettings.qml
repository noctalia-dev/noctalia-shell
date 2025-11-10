import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.System

ColumnLayout {
  id: root
  spacing: Style.marginM
  width: 700

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property bool valueUsePrimaryColor: widgetData.usePrimaryColor !== undefined ? widgetData.usePrimaryColor : widgetMetadata.usePrimaryColor
  property bool valueUseCustomFont: widgetData.useCustomFont !== undefined ? widgetData.useCustomFont : widgetMetadata.useCustomFont
  property string valueCustomFont: widgetData.customFont !== undefined ? widgetData.customFont : widgetMetadata.customFont
  property string valueFormatHorizontal: widgetData.formatHorizontal !== undefined ? widgetData.formatHorizontal : widgetMetadata.formatHorizontal
  property string valueFormatVertical: widgetData.formatVertical !== undefined ? widgetData.formatVertical : widgetMetadata.formatVertical

  // Track the currently focused input field
  property var focusedInput: null
  property int focusedLineIndex: -1

  readonly property var now: Time.now

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.usePrimaryColor = valueUsePrimaryColor
    settings.useCustomFont = valueUseCustomFont
    settings.customFont = valueCustomFont
    settings.formatHorizontal = valueFormatHorizontal.trim()
    settings.formatVertical = valueFormatVertical.trim()
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
    label: I18n.tr("bar.widget-settings.clock.use-primary-color.label")
    description: I18n.tr("bar.widget-settings.clock.use-primary-color.description")
    checked: valueUsePrimaryColor
    onToggled: checked => valueUsePrimaryColor = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.clock.use-custom-font.label")
    description: I18n.tr("bar.widget-settings.clock.use-custom-font.description")
    checked: valueUseCustomFont
    onToggled: checked => valueUseCustomFont = checked
  }

  NSearchableComboBox {
    Layout.fillWidth: true
    visible: valueUseCustomFont
    label: I18n.tr("bar.widget-settings.clock.custom-font.label")
    description: I18n.tr("bar.widget-settings.clock.custom-font.description")
    model: FontService.availableFonts
    currentKey: valueCustomFont
    placeholder: I18n.tr("bar.widget-settings.clock.custom-font.placeholder")
    searchPlaceholder: I18n.tr("bar.widget-settings.clock.custom-font.search-placeholder")
    popupHeight: 420
    minimumWidth: 300
    onSelected: function (key) {
      valueCustomFont = key
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NHeader {
    label: I18n.tr("bar.widget-settings.clock.clock-display.label")
    description: I18n.tr("bar.widget-settings.clock.clock-display.description")
  }

  RowLayout {
    id: main

    spacing: Style.marginL
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop

    ColumnLayout {
      spacing: Style.marginM

      Layout.fillWidth: true
      Layout.preferredWidth: 1 // Equal sizing hint
      Layout.alignment: Qt.AlignHCenter | Qt.AlignTop

      NTextInput {
        id: inputHoriz
        Layout.fillWidth: true
        label: I18n.tr("bar.widget-settings.clock.horizontal-bar.label")
        description: I18n.tr("bar.widget-settings.clock.horizontal-bar.description")
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
        label: I18n.tr("bar.widget-settings.clock.vertical-bar.label")
        description: I18n.tr("bar.widget-settings.clock.vertical-bar.description")
        // Tokens are Qt format tokens and must not be localized
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
        label: I18n.tr("bar.widget-settings.clock.preview")
        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
      }

      Rectangle {
        Layout.preferredWidth: 320
        Layout.preferredHeight: 160 // Fixed height instead of fillHeight

        color: Color.mSurfaceVariant
        radius: Style.radiusM
        border.color: Color.mSecondary
        border.width: Style.borderS

        Behavior on border.color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        ColumnLayout {
          spacing: Style.marginM
          anchors.centerIn: parent

          ColumnLayout {
            spacing: -2
            Layout.alignment: Qt.AlignHCenter

            // Horizontal
            Repeater {
              Layout.topMargin: Style.marginM
              model: I18n.locale.toString(now, valueFormatHorizontal.trim()).split("\\n")
              delegate: NText {
                visible: text !== ""
                text: modelData
                family: valueUseCustomFont && valueCustomFont ? valueCustomFont : Settings.data.ui.fontDefault
                pointSize: Style.fontSizeM
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
            spacing: -2
            Layout.alignment: Qt.AlignHCenter

            Repeater {
              Layout.topMargin: Style.marginM
              model: I18n.locale.toString(now, valueFormatVertical.trim()).split(" ")
              delegate: NText {
                visible: text !== ""
                text: modelData
                family: valueUseCustomFont && valueCustomFont ? valueCustomFont : Settings.data.ui.fontDefault
                pointSize: Style.fontSizeM
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
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  NDateTimeTokens {
    Layout.fillWidth: true
    height: 200

    // Connect to token clicked signal if NDateTimeTokens provides it
    onTokenClicked: token => root.insertToken(token)
  }
}
