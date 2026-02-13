import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  property string valueIcon: widgetData.icon !== undefined ? widgetData.icon : widgetMetadata.icon
  property bool valueTextStream: widgetData.textStream !== undefined ? widgetData.textStream : widgetMetadata.textStream
  property bool valueParseJson: widgetData.parseJson !== undefined ? widgetData.parseJson : widgetMetadata.parseJson
  property int valueMaxTextLengthHorizontal: widgetData?.maxTextLength?.horizontal ?? widgetMetadata?.maxTextLength?.horizontal
  property int valueMaxTextLengthVertical: widgetData?.maxTextLength?.vertical ?? widgetMetadata?.maxTextLength?.vertical
  property string valueHideMode: (widgetData.hideMode !== undefined) ? widgetData.hideMode : widgetMetadata.hideMode
  property bool valueShowIcon: (widgetData.showIcon !== undefined) ? widgetData.showIcon : widgetMetadata.showIcon
  property bool valueEnableColorization: widgetData.enableColorization || false
  property string valueColorizeSystemIcon: widgetData.colorizeSystemIcon !== undefined ? widgetData.colorizeSystemIcon : widgetMetadata.colorizeSystemIcon || "none"
  property string valueIpcIdentifier: widgetData.ipcIdentifier !== undefined ? widgetData.ipcIdentifier : widgetMetadata.ipcIdentifier || ""

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.icon = valueIcon;
    settings.leftClickExec = leftClickExecInput.text;
    settings.leftClickUpdateText = leftClickUpdateText.checked;
    settings.rightClickExec = rightClickExecInput.text;
    settings.rightClickUpdateText = rightClickUpdateText.checked;
    settings.middleClickExec = middleClickExecInput.text;
    settings.middleClickUpdateText = middleClickUpdateText.checked;
    settings.wheelMode = separateWheelToggle.internalChecked ? "separate" : "unified";
    settings.wheelExec = wheelExecInput.text;
    settings.wheelUpExec = wheelUpExecInput.text;
    settings.wheelDownExec = wheelDownExecInput.text;
    settings.wheelUpdateText = wheelUpdateText.checked;
    settings.wheelUpUpdateText = wheelUpUpdateText.checked;
    settings.wheelDownUpdateText = wheelDownUpdateText.checked;
    settings.textCommand = textCommandInput.text;
    settings.textCollapse = textCollapseInput.text;
    settings.textStream = valueTextStream;
    settings.parseJson = valueParseJson;
    settings.showIcon = valueShowIcon;
    settings.hideMode = valueHideMode;
    settings.maxTextLength = {
      "horizontal": valueMaxTextLengthHorizontal,
      "vertical": valueMaxTextLengthVertical
    };
    settings.textIntervalMs = parseInt(textIntervalInput.text || textIntervalInput.placeholderText, 10);
    settings.enableColorization = valueEnableColorization;
    settings.colorizeSystemIcon = valueColorizeSystemIcon;
    settings.ipcIdentifier = valueIpcIdentifier;
    settingsChanged(settings);
  }

  RowLayout {
    spacing: Style.marginM

    NLabel {
      label: I18n.tr("common.icon")
      description: I18n.tr("bar.custom-button.icon-description")
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: valueIcon
      pointSize: Style.fontSizeXL
      visible: valueIcon !== ""
    }

    NButton {
      text: I18n.tr("common.browse")
      onClicked: iconPicker.open()
    }
  }

  NIconPicker {
    id: iconPicker
    initialIcon: valueIcon
    onIconSelected: function (iconName) {
      valueIcon = iconName;
      saveSettings();
    }
  }

  NToggle {
    id: showIconToggle
    label: I18n.tr("bar.custom-button.show-icon-label", "Show icon")
    description: I18n.tr("bar.custom-button.show-icon-description", "Toggles the visibility of the widget's icon.")
    checked: valueShowIcon
    onToggled: checked => {
                 valueShowIcon = checked;
                 saveSettings();
               }
    visible: textCommandInput.text !== ""
  }

  NToggle {
    label: I18n.tr("bar.custom-button.enable-colorization-label")
    description: I18n.tr("bar.custom-button.enable-colorization-description")
    checked: valueEnableColorization
    onToggled: checked => {
                 valueEnableColorization = checked;
                 saveSettings();
               }
  }

  NComboBox {
    visible: valueEnableColorization
    label: I18n.tr("common.select-color")
    description: I18n.tr("bar.custom-button.color-selection-description")
    model: Color.colorKeyModel
    currentKey: valueColorizeSystemIcon
    onSelected: key => {
                  valueColorizeSystemIcon = key;
                  saveSettings();
                }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.ipc-identifier-label")
    description: I18n.tr("bar.custom-button.ipc-identifier-description")
    placeholderText: I18n.tr("placeholders.enter-ipc-identifier")
    text: valueIpcIdentifier
    onTextChanged: valueIpcIdentifier = text
    onEditingFinished: saveSettings()
  }

  RowLayout {
    spacing: Style.marginM

    NTextInput {
      id: leftClickExecInput
      Layout.fillWidth: true
      label: I18n.tr("bar.custom-button.left-click-label")
      description: I18n.tr("bar.custom-button.left-click-description")
      placeholderText: I18n.tr("placeholders.enter-command")
      text: widgetData?.leftClickExec || widgetMetadata.leftClickExec
      onEditingFinished: saveSettings()
    }

    NToggle {
      id: leftClickUpdateText
      enabled: !valueTextStream
      Layout.alignment: Qt.AlignRight | Qt.AlignBottom
      Layout.bottomMargin: Style.marginS
      onEntered: TooltipService.show(leftClickUpdateText, I18n.tr("bar.custom-button.left-click-update-text"), "auto")
      onExited: TooltipService.hide()
      checked: widgetData?.leftClickUpdateText ?? widgetMetadata.leftClickUpdateText
      onToggled: isChecked => {
                   checked = isChecked;
                   saveSettings();
                 }
    }
  }

  RowLayout {
    spacing: Style.marginM

    NTextInput {
      id: rightClickExecInput
      Layout.fillWidth: true
      label: I18n.tr("bar.custom-button.right-click-label")
      description: I18n.tr("bar.custom-button.right-click-description")
      placeholderText: I18n.tr("placeholders.enter-command")
      text: widgetData?.rightClickExec || widgetMetadata.rightClickExec
      onEditingFinished: saveSettings()
    }

    NToggle {
      id: rightClickUpdateText
      enabled: !valueTextStream
      Layout.alignment: Qt.AlignRight | Qt.AlignBottom
      Layout.bottomMargin: Style.marginS
      onEntered: TooltipService.show(rightClickUpdateText, I18n.tr("bar.custom-button.right-click-update-text"), "auto")
      onExited: TooltipService.hide()
      checked: widgetData?.rightClickUpdateText ?? widgetMetadata.rightClickUpdateText
      onToggled: isChecked => {
                   checked = isChecked;
                   saveSettings();
                 }
    }
  }

  RowLayout {
    spacing: Style.marginM

    NTextInput {
      id: middleClickExecInput
      Layout.fillWidth: true
      label: I18n.tr("bar.custom-button.middle-click-label")
      description: I18n.tr("bar.custom-button.middle-click-description")
      placeholderText: I18n.tr("placeholders.enter-command")
      text: widgetData.middleClickExec || widgetMetadata.middleClickExec
      onEditingFinished: saveSettings()
    }

    NToggle {
      id: middleClickUpdateText
      enabled: !valueTextStream
      Layout.alignment: Qt.AlignRight | Qt.AlignBottom
      Layout.bottomMargin: Style.marginS
      onEntered: TooltipService.show(middleClickUpdateText, I18n.tr("bar.custom-button.middle-click-update-text"), "auto")
      onExited: TooltipService.hide()
      checked: widgetData?.middleClickUpdateText ?? widgetMetadata.middleClickUpdateText
      onToggled: isChecked => {
                   checked = isChecked;
                   saveSettings();
                 }
    }
  }

  // Wheel command settings
  NToggle {
    id: separateWheelToggle
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.wheel-mode-separate-label", "Separate wheel commands")
    description: I18n.tr("bar.custom-button.wheel-mode-separate-description", "Enable separate commands for wheel up and down")
    property bool internalChecked: (widgetData?.wheelMode || widgetMetadata?.wheelMode) === "separate"
    checked: internalChecked
    onToggled: checked => {
                 internalChecked = checked;
                 saveSettings();
               }
  }

  ColumnLayout {
    Layout.fillWidth: true

    RowLayout {
      id: unifiedWheelLayout
      visible: !separateWheelToggle.checked
      spacing: Style.marginM

      NTextInput {
        id: wheelExecInput
        Layout.fillWidth: true
        label: I18n.tr("bar.custom-button.wheel-label")
        description: I18n.tr("bar.custom-button.wheel-description")
        placeholderText: I18n.tr("placeholders.enter-command")
        text: widgetData?.wheelExec || widgetMetadata?.wheelExec
        onEditingFinished: saveSettings()
      }

      NToggle {
        id: wheelUpdateText
        enabled: !valueTextStream
        Layout.alignment: Qt.AlignRight | Qt.AlignBottom
        Layout.bottomMargin: Style.marginS
        onEntered: TooltipService.show(wheelUpdateText, I18n.tr("bar.custom-button.wheel-update-text"), "auto")
        onExited: TooltipService.hide()
        checked: widgetData?.wheelUpdateText ?? widgetMetadata?.wheelUpdateText
        onToggled: isChecked => {
                     checked = isChecked;
                     saveSettings();
                   }
      }
    }

    ColumnLayout {
      id: separatedWheelLayout
      Layout.fillWidth: true
      visible: separateWheelToggle.checked

      RowLayout {
        spacing: Style.marginM

        NTextInput {
          id: wheelUpExecInput
          Layout.fillWidth: true
          label: I18n.tr("bar.custom-button.wheel-up-label")
          description: I18n.tr("bar.custom-button.wheel-up-description")
          placeholderText: I18n.tr("placeholders.enter-command")
          text: widgetData?.wheelUpExec || widgetMetadata?.wheelUpExec
          onEditingFinished: saveSettings()
        }

        NToggle {
          id: wheelUpUpdateText
          enabled: !valueTextStream
          Layout.alignment: Qt.AlignRight | Qt.AlignBottom
          Layout.bottomMargin: Style.marginS
          onEntered: TooltipService.show(wheelUpUpdateText, I18n.tr("bar.custom-button.wheel-update-text"), "auto")
          onExited: TooltipService.hide()
          checked: (widgetData?.wheelUpUpdateText !== undefined) ? widgetData.wheelUpUpdateText : widgetMetadata?.wheelUpUpdateText
          onToggled: isChecked => {
                       checked = isChecked;
                       saveSettings();
                     }
        }
      }

      RowLayout {
        spacing: Style.marginM

        NTextInput {
          id: wheelDownExecInput
          Layout.fillWidth: true
          label: I18n.tr("bar.custom-button.wheel-down-label")
          description: I18n.tr("bar.custom-button.wheel-down-description")
          placeholderText: I18n.tr("placeholders.enter-command")
          text: widgetData?.wheelDownExec || widgetMetadata?.wheelDownExec
          onEditingFinished: saveSettings()
        }

        NToggle {
          id: wheelDownUpdateText
          enabled: !valueTextStream
          Layout.alignment: Qt.AlignRight | Qt.AlignBottom
          Layout.bottomMargin: Style.marginS
          onEntered: TooltipService.show(wheelDownUpdateText, I18n.tr("bar.custom-button.wheel-update-text"), "auto")
          onExited: TooltipService.hide()
          checked: (widgetData?.wheelDownUpdateText !== undefined) ? widgetData.wheelDownUpdateText : widgetMetadata?.wheelDownUpdateText
          onToggled: isChecked => {
                       checked = isChecked;
                       saveSettings();
                     }
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NHeader {
    label: I18n.tr("bar.custom-button.dynamic-text")
  }

  NSpinBox {
    label: I18n.tr("bar.custom-button.max-text-length-horizontal-label", "Max text length (horizontal)")
    description: I18n.tr("bar.custom-button.max-text-length-horizontal-description", "Maximum number of characters to show in horizontal bar (0 to hide text)")
    from: 0
    to: 100
    value: valueMaxTextLengthHorizontal
    onValueChanged: {
      valueMaxTextLengthHorizontal = value;
      saveSettings();
    }
  }

  NSpinBox {
    label: I18n.tr("bar.custom-button.max-text-length-vertical-label", "Max text length (vertical)")
    description: I18n.tr("bar.custom-button.max-text-length-vertical-description", "Maximum number of characters to show in vertical bar (0 to hide text)")
    from: 0
    to: 100
    value: valueMaxTextLengthVertical
    onValueChanged: {
      valueMaxTextLengthVertical = value;
      saveSettings();
    }
  }

  NToggle {
    id: textStreamInput
    label: I18n.tr("bar.custom-button.text-stream-label")
    description: I18n.tr("bar.custom-button.text-stream-description")
    checked: valueTextStream
    onToggled: checked => {
                 valueTextStream = checked;
                 saveSettings();
               }
  }

  NToggle {
    id: parseJsonInput
    label: I18n.tr("bar.custom-button.parse-json-label", "Parse output as JSON")
    description: I18n.tr("bar.custom-button.parse-json-description", "Parse the command output as a JSON object to dynamically set text and icon.")
    checked: valueParseJson
    onToggled: checked => {
                 valueParseJson = checked;
                 saveSettings();
               }
  }

  NTextInput {
    id: textCommandInput
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.display-command-output-label")
    description: valueTextStream ? I18n.tr("bar.custom-button.display-command-output-stream-description") : I18n.tr("bar.custom-button.display-command-output-description")
    placeholderText: I18n.tr("placeholders.command-example")
    text: widgetData?.textCommand || widgetMetadata.textCommand
    onEditingFinished: saveSettings()
  }

  NTextInput {
    id: textCollapseInput
    Layout.fillWidth: true
    visible: valueTextStream
    label: I18n.tr("bar.custom-button.collapse-condition-label")
    description: I18n.tr("bar.custom-button.collapse-condition-description")
    placeholderText: I18n.tr("placeholders.enter-text-to-collapse")
    text: widgetData?.textCollapse || widgetMetadata.textCollapse
    onEditingFinished: saveSettings()
  }

  NTextInput {
    id: textIntervalInput
    Layout.fillWidth: true
    visible: !valueTextStream
    label: I18n.tr("bar.custom-button.refresh-interval-label")
    description: I18n.tr("bar.custom-button.refresh-interval-description")
    placeholderText: String(widgetMetadata.textIntervalMs)
    text: widgetData && widgetData.textIntervalMs !== undefined ? String(widgetData.textIntervalMs) : ""
    onEditingFinished: saveSettings()
  }

  NComboBox {
    id: hideModeComboBox
    label: I18n.tr("bar.custom-button.hide-mode-label", "Hide mode")
    description: I18n.tr("bar.custom-button.hide-mode-description", "Controls widget visibility when the command has no output.")
    model: [
      {
        name: I18n.tr("bar.custom-button.hide-mode-always-expanded", "Always expanded"),
        key: "alwaysExpanded"
      },
      {
        name: I18n.tr("bar.custom-button.hide-mode-expand-with-output", "Expand when has output"),
        key: "expandWithOutput"
      },
      {
        name: I18n.tr("bar.custom-button.hide-mode-max-transparent", "Max expanded but transparent"),
        key: "maxTransparent"
      }
    ]
    currentKey: valueHideMode
    onSelected: key => {
                  valueHideMode = key;
                  saveSettings();
                }
    visible: textCommandInput.text !== "" && valueTextStream == true
  }
}
