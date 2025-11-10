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

  NHeader {
    label: I18n.tr("settings.audio.volumes.section.label")
    description: I18n.tr("settings.audio.volumes.section.description")
  }

  property real localVolume: AudioService.volume

  Connections {
    target: AudioService.sink?.audio ? AudioService.sink?.audio : null
    function onVolumeChanged() {
      localVolume = AudioService.volume
    }
  }

  // Master Volume
  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("settings.audio.volumes.output-volume.label")
      description: I18n.tr("settings.audio.volumes.output-volume.description")
    }

    // Pipewire seems a bit finicky, if we spam too many volume changes it breaks easily
    // Probably because they have some quick fades in and out to avoid clipping
    // We use a timer to space out the updates, to avoid lock up
    Timer {
      interval: 100
      running: true
      repeat: true
      onTriggered: {
        if (Math.abs(localVolume - AudioService.volume) >= 0.01) {
          AudioService.setVolume(localVolume)
        }
      }
    }

    NValueSlider {
      Layout.fillWidth: true
      from: 0
      to: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
      value: localVolume
      stepSize: 0.01
      text: Math.round(AudioService.volume * 100) + "%"
      onMoved: value => localVolume = value
    }
  }

  // Mute Toggle
  ColumnLayout {
    spacing: Style.marginS
    Layout.fillWidth: true

    NToggle {
      label: I18n.tr("settings.audio.volumes.mute-output.label")
      description: I18n.tr("settings.audio.volumes.mute-output.description")
      checked: AudioService.muted
      onToggled: checked => {
                   if (AudioService.sink && AudioService.sink.audio) {
                     AudioService.sink.audio.muted = checked
                   }
                 }
    }
  }

  // Input Volume
  ColumnLayout {
    spacing: Style.marginXS
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("settings.audio.volumes.input-volume.label")
      description: I18n.tr("settings.audio.volumes.input-volume.description")
    }

    NValueSlider {
      Layout.fillWidth: true
      from: 0
      to: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
      value: AudioService.inputVolume
      stepSize: 0.01
      text: Math.round(AudioService.inputVolume * 100) + "%"
      onMoved: value => AudioService.setInputVolume(value)
    }
  }

  // Input Mute Toggle
  ColumnLayout {
    spacing: Style.marginS
    Layout.fillWidth: true

    NToggle {
      label: I18n.tr("settings.audio.volumes.mute-input.label")
      description: I18n.tr("settings.audio.volumes.mute-input.description")
      checked: AudioService.inputMuted
      onToggled: checked => AudioService.setInputMuted(checked)
    }
  }

  // Volume Step Size
  ColumnLayout {
    spacing: Style.marginS
    Layout.fillWidth: true

    NSpinBox {
      Layout.fillWidth: true
      label: I18n.tr("settings.audio.volumes.step-size.label")
      description: I18n.tr("settings.audio.volumes.step-size.description")
      minimum: 1
      maximum: 25
      value: Settings.data.audio.volumeStep
      stepSize: 1
      suffix: "%"
      onValueChanged: Settings.data.audio.volumeStep = value
    }
  }

  // Raise maximum volume above 100%
  ColumnLayout {
    spacing: Style.marginS
    Layout.fillWidth: true

    NToggle {
      label: I18n.tr("settings.audio.volumes.volume-overdrive.label")
      description: I18n.tr("settings.audio.volumes.volume-overdrive.description")
      checked: Settings.data.audio.volumeOverdrive
      onToggled: checked => Settings.data.audio.volumeOverdrive = checked
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // AudioService Devices
  ColumnLayout {
    spacing: Style.marginS
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.audio.devices.section.label")
      description: I18n.tr("settings.audio.devices.section.description")
    }

    // -------------------------------
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
            AudioService.setAudioSink(modelData)
            localVolume = AudioService.volume
          }
          Layout.fillWidth: true
        }
      }
    }

    // -------------------------------
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
        //Layout.fillWidth: true
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

  // Divider
  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Media Player Preferences
  ColumnLayout {
    spacing: Style.marginL

    NHeader {
      label: I18n.tr("settings.audio.media.section.label")
      description: I18n.tr("settings.audio.media.section.description")
    }

    // Preferred player
    NTextInput {
      label: I18n.tr("settings.audio.media.primary-player.label")
      description: I18n.tr("settings.audio.media.primary-player.description")
      placeholderText: I18n.tr("settings.audio.media.primary-player.placeholder")
      text: Settings.data.audio.preferredPlayer
      onTextChanged: {
        Settings.data.audio.preferredPlayer = text
        MediaService.updateCurrentPlayer()
      }
    }

    // Blacklist editor
    ColumnLayout {
      spacing: Style.marginS
      Layout.fillWidth: true

      NTextInputButton {
        id: blacklistInput
        label: I18n.tr("settings.audio.media.excluded-player.label")
        description: I18n.tr("settings.audio.media.excluded-player.description")
        placeholderText: I18n.tr("settings.audio.media.excluded-player.placeholder")
        buttonIcon: "add"
        Layout.fillWidth: true
        onButtonClicked: {
          const val = (blacklistInput.text || "").trim()
          if (val !== "") {
            const arr = (Settings.data.audio.mprisBlacklist || [])
            if (!arr.find(x => String(x).toLowerCase() === val.toLowerCase())) {
              Settings.data.audio.mprisBlacklist = [...arr, val]
              blacklistInput.text = ""
              MediaService.updateCurrentPlayer()
            }
          }
        }
      }

      // Current blacklist entries
      Flow {
        Layout.fillWidth: true
        Layout.leftMargin: Style.marginS
        spacing: Style.marginS

        Repeater {
          model: Settings.data.audio.mprisBlacklist
          delegate: Rectangle {
            required property string modelData
            // Padding around the inner row
            property real pad: Style.marginS
            // Visuals
            color: Qt.alpha(Color.mOnSurface, 0.125)
            border.color: Qt.alpha(Color.mOnSurface, Style.opacityLight)
            border.width: Style.borderS

            // Content
            RowLayout {
              id: chipRow
              spacing: Style.marginXS
              anchors.fill: parent
              anchors.margins: pad

              NText {
                text: modelData
                color: Color.mOnSurface
                pointSize: Style.fontSizeS
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: Style.marginS
              }

              NIconButton {
                icon: "close"
                baseSize: Style.baseWidgetSize * 0.8
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: Style.marginXS
                onClicked: {
                  const arr = (Settings.data.audio.mprisBlacklist || [])
                  const idx = arr.findIndex(x => String(x) === modelData)
                  if (idx >= 0) {
                    arr.splice(idx, 1)
                    Settings.data.audio.mprisBlacklist = arr
                    MediaService.updateCurrentPlayer()
                  }
                }
              }
            }

            // Intrinsic size derived from inner row + padding
            implicitWidth: chipRow.implicitWidth + pad * 2
            implicitHeight: Math.max(chipRow.implicitHeight + pad * 2, Style.baseWidgetSize * 0.8)
            radius: Style.radiusM
          }
        }
      }
    }
    // AudioService Visualizer section
    NComboBox {
      label: I18n.tr("settings.audio.media.visualizer-type.label")
      description: I18n.tr("settings.audio.media.visualizer-type.description")
      model: [{
          "key": "none",
          "name": I18n.tr("options.visualizer-types.none")
        }, {
          "key": "linear",
          "name": I18n.tr("options.visualizer-types.linear")
        }, {
          "key": "mirrored",
          "name": I18n.tr("options.visualizer-types.mirrored")
        }, {
          "key": "wave",
          "name": I18n.tr("options.visualizer-types.wave")
        }]
      currentKey: Settings.data.audio.visualizerType
      onSelected: key => Settings.data.audio.visualizerType = key
    }

    NComboBox {
      label: I18n.tr("settings.audio.media.visualizer-quality.label")
      description: I18n.tr("settings.audio.media.visualizer-quality.description")
      model: [{
          "key": "low",
          "name": I18n.tr("options.visualizer-quality.low")
        }, {
          "key": "high",
          "name": I18n.tr("options.visualizer-quality.high")
        }]
      currentKey: Settings.data.audio.visualizerQuality
      onSelected: key => Settings.data.audio.visualizerQuality = key
    }

    NComboBox {
      label: I18n.tr("settings.audio.media.frame-rate.label")
      description: I18n.tr("settings.audio.media.frame-rate.description")
      model: [{
          "key": "30",
          "name": I18n.tr("options.frame-rates.fps", {
                            "fps": "30"
                          })
        }, {
          "key": "60",
          "name": I18n.tr("options.frame-rates.fps", {
                            "fps": "60"
                          })
        }, {
          "key": "100",
          "name": I18n.tr("options.frame-rates.fps", {
                            "fps": "100"
                          })
        }, {
          "key": "120",
          "name": I18n.tr("options.frame-rates.fps", {
                            "fps": "120"
                          })
        }, {
          "key": "144",
          "name": I18n.tr("options.frame-rates.fps", {
                            "fps": "144"
                          })
        }, {
          "key": "165",
          "name": I18n.tr("options.frame-rates.fps", {
                            "fps": "165"
                          })
        }, {
          "key": "240",
          "name": I18n.tr("options.frame-rates.fps", {
                            "fps": "240"
                          })
        }]
      currentKey: Settings.data.audio.cavaFrameRate
      onSelected: key => Settings.data.audio.cavaFrameRate = key
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
