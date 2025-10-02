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

  // Local state with safe defaults
  property bool valueUsePrimaryColor: (widgetData && widgetData.usePrimaryColor !== undefined) ? widgetData.usePrimaryColor : (widgetMetadata ? widgetMetadata.usePrimaryColor : true)
  property bool valueUseMonospacedFont: (widgetData && widgetData.useMonospacedFont !== undefined) ? widgetData.useMonospacedFont : (widgetMetadata ? widgetMetadata.useMonospacedFont : false)
  property bool valueUseCustomFont: (widgetData && widgetData.useCustomFont !== undefined) ? widgetData.useCustomFont : (widgetMetadata ? widgetMetadata.useCustomFont : false)
  property string valueCustomFont: (widgetData && widgetData.customFont !== undefined) ? widgetData.customFont : (widgetMetadata ? widgetMetadata.customFont : "")
  property string valueFormatHorizontal: (widgetData && widgetData.formatHorizontal !== undefined) ? widgetData.formatHorizontal : (widgetMetadata ? widgetMetadata.formatHorizontal : "HH:mm ddd, MMM dd")
  property string valueFormatVertical: (widgetData && widgetData.formatVertical !== undefined) ? widgetData.formatVertical : (widgetMetadata ? widgetMetadata.formatVertical : "HH mm dd MM")

  // Font list - will be populated dynamically
  property var fontList: []

  Component.onCompleted: {
    loadFonts()
  }
  
  function loadFonts() {
    console.log("ClockSettings: Loading fonts...")
    
    // Try to access FontService directly
    if (typeof FontService !== 'undefined') {
      console.log("ClockSettings: FontService exists")
      if (FontService.availableFonts) {
        console.log("ClockSettings: FontService.availableFonts exists with", FontService.availableFonts.length, "fonts")
        fontList = FontService.availableFonts
        console.log("ClockSettings: Successfully loaded", fontList.length, "fonts from FontService")
        return
      } else {
        console.log("ClockSettings: FontService.availableFonts is null/undefined")
      }
    } else {
      console.log("ClockSettings: FontService is not defined")
    }
    
    // Fallback font list
    console.log("ClockSettings: Using fallback font list")
    fontList = [
      { key: "Cantarell", name: "Cantarell" },
      { key: "DejaVu Sans", name: "DejaVu Sans" },
      { key: "DejaVu Sans Mono", name: "DejaVu Sans Mono" },
      { key: "DejaVu Serif", name: "DejaVu Serif" },
      { key: "Fira Code", name: "Fira Code" },
      { key: "Fira Sans", name: "Fira Sans" },
      { key: "IBM Plex Sans", name: "IBM Plex Sans" },
      { key: "IBM Plex Mono", name: "IBM Plex Mono" },
      { key: "Inconsolata", name: "Inconsolata" },
      { key: "Inter", name: "Inter" },
      { key: "JetBrains Mono", name: "JetBrains Mono" },
      { key: "Liberation Sans", name: "Liberation Sans" },
      { key: "Liberation Mono", name: "Liberation Mono" },
      { key: "Noto Sans", name: "Noto Sans" },
      { key: "Noto Mono", name: "Noto Mono" },
      { key: "Open Sans", name: "Open Sans" },
      { key: "Roboto", name: "Roboto" },
      { key: "Roboto Mono", name: "Roboto Mono" },
      { key: "Source Code Pro", name: "Source Code Pro" },
      { key: "Ubuntu", name: "Ubuntu" },
      { key: "Ubuntu Mono", name: "Ubuntu Mono" }
    ]
    console.log("ClockSettings: Loaded", fontList.length, "fallback fonts")
  }

  // Track the currently focused input field
  property var focusedInput: null
  property int focusedLineIndex: -1

  readonly property var now: Time.date

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.usePrimaryColor = valueUsePrimaryColor
    settings.useMonospacedFont = valueUseMonospacedFont
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
    label: I18n.tr("bar.widget-settings.clock.use-monospaced-font.label")
    description: I18n.tr("bar.widget-settings.clock.use-monospaced-font.description")
    checked: valueUseMonospacedFont
    onToggled: checked => valueUseMonospacedFont = checked
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
    // Use FontService.availableFonts directly - this works in GeneralTab
    model: FontService ? FontService.availableFonts : []
    currentKey: valueCustomFont
    placeholder: I18n.tr("bar.widget-settings.clock.custom-font.placeholder")
    searchPlaceholder: I18n.tr("bar.widget-settings.clock.custom-font.search-placeholder")
    popupHeight: 420 * scaling
    minimumWidth: 300 * scaling
    
    Component.onCompleted: {
      console.log("ClockSettings: NSearchableComboBox model has", model ? model.length : 0, "fonts")
      console.log("ClockSettings: FontService type:", typeof FontService)
      if (FontService) {
        console.log("ClockSettings: FontService.availableFonts type:", typeof FontService.availableFonts)
        console.log("ClockSettings: FontService.availableFonts length:", FontService.availableFonts ? FontService.availableFonts.length : "undefined")
      }
    }
    
    onSelected: function (key) {
      valueCustomFont = key
      console.log("ClockSettings: Selected font:", key)
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
        Layout.preferredWidth: 320 * scaling
        Layout.preferredHeight: 160 * scaling // Fixed height instead of fillHeight

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
              model: Qt.locale().toString(now, valueFormatHorizontal.trim()).split("\\n")
              delegate: NText {
                visible: text !== ""
                text: modelData
                family: valueUseCustomFont && valueCustomFont ? valueCustomFont : (valueUseMonospacedFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault)
                pointSize: Style.fontSizeM * scaling
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
              model: Qt.locale().toString(now, valueFormatVertical.trim()).split(" ")
              delegate: NText {
                visible: text !== ""
                text: modelData
                family: valueUseCustomFont && valueCustomFont ? valueCustomFont : (valueUseMonospacedFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault)
                pointSize: Style.fontSizeM * scaling
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
