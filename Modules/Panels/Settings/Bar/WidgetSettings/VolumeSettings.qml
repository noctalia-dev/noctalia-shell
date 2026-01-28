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

  signal settingsChanged(var settings)

  // Local state
  property string valueDisplayMode: widgetData.displayMode !== undefined ? widgetData.displayMode : widgetMetadata.displayMode
  property string valueMiddleClickCommand: widgetData.middleClickCommand !== undefined ? widgetData.middleClickCommand : widgetMetadata.middleClickCommand

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.displayMode = valueDisplayMode;
    settings.middleClickCommand = valueMiddleClickCommand;
    return settings;
  }

  NComboBox {
    label: I18n.tr("bar.volume.display-mode-label")
    description: I18n.tr("bar.volume.display-mode-description")
    minimumWidth: 134
    model: [
      {
        "key": "onhover",
        "name": I18n.tr("display-modes.on-hover")
      },
      {
        "key": "alwaysShow",
        "name": I18n.tr("display-modes.always-show")
      },
      {
        "key": "alwaysHide",
        "name": I18n.tr("display-modes.always-hide")
      }
    ]
    currentKey: valueDisplayMode
    onSelected: key => {
                  valueDisplayMode = key;
                  settingsChanged(saveSettings());
                }
  }

  // Middle click command
  NTextInput {
    label: I18n.tr("panels.control-center.shortcuts-custom-button-on-middle-clicked-label")
    description: I18n.tr("panels.audio.on-middle-clicked-description")
    placeholderText: I18n.tr("panels.audio.external-mixer-placeholder")
    text: valueMiddleClickCommand
    onTextChanged: valueMiddleClickCommand = text
    onEditingFinished: settingsChanged(saveSettings())
  }
}
