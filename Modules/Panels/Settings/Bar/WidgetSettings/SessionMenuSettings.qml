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

  signal settingsChanged(var settings)

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
        "key": "none",
        "name": I18n.tr("common.none")
      },
      {
        "key": "primary",
        "name": I18n.tr("common.primary")
      },
      {
        "key": "secondary",
        "name": I18n.tr("common.secondary")
      },
      {
        "key": "tertiary",
        "name": I18n.tr("common.tertiary")
      },
      {
        "key": "error",
        "name": I18n.tr("common.error")
      }
    ]
    currentKey: root.valueColorName
    onSelected: key => {
                  root.valueColorName = key;
                  settingsChanged(saveSettings());
                }
  }
}
