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

  property bool valueShowBackground: widgetData.showBackground !== undefined ? widgetData.showBackground : widgetMetadata.showBackground
  property string valueVisualizerType: widgetData.visualizerType !== undefined ? widgetData.visualizerType : widgetMetadata.visualizerType
  property string valueHideMode: widgetData.hideMode !== undefined ? widgetData.hideMode : widgetMetadata.hideMode
  property string valueVisualizerVisibility: widgetData.visualizerVisibility !== undefined ? widgetData.visualizerVisibility : (widgetMetadata.visualizerVisibility !== undefined ? widgetMetadata.visualizerVisibility : "always")
  property bool valueShowButtons: widgetData.showButtons !== undefined ? widgetData.showButtons : (widgetMetadata.showButtons !== undefined ? widgetMetadata.showButtons : true)

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showBackground = valueShowBackground;
    settings.visualizerType = valueVisualizerType;
    settings.hideMode = valueHideMode;
    settings.visualizerVisibility = valueVisualizerVisibility;
    settings.showButtons = valueShowButtons;
    return settings;
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.media-player.show-background.label")
    description: I18n.tr("settings.desktop-widgets.media-player.show-background.description")
    checked: valueShowBackground
    onToggled: checked => valueShowBackground = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.media-player.show-buttons.label")
    description: I18n.tr("settings.desktop-widgets.media-player.show-buttons.description")
    checked: valueShowButtons
    onToggled: checked => valueShowButtons = checked
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.media-player.visualizer-type.label")
    description: I18n.tr("settings.desktop-widgets.media-player.visualizer-type.description")
    model: [
      {
        "key": "",
        "name": I18n.tr("options.visualizer-types.none")
      },
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
    onSelected: key => valueVisualizerType = key
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.media-player.visualizer-visibility.label")
    description: I18n.tr("settings.desktop-widgets.media-player.visualizer-visibility.description")
    enabled: valueVisualizerType && valueVisualizerType !== "" && valueVisualizerType !== "none"
    model: [
      {
        "key": "always",
        "name": I18n.tr("options.visualizer-visibility.always")
      },
      {
        "key": "with-background",
        "name": I18n.tr("options.visualizer-visibility.with-background")
      }
    ]
    currentKey: valueVisualizerVisibility
    onSelected: key => valueVisualizerVisibility = key
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.media-player.hide-mode.label")
    description: I18n.tr("settings.desktop-widgets.media-player.hide-mode.description")
    model: [
      {
        "key": "hidden",
        "name": I18n.tr("options.hide-modes.hidden")
      },
      {
        "key": "idle",
        "name": I18n.tr("options.hide-modes.idle")
      },
      {
        "key": "visible",
        "name": I18n.tr("options.hide-modes.visible")
      }
    ]
    currentKey: valueHideMode
    onSelected: key => valueHideMode = key
  }
}
