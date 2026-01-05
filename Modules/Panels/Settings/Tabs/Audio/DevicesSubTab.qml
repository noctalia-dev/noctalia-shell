import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Services.Media
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NHeader {
    label: I18n.tr("settings.audio.devices.section.label")
    description: I18n.tr("settings.audio.devices.section.description")
  }

  // Output Devices
  ButtonGroup {
    id: sinks
  }

  ColumnLayout {
    spacing: Style.marginXS
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginL

    NLabel {
      label: I18n.tr("settings.audio.devices.output-device.label")
      description: I18n.tr("settings.audio.devices.output-device.description")
    }

    Repeater {
      model: AudioService.sinks
      NRadioButton {
        ButtonGroup.group: sinks
        required property PwNode modelData
        text: modelData.description
        checked: AudioService.sink?.id === modelData.id
        onClicked: {
          AudioService.setAudioSink(modelData);
        }
        Layout.fillWidth: true
      }
    }
  }

  // Input Devices
  ButtonGroup {
    id: sources
  }

  ColumnLayout {
    spacing: Style.marginXS
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("settings.audio.devices.input-device.label")
      description: I18n.tr("settings.audio.devices.input-device.description")
    }

    Repeater {
      model: AudioService.sources
      NRadioButton {
        ButtonGroup.group: sources
        required property PwNode modelData
        text: modelData.description
        checked: AudioService.source?.id === modelData.id
        onClicked: AudioService.setAudioSource(modelData)
        Layout.fillWidth: true
      }
    }
  }
}
