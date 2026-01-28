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
    label: I18n.tr("panels.desktop-widgets.clock-show-background-label")
    description: I18n.tr("panels.desktop-widgets.media-player-show-background-description")
    checked: valueShowBackground
    onToggled: checked => {
                 valueShowBackground = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.clock-rounded-corners-label")
    description: I18n.tr("panels.desktop-widgets.media-player-rounded-corners-description")
    checked: valueRoundedCorners
    onToggled: checked => {
                 valueRoundedCorners = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.media-player-show-album-art-label")
    description: I18n.tr("panels.desktop-widgets.media-player-show-album-art-description")
    checked: valueShowAlbumArt
    onToggled: checked => {
                 valueShowAlbumArt = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.media-mini.show-visualizer-label")
    description: I18n.tr("panels.desktop-widgets.media-player-show-visualizer-description")
    checked: valueShowVisualizer
    onToggled: checked => {
                 valueShowVisualizer = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.media-player-show-buttons-label")
    description: I18n.tr("panels.desktop-widgets.media-player-show-buttons-description")
    checked: valueShowButtons
    onToggled: checked => {
                 valueShowButtons = checked;
                 settingsChanged(saveSettings());
               }
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.audio.visualizer-type-label")
    description: I18n.tr("panels.desktop-widgets.media-player-visualizer-type-description")
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
    onSelected: key => {
                  valueVisualizerType = key;
                  settingsChanged(saveSettings());
                }
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.hide-mode-label")
    description: I18n.tr("bar.media-mini.hide-mode-description")
    model: [
      {
        "key": "hidden",
        "name": I18n.tr("hide-modes.hidden")
      },
      {
        "key": "idle",
        "name": I18n.tr("hide-modes.idle")
      },
      {
        "key": "visible",
        "name": I18n.tr("hide-modes.visible")
      }
    ]
    currentKey: valueHideMode
    onSelected: key => {
                  valueHideMode = key;
                  settingsChanged(saveSettings());
                }
  }
}
