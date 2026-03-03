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

  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  property bool valueShowBackground: widgetData.showBackground !== undefined ? widgetData.showBackground : widgetMetadata.showBackground
  property bool valueRoundedCorners: widgetData.roundedCorners !== undefined ? widgetData.roundedCorners : widgetMetadata.roundedCorners
  property string valueWidgetImage: widgetData.image !== undefined ? widgetData.image : ""
  property real valueWidgetOpacity: widgetData.opacity !== undefined ? widgetData.opacity : 1.0

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showBackground = valueShowBackground;
    settings.roundedCorners = valueRoundedCorners;
    settings.image = valueWidgetImage;
    settings.opacity = valueWidgetOpacity;
    settingsChanged(settings);
  }

  RowLayout {
    spacing: Style.marginS

    NLabel {
      label: I18n.tr("panels.desktop-widgets.custom-sticker-selection-title")
      description: I18n.tr("panels.desktop-widgets.custom-sticker-selection-description")
    }

    NIconButton {
      icon: "wallpaper-selector"
      tooltipText: I18n.tr("panels.desktop-widgets.custom-sticker-selection-tooltip")
      onClicked: imageSelection.openFilePicker()
    }

    NFilePicker {
      id: imageSelection
      title: I18n.tr("panels.desktop-widgets.custom-sticker-selection-title")
      selectionMode: "files"

      onAccepted: paths => {
                    if (paths.length > 0) {
                      valueWidgetImage = paths[0];
                      saveSettings();
                    }
                  }
    }
  }
  NValueSlider {
    property real _value: valueWidgetOpacity

    from: 0.0
    to: 1.0
    defaultValue: 1.0
    value: _value
    text: `${_value * 100.0}%`
    label: I18n.tr("panels.desktop-widgets.custom-sticker-opacity-label")
    description: I18n.tr("panels.desktop-widgets.custom-sticker-opacity-description")
    onMoved: value => _value = value
    onPressedChanged: (pressed, value) => {
                        // When slider is let go
                        if (!pressed) {
                          valueWidgetOpacity = value;
                          saveSettings();
                        }
                      }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.custom-sticker-show-background-label")
    description: I18n.tr("panels.desktop-widgets.custom-sticker-show-background-description")
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
    label: I18n.tr("panels.desktop-widgets.custom-sticker-rounded-corners-label")
    description: I18n.tr("panels.desktop-widgets.custom-sticker-rounded-corners-description")
    checked: valueRoundedCorners
    onToggled: checked => {
                 valueRoundedCorners = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.roundedCorners
  }
}
