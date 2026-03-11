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
  property bool valueShowExecTooltip: widgetData.showExecTooltip !== undefined ? widgetData.showExecTooltip : widgetMetadata.showExecTooltip
  property bool valueShowTextTooltip: widgetData.showTextTooltip !== undefined ? widgetData.showTextTooltip : widgetMetadata.showTextTooltip
  property bool valueEnableColorization: widgetData.enableColorization !== undefined ? widgetData.enableColorization : widgetMetadata.enableColorization
  property string valueColorizeSystemIcon: widgetData.colorizeSystemIcon !== undefined ? widgetData.colorizeSystemIcon : widgetMetadata.colorizeSystemIcon
  property string valueIpcIdentifier: widgetData.ipcIdentifier !== undefined ? widgetData.ipcIdentifier : widgetMetadata.ipcIdentifier
  property string valueGeneralTooltipText: widgetData.generalTooltipText !== undefined ? widgetData.generalTooltipText : widgetMetadata.generalTooltipText

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
    settings.showExecTooltip = valueShowExecTooltip;
    settings.showTextTooltip = valueShowTextTooltip;
    settings.hideMode = valueHideMode;
    settings.maxTextLength = {
      "horizontal": valueMaxTextLengthHorizontal,
      "vertical": valueMaxTextLengthVertical
    };
    settings.textIntervalMs = parseInt(textIntervalInput.text || textIntervalInput.placeholderText, 10);
    settings.enableColorization = valueEnableColorization;
    settings.colorizeSystemIcon = valueColorizeSystemIcon;
    settings.ipcIdentifier = valueIpcIdentifier;
    settings.generalTooltipText = valueGeneralTooltipText;
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
    label: I18n.tr("bar.custom-button.show-icon-label")
    description: I18n.tr("bar.custom-button.show-icon-description")
    checked: valueShowIcon
    onToggled: checked => {
                 valueShowIcon = checked;
                 saveSettings();
               }
    visible: textCommandInput.text !== ""
    defaultValue: widgetMetadata.showIcon
  }

  NToggle {
    label: I18n.tr("bar.custom-button.enable-colorization-label")
    description: I18n.tr("bar.custom-button.enable-colorization-description")
    checked: valueEnableColorization
    onToggled: checked => {
                 valueEnableColorization = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.enableColorization
  }

  NColorChoice {
    visible: valueEnableColorization
    label: I18n.tr("common.select-icon-color")
    description: I18n.tr("bar.custom-button.color-selection-description")
    currentKey: valueColorizeSystemIcon
    onSelected: key => {
                  valueColorizeSystemIcon = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.colorizeSystemIcon
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.general-tooltip-text-label")
    description: I18n.tr("bar.custom-button.general-tooltip-text-description")
    placeholderText: I18n.tr("placeholders.enter-tooltip")
    text: valueGeneralTooltipText
    onTextChanged: valueGeneralTooltipText = text
    onEditingFinished: saveSettings()
    defaultValue: widgetMetadata.generalTooltipText
  }

  NToggle {
    id: showExecTooltipToggle
    label: I18n.tr("bar.custom-button.show-exec-tooltip-label")
    description: I18n.tr("bar.custom-button.show-exec-tooltip-description")
    checked: valueShowExecTooltip
    onToggled: checked => {
                 valueShowExecTooltip = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.showExecTooltip
  }

  NToggle {
    id: showTextTooltipToggle
    label: I18n.tr("bar.custom-button.show-text-tooltip-label")
    description: I18n.tr("bar.custom-button.show-text-tooltip-description")
    checked: valueShowTextTooltip
    onToggled: checked => {
                 valueShowTextTooltip = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.showTextTooltip
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.ipc-identifier-label")
    description: I18n.tr("bar.custom-button.ipc-identifier-description")
    placeholderText: I18n.tr("placeholders.enter-ipc-identifier")
    text: valueIpcIdentifier
    onTextChanged: valueIpcIdentifier = text
    onEditingFinished: saveSettings()
    defaultValue: widgetMetadata.ipcIdentifier
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
      defaultValue: widgetMetadata.leftClickExec
    }

    NToggle {
      id: leftClickUpdateText
      enabled: !valueTextStream
      Layout.alignment: Qt.AlignRight | Qt.AlignBottom
      Layout.bottomMargin: Style.marginS
      onEntered: TooltipService.show(leftClickUpdateText, I18n.tr("bar.custom-button.left-click-update-text"))
      onExited: TooltipService.hide()
      checked: widgetData?.leftClickUpdateText ?? widgetMetadata.leftClickUpdateText
      onToggled: isChecked => {
                   checked = isChecked;
                   saveSettings();
                 }
      defaultValue: widgetMetadata.leftClickUpdateText
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
      defaultValue: widgetMetadata.rightClickExec
    }

    NToggle {
      id: rightClickUpdateText
      enabled: !valueTextStream
      Layout.alignment: Qt.AlignRight | Qt.AlignBottom
      Layout.bottomMargin: Style.marginS
      onEntered: TooltipService.show(rightClickUpdateText, I18n.tr("bar.custom-button.right-click-update-text"))
      onExited: TooltipService.hide()
      checked: widgetData?.rightClickUpdateText ?? widgetMetadata.rightClickUpdateText
      onToggled: isChecked => {
                   checked = isChecked;
                   saveSettings();
                 }
      defaultValue: widgetMetadata.rightClickUpdateText
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
      defaultValue: widgetMetadata.middleClickExec
    }

    NToggle {
      id: middleClickUpdateText
      enabled: !valueTextStream
      Layout.alignment: Qt.AlignRight | Qt.AlignBottom
      Layout.bottomMargin: Style.marginS
      onEntered: TooltipService.show(middleClickUpdateText, I18n.tr("bar.custom-button.middle-click-update-text"))
      onExited: TooltipService.hide()
      checked: widgetData?.middleClickUpdateText ?? widgetMetadata.middleClickUpdateText
      onToggled: isChecked => {
                   checked = isChecked;
                   saveSettings();
                 }
      defaultValue: widgetMetadata.middleClickUpdateText
    }
  }

  // Wheel command settings
  NToggle {
    id: separateWheelToggle
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.wheel-mode-separate-label")
    description: I18n.tr("bar.custom-button.wheel-mode-separate-description")
    property bool internalChecked: (widgetData?.wheelMode || widgetMetadata?.wheelMode) === "separate"
    checked: internalChecked
    onToggled: checked => {
                 internalChecked = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.wheelMode === "separate"
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
        defaultValue: widgetMetadata.wheelExec
      }

      NToggle {
        id: wheelUpdateText
        enabled: !valueTextStream
        Layout.alignment: Qt.AlignRight | Qt.AlignBottom
        Layout.bottomMargin: Style.marginS
        onEntered: TooltipService.show(wheelUpdateText, I18n.tr("bar.custom-button.wheel-update-text"))
        onExited: TooltipService.hide()
        checked: widgetData?.wheelUpdateText ?? widgetMetadata?.wheelUpdateText
        onToggled: isChecked => {
                     checked = isChecked;
                     saveSettings();
                   }
        defaultValue: widgetMetadata.wheelUpdateText
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
          defaultValue: widgetMetadata.wheelUpExec
        }

        NToggle {
          id: wheelUpUpdateText
          enabled: !valueTextStream
          Layout.alignment: Qt.AlignRight | Qt.AlignBottom
          Layout.bottomMargin: Style.marginS
          onEntered: TooltipService.show(wheelUpUpdateText, I18n.tr("bar.custom-button.wheel-update-text"))
          onExited: TooltipService.hide()
          checked: (widgetData?.wheelUpUpdateText !== undefined) ? widgetData.wheelUpUpdateText : widgetMetadata?.wheelUpUpdateText
          onToggled: isChecked => {
                       checked = isChecked;
                       saveSettings();
                     }
          defaultValue: widgetMetadata.wheelUpUpdateText
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
          defaultValue: widgetMetadata.wheelDownExec
        }

        NToggle {
          id: wheelDownUpdateText
          enabled: !valueTextStream
          Layout.alignment: Qt.AlignRight | Qt.AlignBottom
          Layout.bottomMargin: Style.marginS
          onEntered: TooltipService.show(wheelDownUpdateText, I18n.tr("bar.custom-button.wheel-update-text"))
          onExited: TooltipService.hide()
          checked: (widgetData?.wheelDownUpdateText !== undefined) ? widgetData.wheelDownUpdateText : widgetMetadata?.wheelDownUpdateText
          onToggled: isChecked => {
                       checked = isChecked;
                       saveSettings();
                     }
          defaultValue: widgetMetadata.wheelDownUpdateText
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
    label: I18n.tr("bar.custom-button.max-text-length-horizontal-label")
    description: I18n.tr("bar.custom-button.max-text-length-horizontal-description")
    from: 0
    to: 100
    value: valueMaxTextLengthHorizontal
    onValueChanged: {
      valueMaxTextLengthHorizontal = value;
      saveSettings();
    }
    defaultValue: widgetMetadata.maxTextLength.horizontal
  }

  NSpinBox {
    label: I18n.tr("bar.custom-button.max-text-length-vertical-label")
    description: I18n.tr("bar.custom-button.max-text-length-vertical-description")
    from: 0
    to: 100
    value: valueMaxTextLengthVertical
    onValueChanged: {
      valueMaxTextLengthVertical = value;
      saveSettings();
    }
    defaultValue: widgetMetadata.maxTextLength.vertical
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
    defaultValue: widgetMetadata.textStream
  }

  NToggle {
    id: parseJsonInput
    label: I18n.tr("bar.custom-button.parse-json-label")
    description: I18n.tr("bar.custom-button.parse-json-description")
    checked: valueParseJson
    onToggled: checked => {
                 valueParseJson = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.parseJson
  }

  NTextInput {
    id: textCommandInput
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.display-command-output-label")
    description: valueTextStream ? I18n.tr("bar.custom-button.display-command-output-stream-description") : I18n.tr("bar.custom-button.display-command-output-description")
    placeholderText: I18n.tr("placeholders.command-example")
    text: widgetData?.textCommand || widgetMetadata.textCommand
    onEditingFinished: saveSettings()
    defaultValue: widgetMetadata.textCommand
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
    defaultValue: widgetMetadata.textCollapse
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
    defaultValue: String(widgetMetadata.textIntervalMs)
  }

  NComboBox {
    id: hideModeComboBox
    label: I18n.tr("bar.custom-button.hide-mode-label")
    description: I18n.tr("bar.custom-button.hide-mode-description")
    model: [
      {
        name: I18n.tr("bar.custom-button.hide-mode-always-expanded"),
        key: "alwaysExpanded"
      },
      {
        name: I18n.tr("bar.custom-button.hide-mode-expand-with-output"),
        key: "expandWithOutput"
      },
      {
        name: I18n.tr("bar.custom-button.hide-mode-max-transparent"),
        key: "maxTransparent"
      }
    ]
    currentKey: valueHideMode
    onSelected: key => {
                  valueHideMode = key;
                  saveSettings();
                }
    visible: textCommandInput.text !== "" && valueTextStream == true
    defaultValue: widgetMetadata.hideMode
  }
}
