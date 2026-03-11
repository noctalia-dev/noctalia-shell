import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM
  width: 700

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property string valueClockColor: widgetData.clockColor !== undefined ? widgetData.clockColor : widgetMetadata.clockColor
  property bool valueUseCustomFont: widgetData.useCustomFont !== undefined ? widgetData.useCustomFont : widgetMetadata.useCustomFont
  property string valueCustomFont: widgetData.customFont !== undefined ? widgetData.customFont : widgetMetadata.customFont
  property string valueFormatHorizontal: widgetData.formatHorizontal !== undefined ? widgetData.formatHorizontal : widgetMetadata.formatHorizontal
  property string valueFormatVertical: widgetData.formatVertical !== undefined ? widgetData.formatVertical : widgetMetadata.formatVertical
  property string valueTooltipFormat: widgetData.tooltipFormat !== undefined ? widgetData.tooltipFormat : widgetMetadata.tooltipFormat

  readonly property color textColor: Color.resolveColorKey(valueClockColor)

  // Track the currently focused input field
  property var focusedInput: null
  property int focusedLineIndex: -1

  readonly property var now: Time.now

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.clockColor = valueClockColor;
    settings.useCustomFont = valueUseCustomFont;
    settings.customFont = valueCustomFont;
    settings.formatHorizontal = valueFormatHorizontal.trim();
    settings.formatVertical = valueFormatVertical.trim();
    settings.tooltipFormat = valueTooltipFormat.trim();
    settingsChanged(settings);
  }

  // Function to insert token at cursor position in the focused input
  function insertToken(token) {
    if (!focusedInput || !focusedInput.inputItem) {
      // If no input is focused, default to horiz
      if (inputHoriz.inputItem) {
        inputHoriz.inputItem.focus = true;
        focusedInput = inputHoriz;
      }
    }

    if (focusedInput && focusedInput.inputItem) {
      var input = focusedInput.inputItem;
      var cursorPos = input.cursorPosition;
      var currentText = input.text;

      // Insert token at cursor position
      var newText = currentText.substring(0, cursorPos) + token + currentText.substring(cursorPos);
      input.text = newText + " ";

      // Move cursor after the inserted token
      input.cursorPosition = cursorPos + token.length + 1;

      // Ensure the input keeps focus
      input.focus = true;
    }
  }

  NColorChoice {
    currentKey: valueClockColor
    onSelected: key => {
                  valueClockColor = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.clockColor
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.clock.use-custom-font-label")
    description: I18n.tr("bar.clock.use-custom-font-description")
    checked: valueUseCustomFont
    onToggled: checked => {
                 valueUseCustomFont = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.useCustomFont
  }

  NSearchableComboBox {
    Layout.fillWidth: true
    visible: valueUseCustomFont
    label: I18n.tr("bar.clock.custom-font-label")
    description: I18n.tr("bar.clock.custom-font-description")
    model: FontService.availableFonts
    currentKey: valueCustomFont
    placeholder: I18n.tr("bar.clock.custom-font-placeholder")
    searchPlaceholder: I18n.tr("bar.clock.custom-font-search-placeholder")
    popupHeight: 420
    minimumWidth: 300
    onSelected: function (key) {
      valueCustomFont = key;
      saveSettings();
    }
    defaultValue: Settings.data.ui.fontDefault
  }

  NDivider {
    Layout.fillWidth: true
  }

  NHeader {
    label: I18n.tr("bar.clock.clock-display-label")
    description: I18n.tr("bar.clock.clock-display-description")
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
        label: I18n.tr("bar.clock.horizontal-bar-label")
        description: I18n.tr("bar.clock.horizontal-bar-description")
        placeholderText: "HH:mm ddd, MMM dd"
        text: valueFormatHorizontal
        onTextChanged: valueFormatHorizontal = text
        onEditingFinished: saveSettings()
        Component.onCompleted: {
          if (inputItem) {
            inputItem.onActiveFocusChanged.connect(function () {
              if (inputItem.activeFocus) {
                root.focusedInput = inputHoriz;
              }
            });
          }
        }
        defaultValue: widgetMetadata.formatHorizontal
      }

      Item {
        Layout.fillHeight: true
      }

      NTextInput {
        id: inputVert
        Layout.fillWidth: true
        label: I18n.tr("bar.clock.vertical-bar-label")
        description: I18n.tr("bar.clock.vertical-bar-description")
        // Tokens are Qt format tokens and must not be localized
        placeholderText: "HH mm dd MM"
        text: valueFormatVertical
        onTextChanged: valueFormatVertical = text
        onEditingFinished: saveSettings()
        Component.onCompleted: {
          if (inputItem) {
            inputItem.onActiveFocusChanged.connect(function () {
              if (inputItem.activeFocus) {
                root.focusedInput = inputVert;
              }
            });
          }
        }
        defaultValue: widgetMetadata.formatVertical
      }

      NTextInput {
        id: inputTooltip
        Layout.fillWidth: true
        label: I18n.tr("bar.clock.tooltip-format-label")
        description: I18n.tr("bar.clock.tooltip-format-description")
        placeholderText: "HH:mm, ddd MMM dd"
        text: valueTooltipFormat
        onTextChanged: valueTooltipFormat = text
        onEditingFinished: saveSettings()
        Component.onCompleted: {
          if (inputItem) {
            inputItem.onActiveFocusChanged.connect(function () {
              if (inputItem.activeFocus) {
                root.focusedInput = inputTooltip;
              }
            });
          }
        }
        defaultValue: widgetMetadata.tooltipFormat
      }
    }

    // --------------
    // Preview
    ColumnLayout {
      Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
      Layout.fillWidth: false

      NLabel {
        label: I18n.tr("bar.clock.preview")
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
                color: textColor
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
                color: textColor
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
    Layout.preferredHeight: 300

    // Connect to token clicked signal if NDateTimeTokens provides it
    onTokenClicked: token => root.insertToken(token)
  }
}
