import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  property int valueWidth: widgetData.width !== undefined ? widgetData.width : widgetMetadata.width
  property int valueHeight: widgetData.height !== undefined ? widgetData.height : widgetMetadata.height
  property string valueVisualizerType: widgetData.visualizerType !== undefined ? widgetData.visualizerType : widgetMetadata.visualizerType
  property string valueColorName: widgetData.colorName !== undefined ? widgetData.colorName : widgetMetadata.colorName
  property bool valueHideWhenIdle: widgetData.hideWhenIdle !== undefined ? widgetData.hideWhenIdle : widgetMetadata.hideWhenIdle
  property bool valueShowBackground: widgetData.showBackground !== undefined ? widgetData.showBackground : widgetMetadata.showBackground
  property bool valueRoundedCorners: widgetData.roundedCorners !== undefined ? widgetData.roundedCorners : widgetMetadata.roundedCorners

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.width = valueWidth;
    settings.height = valueHeight;
    settings.visualizerType = valueVisualizerType;
    settings.colorName = valueColorName;
    settings.hideWhenIdle = valueHideWhenIdle;
    settings.showBackground = valueShowBackground;
    settings.roundedCorners = valueRoundedCorners;
    settingsChanged(settings);
  }

  NTextInput {
    id: widthInput
    Layout.fillWidth: true
    label: I18n.tr("common.width")
    description: I18n.tr("bar.audio-visualizer.width-description")
    text: String(valueWidth)
    placeholderText: I18n.tr("placeholders.enter-width-pixels")
    inputMethodHints: Qt.ImhDigitsOnly
    onEditingFinished: {
      const parsed = parseInt(text);
      if (!isNaN(parsed) && parsed > 0) {
        valueWidth = parsed;
        saveSettings();
      } else {
        text = String(valueWidth);
      }
    }
    defaultValue: String(widgetMetadata.width)
  }

  NTextInput {
    id: heightInput
    Layout.fillWidth: true
    label: I18n.tr("common.height")
    description: I18n.tr("bar.audio-visualizer.height-description")
    text: String(valueHeight)
    placeholderText: I18n.tr("placeholders.enter-width-pixels")
    inputMethodHints: Qt.ImhDigitsOnly
    onEditingFinished: {
      const parsed = parseInt(text);
      if (!isNaN(parsed) && parsed > 0) {
        valueHeight = parsed;
        saveSettings();
      } else {
        text = String(valueHeight);
      }
    }
    defaultValue: String(widgetMetadata.height)
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.audio.visualizer-type-label")
    description: I18n.tr("panels.desktop-widgets.media-player-visualizer-type-description")
    model: [
      {
        "key": "linear",
        "name": I18n.tr("options.visualizer-types.linear")
      },
      {
        "key": "mirrored",
        "name": I18n.tr("options.visualizer-types.mirrored")
      },
      {
        "key": "wave",
        "name": I18n.tr("options.visualizer-types.wave")
      }
    ]
    currentKey: valueVisualizerType
    onSelected: key => {
                  valueVisualizerType = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.visualizerType
  }

  NColorChoice {
    Layout.fillWidth: true
    label: I18n.tr("bar.audio-visualizer.color-name-label")
    description: I18n.tr("bar.audio-visualizer.color-name-description")
    currentKey: valueColorName
    onSelected: key => {
                  valueColorName = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.colorName
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.audio-visualizer.hide-when-idle-label")
    description: I18n.tr("bar.audio-visualizer.hide-when-idle-description")
    checked: valueHideWhenIdle
    onToggled: checked => {
                 valueHideWhenIdle = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.hideWhenIdle
  }

  NDivider {
    Layout.fillWidth: true
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.clock-show-background-label")
    description: I18n.tr("panels.desktop-widgets.media-player-show-background-description")
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
    description: I18n.tr("panels.desktop-widgets.media-player-rounded-corners-description")
    checked: valueRoundedCorners
    onToggled: checked => {
                 valueRoundedCorners = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.roundedCorners
  }
}
