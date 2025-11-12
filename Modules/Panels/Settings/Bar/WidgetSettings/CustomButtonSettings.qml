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

  property var widgetData: null
  property var widgetMetadata: null

  property string valueIcon: widgetData.icon !== undefined ? widgetData.icon : widgetMetadata.icon
  property bool valueTextStream: widgetData.textStream !== undefined ? widgetData.textStream : widgetMetadata.textStream
  property bool valueParseJson: widgetData.parseJson !== undefined ? widgetData.parseJson : widgetMetadata.parseJson
  property bool valueHideTextInVerticalBar: widgetData.hideTextInVerticalBar !== undefined ? widgetData.hideTextInVerticalBar : widgetMetadata.hideTextInVerticalBar

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.icon = valueIcon
    settings.leftClickExec = leftClickExecInput.text
    settings.leftClickUpdateText = leftClickUpdateText.checked
    settings.rightClickExec = rightClickExecInput.text
    settings.rightClickUpdateText = rightClickUpdateText.checked
    settings.middleClickExec = middleClickExecInput.text
    settings.middleClickUpdateText = middleClickUpdateText.checked
    settings.wheelExec = wheelExecInput.text
    settings.wheelUpdateText = wheelUpdateText.checked
    settings.textCommand = textCommandInput.text
    settings.textCollapse = textCollapseInput.text
    settings.textStream = valueTextStream
    settings.parseJson = valueParseJson
    settings.hideTextInVerticalBar = valueHideTextInVerticalBar
    settings.textIntervalMs = parseInt(textIntervalInput.text || textIntervalInput.placeholderText, 10)
    return settings
  }

  RowLayout {
    spacing: Style.marginM

    NLabel {
      label: I18n.tr("bar.widget-settings.custom-button.icon.label")
      description: I18n.tr("bar.widget-settings.custom-button.icon.description")
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: valueIcon
      pointSize: Style.fontSizeXL
      visible: valueIcon !== ""
    }

    NButton {
      text: I18n.tr("bar.widget-settings.custom-button.browse")
      onClicked: iconPicker.open()
    }
  }

  NIconPicker {
    id: iconPicker
    initialIcon: valueIcon
    onIconSelected: function (iconName) {
      valueIcon = iconName
    }
  }

  RowLayout {
    spacing: Style.marginM

    NTextInput {
      id: leftClickExecInput
      Layout.fillWidth: true
      label: I18n.tr("bar.widget-settings.custom-button.left-click.label")
      description: I18n.tr("bar.widget-settings.custom-button.left-click.description")
      placeholderText: I18n.tr("placeholders.enter-command")
      text: widgetData?.leftClickExec || widgetMetadata.leftClickExec
    }

    NToggle {
      id: leftClickUpdateText
      enabled: !valueTextStream
      Layout.alignment: Qt.AlignRight | Qt.AlignBottom
      Layout.bottomMargin: Style.marginS
      onEntered: TooltipService.show(Screen, leftClickUpdateText, I18n.tr("bar.widget-settings.custom-button.left-click.update-text"), "auto")
      onExited: TooltipService.hide()
      checked: widgetData?.leftClickUpdateText ?? widgetMetadata.leftClickUpdateText
      onToggled: isChecked => checked = isChecked
    }
  }

  RowLayout {
    spacing: Style.marginM

    NTextInput {
      id: rightClickExecInput
      Layout.fillWidth: true
      label: I18n.tr("bar.widget-settings.custom-button.right-click.label")
      description: I18n.tr("bar.widget-settings.custom-button.right-click.description")
      placeholderText: I18n.tr("placeholders.enter-command")
      text: widgetData?.rightClickExec || widgetMetadata.rightClickExec
    }

    NToggle {
      id: rightClickUpdateText
      enabled: !valueTextStream
      Layout.alignment: Qt.AlignRight | Qt.AlignBottom
      Layout.bottomMargin: Style.marginS
      onEntered: TooltipService.show(Screen, rightClickUpdateText, I18n.tr("bar.widget-settings.custom-button.right-click.update-text"), "auto")
      onExited: TooltipService.hide()
      checked: widgetData?.rightClickUpdateText ?? widgetMetadata.rightClickUpdateText
      onToggled: isChecked => checked = isChecked
    }
  }

  RowLayout {
    spacing: Style.marginM

    NTextInput {
      id: middleClickExecInput
      Layout.fillWidth: true
      label: I18n.tr("bar.widget-settings.custom-button.middle-click.label")
      description: I18n.tr("bar.widget-settings.custom-button.middle-click.description")
      placeholderText: I18n.tr("placeholders.enter-command")
      text: widgetData.middleClickExec || widgetMetadata.middleClickExec
    }

    NToggle {
      id: middleClickUpdateText
      enabled: !valueTextStream
      Layout.alignment: Qt.AlignRight | Qt.AlignBottom
      Layout.bottomMargin: Style.marginS
      onEntered: TooltipService.show(Screen, middleClickUpdateText, I18n.tr("bar.widget-settings.custom-button.middle-click.update-text"), "auto")
      onExited: TooltipService.hide()
      checked: widgetData?.middleClickUpdateText ?? widgetMetadata.middleClickUpdateText
      onToggled: isChecked => checked = isChecked
    }
  }

  RowLayout {
    spacing: Style.marginM

    NTextInput {
      id: wheelExecInput
      Layout.fillWidth: true
      label: I18n.tr("bar.widget-settings.custom-button.wheel.label")
      description: I18n.tr("bar.widget-settings.custom-button.wheel.description")
      placeholderText: I18n.tr("placeholders.enter-command")
      text: widgetData.wheelExec || widgetMetadata.wheelExec
    }

    NToggle {
      id: wheelUpdateText
      enabled: !valueTextStream
      Layout.alignment: Qt.AlignRight | Qt.AlignBottom
      Layout.bottomMargin: Style.marginS
      onEntered: TooltipService.show(Screen, wheelUpdateText, I18n.tr("bar.widget-settings.custom-button.wheel.update-text"), "auto")
      onExited: TooltipService.hide()
      checked: widgetData?.wheelUpdateText ?? widgetMetadata.wheelUpdateText
      onToggled: isChecked => checked = isChecked
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NHeader {
    label: I18n.tr("bar.widget-settings.custom-button.dynamic-text")
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.custom-button.hide-vertical.label", "Hide text in vertical bar")
    description: I18n.tr("bar.widget-settings.custom-button.hide-vertical.description", "If enabled, the text from the command output will not be shown when the bar is in a vertical layout (left or right).")
    checked: valueHideTextInVerticalBar
    onToggled: checked => valueHideTextInVerticalBar = checked
  }

  NToggle {
    id: textStreamInput
    label: I18n.tr("bar.widget-settings.custom-button.text-stream.label")
    description: I18n.tr("bar.widget-settings.custom-button.text-stream.description")
    checked: valueTextStream
    onToggled: checked => valueTextStream = checked
  }

  NToggle {
    id: parseJsonInput
    label: I18n.tr("bar.widget-settings.custom-button.parse-json.label", "Parse output as JSON")
    description: I18n.tr("bar.widget-settings.custom-button.parse-json.description", "Parse the command output as a JSON object to dynamically set text and icon.")
    checked: valueParseJson
    onToggled: checked => valueParseJson = checked
  }

  NTextInput {
    id: textCommandInput
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.custom-button.display-command-output.label")
    description: valueTextStream ? I18n.tr("bar.widget-settings.custom-button.display-command-output.stream-description") : I18n.tr("bar.widget-settings.custom-button.display-command-output.description")
    placeholderText: I18n.tr("placeholders.command-example")
    text: widgetData?.textCommand || widgetMetadata.textCommand
  }

  NTextInput {
    id: textCollapseInput
    Layout.fillWidth: true
    visible: valueTextStream
    label: I18n.tr("bar.widget-settings.custom-button.collapse-condition.label")
    description: I18n.tr("bar.widget-settings.custom-button.collapse-condition.description")
    placeholderText: I18n.tr("placeholders.enter-text-to-collapse")
    text: widgetData?.textCollapse || widgetMetadata.textCollapse
  }

  NTextInput {
    id: textIntervalInput
    Layout.fillWidth: true
    visible: !valueTextStream
    label: I18n.tr("bar.widget-settings.custom-button.refresh-interval.label")
    description: I18n.tr("bar.widget-settings.custom-button.refresh-interval.description")
    placeholderText: String(widgetMetadata.textIntervalMs || 3000)
    text: widgetData && widgetData.textIntervalMs !== undefined ? String(widgetData.textIntervalMs) : ""
  }
}
