import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property string valueHideMode: "hidden" // Default to 'Hide When Empty'
  // Deprecated: hideWhenIdle now folded into hideMode = "idle"
  property bool valueHideWhenIdle: widgetData.hideWhenIdle !== undefined ? widgetData.hideWhenIdle : widgetMetadata.hideWhenIdle
  property bool valueShowAlbumArt: widgetData.showAlbumArt !== undefined ? widgetData.showAlbumArt : widgetMetadata.showAlbumArt
  property bool valueShowArtistFirst: widgetData.showArtistFirst !== undefined ? widgetData.showArtistFirst : widgetMetadata.showArtistFirst
  property bool valueShowVisualizer: widgetData.showVisualizer !== undefined ? widgetData.showVisualizer : widgetMetadata.showVisualizer
  property string valueVisualizerType: widgetData.visualizerType || widgetMetadata.visualizerType
  property string valueScrollingMode: widgetData.scrollingMode || widgetMetadata.scrollingMode
  property int valueMaxWidth: widgetData.maxWidth !== undefined ? widgetData.maxWidth : widgetMetadata.maxWidth
  property bool valueUseFixedWidth: widgetData.useFixedWidth !== undefined ? widgetData.useFixedWidth : widgetMetadata.useFixedWidth
  property bool valueShowProgressRing: widgetData.showProgressRing !== undefined ? widgetData.showProgressRing : widgetMetadata.showProgressRing

  Component.onCompleted: {
    if (widgetData && widgetData.hideMode !== undefined) {
      valueHideMode = widgetData.hideMode;
    }
  }

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.hideMode = valueHideMode;
    // No longer store hideWhenIdle separately; kept for backward compatibility only
    settings.showAlbumArt = valueShowAlbumArt;
    settings.showArtistFirst = valueShowArtistFirst;
    settings.showVisualizer = valueShowVisualizer;
    settings.visualizerType = valueVisualizerType;
    settings.scrollingMode = valueScrollingMode;
    settings.maxWidth = parseInt(widthInput.text) || widgetMetadata.maxWidth;
    settings.useFixedWidth = valueUseFixedWidth;
    settings.showProgressRing = valueShowProgressRing;
    return settings;
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.media-mini.hide-mode.label")
    description: I18n.tr("bar.widget-settings.media-mini.hide-mode.description")
    model: [
      {
        "key": "visible",
        "name": I18n.tr("options.hide-modes.visible")
      },
      {
        "key": "hidden",
        "name": I18n.tr("options.hide-modes.hidden")
      },
      {
        "key": "transparent",
        "name": I18n.tr("options.hide-modes.transparent")
      },
      {
        "key": "idle",
        "name": I18n.tr("options.hide-modes.idle")
      }
    ]
    currentKey: root.valueHideMode
    onSelected: key => root.valueHideMode = key
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.media-mini.show-album-art.label")
    description: I18n.tr("bar.widget-settings.media-mini.show-album-art.description")
    checked: valueShowAlbumArt
    onToggled: checked => valueShowAlbumArt = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.media-mini.show-artist-first.label")
    description: I18n.tr("bar.widget-settings.media-mini.show-artist-first.description")
    checked: valueShowArtistFirst
    onToggled: checked => valueShowArtistFirst = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.media-mini.show-visualizer.label")
    description: I18n.tr("bar.widget-settings.media-mini.show-visualizer.description")
    checked: valueShowVisualizer
    onToggled: checked => valueShowVisualizer = checked
  }

  NComboBox {
    visible: valueShowVisualizer
    label: I18n.tr("bar.widget-settings.media-mini.visualizer-type.label")
    description: I18n.tr("bar.widget-settings.media-mini.visualizer-type.description")
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
    minimumWidth: 200
  }

  NTextInput {
    id: widthInput
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.media-mini.max-width.label")
    description: I18n.tr("bar.widget-settings.media-mini.max-width.description")
    placeholderText: widgetMetadata.maxWidth
    text: valueMaxWidth
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.media-mini.use-fixed-width.label")
    description: I18n.tr("bar.widget-settings.media-mini.use-fixed-width.description")
    checked: valueUseFixedWidth
    onToggled: checked => valueUseFixedWidth = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.media-mini.show-progress-ring.label")
    description: I18n.tr("bar.widget-settings.media-mini.show-progress-ring.description")
    checked: valueShowProgressRing
    onToggled: checked => valueShowProgressRing = checked
  }

  NComboBox {
    label: I18n.tr("bar.widget-settings.media-mini.scrolling-mode.label")
    description: I18n.tr("bar.widget-settings.media-mini.scrolling-mode.description")
    model: [
      {
        "key": "always",
        "name": I18n.tr("options.scrolling-modes.always")
      },
      {
        "key": "hover",
        "name": I18n.tr("options.scrolling-modes.hover")
      },
      {
        "key": "never",
        "name": I18n.tr("options.scrolling-modes.never")
      }
    ]
    currentKey: valueScrollingMode
    onSelected: key => valueScrollingMode = key
    minimumWidth: 200
  }
}
