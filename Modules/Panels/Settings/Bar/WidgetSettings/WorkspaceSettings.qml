import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  property string valueLabelMode: widgetData.labelMode !== undefined ? widgetData.labelMode : widgetMetadata.labelMode
  property bool valueHideUnoccupied: widgetData.hideUnoccupied !== undefined ? widgetData.hideUnoccupied : widgetMetadata.hideUnoccupied
  property int valueCharacterCount: widgetData.characterCount !== undefined ? widgetData.characterCount : widgetMetadata.characterCount

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.labelMode = valueLabelMode
    settings.hideUnoccupied = valueHideUnoccupied
    settings.characterCount = valueCharacterCount
    return settings
  }

  NComboBox {
    id: labelModeCombo
    label: I18n.tr("bar.widget-settings.workspace.label-mode.label")
    description: I18n.tr("bar.widget-settings.workspace.label-mode.description")
    model: [{
        "key": "none",
        "name": I18n.tr("options.workspace-labels.none")
      }, {
        "key": "index",
        "name": I18n.tr("options.workspace-labels.index")
      }, {
        "key": "name",
        "name": I18n.tr("options.workspace-labels.name")
      }]
    currentKey: widgetData.labelMode || widgetMetadata.labelMode
    onSelected: key => valueLabelMode = key
    minimumWidth: 200
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.workspace.hide-unoccupied.label")
    description: I18n.tr("bar.widget-settings.workspace.hide-unoccupied.description")
    checked: valueHideUnoccupied
    onToggled: checked => valueHideUnoccupied = checked
  }

  NSpinBox {
    label: I18n.tr("bar.widget-settings.workspace.character-count.label")
    description: I18n.tr("bar.widget-settings.workspace.character-count.description")
    from: 1
    to: 10
    value: valueCharacterCount
    onValueChanged: valueCharacterCount = value
    visible: valueLabelMode === "name"
  }
}
