import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM
  width: 500

  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  property bool valueShowBackground: widgetData.showBackground !== undefined ? widgetData.showBackground : (widgetMetadata.showBackground ?? true)
  property bool valueRoundedCorners: widgetData.roundedCorners !== undefined ? widgetData.roundedCorners : (widgetMetadata.roundedCorners ?? true)
  property string valueMode: widgetData.mode !== undefined ? widgetData.mode : (widgetMetadata.mode ?? "ring")
  property string valueRingColor: widgetData.ringColor !== undefined ? widgetData.ringColor : (widgetMetadata.ringColor ?? "none")
  property bool valueShowPercentage: widgetData.showPercentage !== undefined ? widgetData.showPercentage : (widgetMetadata.showPercentage ?? false)
  property bool valueFullCircle: widgetData.fullCircle !== undefined ? widgetData.fullCircle : (widgetMetadata.fullCircle ?? true)

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showBackground = valueShowBackground;
    settings.roundedCorners = valueRoundedCorners;
    settings.mode = valueMode;
    settings.ringColor = valueRingColor;
    settings.showPercentage = valueShowPercentage;
    settings.fullCircle = valueFullCircle;
    settingsChanged(settings);
    return settings;
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.battery-display-mode-label")
    description: I18n.tr("battery.display-mode-description")
    currentKey: valueMode
    model: [
      {
        "key": "ring",
        "name": I18n.tr("panels.desktop-widgets.battery-mode-ring")
      },
      {
        "key": "list",
        "name": I18n.tr("panels.desktop-widgets.battery-mode-list")
      }
    ]
    onSelected: key => {
                  valueMode = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.mode
  }

  NColorChoice {
    label: I18n.tr("common.select-color")
    description: I18n.tr("common.select-color-description")
    currentKey: valueRingColor
    onSelected: key => {
                  valueRingColor = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.ringColor
  }

  NToggle {
    Layout.fillWidth: true
    visible: valueMode === "ring"
    label: I18n.tr("panels.desktop-widgets.battery-show-percentage-label")
    description: I18n.tr("panels.desktop-widgets.battery-show-percentage-description")
    checked: valueShowPercentage
    onToggled: checked => {
                 valueShowPercentage = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.showPercentage
  }

  NToggle {
    Layout.fillWidth: true
    visible: valueMode === "ring"
    label: I18n.tr("panels.desktop-widgets.battery-full-circle-label")
    description: I18n.tr("panels.desktop-widgets.battery-full-circle-description")
    checked: valueFullCircle
    onToggled: checked => {
                 valueFullCircle = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.fullCircle
  }

  NDivider {
    Layout.fillWidth: true
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.clock-show-background-label")
    description: I18n.tr("panels.desktop-widgets.clock-show-background-description")
    checked: valueShowBackground
    onToggled: checked => {
                 valueShowBackground = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.showBackground
  }

  NToggle {
    Layout.fillWidth: true
    visible: valueShowBackground
    label: I18n.tr("panels.desktop-widgets.clock-rounded-corners-label")
    description: I18n.tr("panels.desktop-widgets.clock-rounded-corners-description")
    checked: valueRoundedCorners
    onToggled: checked => {
                 valueRoundedCorners = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.roundedCorners
  }
}
