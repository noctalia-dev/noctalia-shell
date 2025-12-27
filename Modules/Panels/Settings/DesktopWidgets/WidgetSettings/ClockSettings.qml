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

  property var widgetData: null
  property var widgetMetadata: null

  property bool valueShowBackground: widgetData.showBackground !== undefined ? widgetData.showBackground : widgetMetadata.showBackground
  property string valueClockStyle: widgetData.clockStyle !== undefined ? widgetData.clockStyle : widgetMetadata.clockStyle
  property bool valueUsePrimaryColor: widgetData.usePrimaryColor !== undefined ? widgetData.usePrimaryColor : widgetMetadata.usePrimaryColor
  property bool valueUseCustomFont: widgetData.useCustomFont !== undefined ? widgetData.useCustomFont : widgetMetadata.useCustomFont
  property string valueCustomFont: widgetData.customFont !== undefined ? widgetData.customFont : ""
  property string valueFormat: widgetData.format !== undefined ? widgetData.format : widgetMetadata.format

  // Track the currently focused input field
  property var focusedInput: null

  readonly property bool isMinimalMode: valueClockStyle === "minimal"
  readonly property var now: Time.now

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showBackground = valueShowBackground;
    settings.clockStyle = valueClockStyle;
    settings.usePrimaryColor = valueUsePrimaryColor;
    settings.useCustomFont = valueUseCustomFont;
    settings.customFont = valueCustomFont;
    settings.format = valueFormat.trim();
    return settings;
  }

  // Function to insert token at cursor position in the focused input
  function insertToken(token) {
    if (!focusedInput || !focusedInput.inputItem) {
      // If no input is focused, default to format input
      if (formatInput.inputItem) {
        formatInput.inputItem.focus = true;
        focusedInput = formatInput;
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

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.clock.style.label")
    description: I18n.tr("settings.desktop-widgets.clock.style.description")
    currentKey: valueClockStyle
    minimumWidth: 260 * Style.uiScaleRatio
    model: [
      {
        "key": "minimal",
        "name": I18n.tr("settings.desktop-widgets.clock.style.minimal")
      },
      {
        "key": "digital",
        "name": I18n.tr("settings.desktop-widgets.clock.style.digital")
      },
      {
        "key": "analog",
        "name": I18n.tr("settings.desktop-widgets.clock.style.analog")
      },
      {
        "key": "binary",
        "name": I18n.tr("settings.desktop-widgets.clock.style.binary")
      }
    ]
    onSelected: key => valueClockStyle = key
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.clock.use-primary-color.label")
    description: I18n.tr("settings.desktop-widgets.clock.use-primary-color.description")
    checked: valueUsePrimaryColor
    onToggled: checked => valueUsePrimaryColor = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.clock.use-custom-font.label")
    description: I18n.tr("settings.desktop-widgets.clock.use-custom-font.description")
    checked: valueUseCustomFont
    onToggled: checked => valueUseCustomFont = checked
  }

  NSearchableComboBox {
    Layout.fillWidth: true
    visible: valueUseCustomFont
    label: I18n.tr("settings.desktop-widgets.clock.custom-font.label")
    description: I18n.tr("settings.desktop-widgets.clock.custom-font.description")
    model: FontService.availableFonts
    currentKey: valueCustomFont
    placeholder: I18n.tr("settings.desktop-widgets.clock.custom-font.placeholder")
    searchPlaceholder: I18n.tr("settings.desktop-widgets.clock.custom-font.search-placeholder")
    popupHeight: 420
    minimumWidth: 300
    onSelected: function (key) {
      valueCustomFont = key;
    }
  }

  NDivider {
    Layout.fillWidth: true
    visible: isMinimalMode
  }

  NHeader {
    visible: isMinimalMode
    label: I18n.tr("settings.desktop-widgets.clock.clock-display.label")
    description: I18n.tr("settings.desktop-widgets.clock.clock-display.description")
  }

  // Format editor - only visible in minimal mode
  RowLayout {
    id: main
    visible: isMinimalMode
    spacing: Style.marginL
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop

    ColumnLayout {
      spacing: Style.marginM
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      Layout.alignment: Qt.AlignHCenter | Qt.AlignTop

      NTextInput {
        id: formatInput
        Layout.fillWidth: true
        label: I18n.tr("settings.desktop-widgets.clock.format.label")
        description: I18n.tr("settings.desktop-widgets.clock.format.description")
        placeholderText: "HH:mm\\nd MMMM yyyy"
        text: valueFormat
        onTextChanged: valueFormat = text
        Component.onCompleted: {
          if (inputItem) {
            inputItem.onActiveFocusChanged.connect(function () {
              if (inputItem.activeFocus) {
                root.focusedInput = formatInput;
              }
            });
          }
        }
      }
    }

    // Preview
    ColumnLayout {
      Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
      Layout.fillWidth: false

      NLabel {
        label: I18n.tr("settings.desktop-widgets.clock.preview")
        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
      }

      Rectangle {
        Layout.preferredWidth: 320
        Layout.preferredHeight: 160
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

            Repeater {
              Layout.topMargin: Style.marginM
              model: I18n.locale.toString(now, valueFormat.trim()).split("\\n")
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
    visible: isMinimalMode
  }

  NDateTimeTokens {
    Layout.fillWidth: true
    height: 200
    visible: isMinimalMode
    onTokenClicked: token => root.insertToken(token)
  }

  NDivider {
    Layout.fillWidth: true
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.clock.show-background.label")
    description: I18n.tr("settings.desktop-widgets.clock.show-background.description")
    checked: valueShowBackground
    onToggled: checked => valueShowBackground = checked
  }
}
