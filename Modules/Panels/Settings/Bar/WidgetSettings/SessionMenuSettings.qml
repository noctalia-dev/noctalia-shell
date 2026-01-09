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
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property string valueColorName: widgetData.colorName !== undefined ? widgetData.colorName : widgetMetadata.colorName

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.colorName = valueColorName;
    return settings;
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.audio-visualizer.color-name-label")
    description: I18n.tr("bar.audio-visualizer.color-name-description")
    model: [
      {
        "key": "primary",
        "name": I18n.tr("colors.primary")
      },
      {
        "key": "secondary",
        "name": I18n.tr("colors.secondary")
      },
      {
        "key": "tertiary",
        "name": I18n.tr("colors.tertiary")
      },
      {
        "key": "onSurface",
        "name": I18n.tr("colors.on-surface")
      },
      {
        "key": "error",
        "name": I18n.tr("colors.error")
      }
    ]
    currentKey: root.valueColorName
    onSelected: key => root.valueColorName = key
  }
}
