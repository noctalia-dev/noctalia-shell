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
  property string valueVisualizerType: (widgetData.visualizerType && widgetData.visualizerType !== "") ? widgetData.visualizerType : (widgetMetadata.visualizerType || "linear")
  property string valueHideMode: widgetData.hideMode !== undefined ? widgetData.hideMode : widgetMetadata.hideMode
  property bool valueShowButtons: widgetData.showButtons !== undefined ? widgetData.showButtons : (widgetMetadata.showButtons !== undefined ? widgetMetadata.showButtons : true)
  property bool valueShowAlbumArt: widgetData.showAlbumArt !== undefined ? widgetData.showAlbumArt : (widgetMetadata.showAlbumArt !== undefined ? widgetMetadata.showAlbumArt : true)
  property bool valueShowVisualizer: widgetData.showVisualizer !== undefined ? widgetData.showVisualizer : (widgetMetadata.showVisualizer !== undefined ? widgetMetadata.showVisualizer : true)
  property bool valueRoundedCorners: widgetData.roundedCorners !== undefined ? widgetData.roundedCorners : (widgetMetadata.roundedCorners !== undefined ? widgetMetadata.roundedCorners : true)

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showBackground = valueShowBackground;
    settings.visualizerType = valueVisualizerType;
    settings.hideMode = valueHideMode;
    settings.showButtons = valueShowButtons;
    settings.showAlbumArt = valueShowAlbumArt;
    settings.showVisualizer = valueShowVisualizer;
    settings.roundedCorners = valueRoundedCorners;

    // Clean up legacy property
    delete settings.visualizerVisibility;

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
    label: I18n.tr("settings.desktop-widgets.media-player.rounded-corners.label")
    description: I18n.tr("settings.desktop-widgets.media-player.rounded-corners.description")
    checked: valueRoundedCorners
    onToggled: checked => valueRoundedCorners = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.media-player.show-album-art.label")
    description: I18n.tr("settings.desktop-widgets.media-player.show-album-art.description")
    checked: valueShowAlbumArt
    onToggled: checked => valueShowAlbumArt = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.media-player.show-visualizer.label")
    description: I18n.tr("settings.desktop-widgets.media-player.show-visualizer.description")
    checked: valueShowVisualizer
    onToggled: checked => valueShowVisualizer = checked
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
    enabled: valueShowVisualizer
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
    onSelected: key => valueVisualizerType = key
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
