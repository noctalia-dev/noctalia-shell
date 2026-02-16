import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property string valueHideMode: "hidden" // Default to 'Hide When Empty'
  // Deprecated: hideWhenIdle now folded into hideMode = "idle"
  property bool valueHideWhenIdle: (widgetData && widgetData.hideWhenIdle !== undefined) ? widgetData.hideWhenIdle : (widgetMetadata && widgetMetadata.hideWhenIdle !== undefined ? widgetMetadata.hideWhenIdle : false)
  property bool valueShowAlbumArt: (widgetData && widgetData.showAlbumArt !== undefined) ? widgetData.showAlbumArt : (widgetMetadata && widgetMetadata.showAlbumArt !== undefined ? widgetMetadata.showAlbumArt : false)
  property bool valuePanelShowAlbumArt: (widgetData && widgetData.panelShowAlbumArt !== undefined) ? widgetData.panelShowAlbumArt : (widgetMetadata && widgetMetadata.panelShowAlbumArt !== undefined ? widgetMetadata.panelShowAlbumArt : true)
  property bool valueShowArtistFirst: (widgetData && widgetData.showArtistFirst !== undefined) ? widgetData.showArtistFirst : (widgetMetadata && widgetMetadata.showArtistFirst !== undefined ? widgetMetadata.showArtistFirst : true)
  property bool valueShowVisualizer: (widgetData && widgetData.showVisualizer !== undefined) ? widgetData.showVisualizer : (widgetMetadata && widgetMetadata.showVisualizer !== undefined ? widgetMetadata.showVisualizer : false)
  property string valueVisualizerType: (widgetData && widgetData.visualizerType) || (widgetMetadata && widgetMetadata.visualizerType) || "linear"
  property string valueScrollingMode: (widgetData && widgetData.scrollingMode) || (widgetMetadata && widgetMetadata.scrollingMode) || "hover"
  property int valueMaxWidth: (widgetData && widgetData.maxWidth !== undefined) ? widgetData.maxWidth : (widgetMetadata && widgetMetadata.maxWidth !== undefined ? widgetMetadata.maxWidth : 145)
  property bool valueUseFixedWidth: (widgetData && widgetData.useFixedWidth !== undefined) ? widgetData.useFixedWidth : (widgetMetadata && widgetMetadata.useFixedWidth !== undefined ? widgetMetadata.useFixedWidth : false)
  property bool valueShowProgressRing: (widgetData && widgetData.showProgressRing !== undefined) ? widgetData.showProgressRing : (widgetMetadata && widgetMetadata.showProgressRing !== undefined ? widgetMetadata.showProgressRing : true)
  property bool valueCompactMode: widgetData.compactMode !== undefined ? widgetData.compactMode : widgetMetadata.compactMode
  property string valueTextColor: (widgetData && widgetData.textColor !== undefined) ? widgetData.textColor : (widgetMetadata && widgetMetadata.textColor !== undefined ? widgetMetadata.textColor : "none")

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
    settings.panelShowAlbumArt = valuePanelShowAlbumArt;
    settings.showArtistFirst = valueShowArtistFirst;
    settings.showVisualizer = valueShowVisualizer;
    settings.visualizerType = valueVisualizerType;
    settings.scrollingMode = valueScrollingMode;
    settings.maxWidth = parseInt(widthInput.text) || widgetMetadata.maxWidth;
    settings.useFixedWidth = valueUseFixedWidth;
    settings.showProgressRing = valueShowProgressRing;
    settings.compactMode = valueCompactMode;
    settings.textColor = valueTextColor;
    settingsChanged(settings);
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.hide-mode-label")
    description: I18n.tr("bar.media-mini.hide-mode-description")
    model: [
      {
        "key": "visible",
        "name": I18n.tr("hide-modes.visible")
      },
      {
        "key": "hidden",
        "name": I18n.tr("hide-modes.hidden")
      },
      {
        "key": "transparent",
        "name": I18n.tr("hide-modes.transparent")
      },
      {
        "key": "idle",
        "name": I18n.tr("hide-modes.idle")
      }
    ]
    currentKey: root.valueHideMode
    onSelected: key => {
                  root.valueHideMode = key;
                  saveSettings();
                }
  }

  NToggle {
    label: I18n.tr("bar.media-mini.show-album-art-label")
    description: I18n.tr("bar.media-mini.show-album-art-description")
    checked: valueShowAlbumArt
    onToggled: checked => {
                 valueShowAlbumArt = checked;
                 saveSettings();
               }
  }

  NToggle {
    label: I18n.tr("bar.media-mini.show-artist-first-label")
    description: I18n.tr("bar.media-mini.show-artist-first-description")
    checked: valueShowArtistFirst
    onToggled: checked => {
                 valueShowArtistFirst = checked;
                 saveSettings();
               }
  }

  NToggle {
    label: I18n.tr("bar.media-mini.show-visualizer-label")
    description: I18n.tr("bar.media-mini.show-visualizer-description")
    checked: valueShowVisualizer
    onToggled: checked => {
                 valueShowVisualizer = checked;
                 saveSettings();
               }
  }

  NComboBox {
    visible: valueShowVisualizer
    label: I18n.tr("bar.media-mini.visualizer-type-label")
    description: I18n.tr("bar.media-mini.visualizer-type-description")
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
    minimumWidth: 200
  }

  NTextInput {
    id: widthInput
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.max-width-label")
    description: I18n.tr("bar.media-mini.max-width-description")
    placeholderText: widgetMetadata.maxWidth
    text: valueMaxWidth
    onEditingFinished: saveSettings()
  }

  NToggle {
    label: I18n.tr("bar.media-mini.use-fixed-width-label")
    description: I18n.tr("bar.media-mini.use-fixed-width-description")
    checked: valueUseFixedWidth
    onToggled: checked => {
                 valueUseFixedWidth = checked;
                 saveSettings();
               }
  }

  NToggle {
    label: I18n.tr("bar.media-mini.show-progress-ring-label")
    description: I18n.tr("bar.media-mini.show-progress-ring-description")
    checked: valueShowProgressRing
    onToggled: checked => {
                 valueShowProgressRing = checked;
                 saveSettings();
               }
  }

  NColorChoice {
    currentKey: valueTextColor
    onSelected: key => {
                  valueTextColor = key;
                  saveSettings();
                }
  }

  NComboBox {
    label: I18n.tr("bar.media-mini.scrolling-mode-label")
    description: I18n.tr("bar.media-mini.scrolling-mode-description")
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
    onSelected: key => {
                  valueScrollingMode = key;
                  saveSettings();
                }
    minimumWidth: 200
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
  }

  NLabel {
    label: I18n.tr("bar.media-mini.panel-section-label")
    description: I18n.tr("bar.media-mini.panel-section-description")
    labelColor: Color.mPrimary
  }

  NToggle {
    label: I18n.tr("bar.media-mini.show-album-art-label")
    description: I18n.tr("bar.media-mini.show-album-art-description")
    checked: valuePanelShowAlbumArt
    onToggled: checked => {
                 valuePanelShowAlbumArt = checked;
                 saveSettings();
               }
  }

  NToggle {
    label: I18n.tr("bar.media-mini.compact-mode-label")
    description: I18n.tr("bar.media-mini.compact-mode-description")
    checked: valueCompactMode
    onToggled: checked => {
                 valueCompactMode = checked;
                 saveSettings();
               }
  }
}
