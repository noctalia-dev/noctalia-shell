import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Media
import qs.Widgets

SmartPanel {
  id: root

  property real localOutputVolume: AudioService.volume || 0
  property bool localOutputVolumeChanging: false
  property int lastSinkId: -1

  property real localInputVolume: AudioService.inputVolume || 0
  property bool localInputVolumeChanging: false
  property int lastSourceId: -1

  preferredWidth: Math.round(420 * Style.uiScaleRatio)
  preferredHeight: Math.round(420 * Style.uiScaleRatio)

  // Reset local volume when device changes - use current device's volume
  Connections {
    target: AudioService
    function onSinkChanged() {
      if (AudioService.sink) {
        const newSinkId = AudioService.sink.id;
        if (newSinkId !== lastSinkId) {
          lastSinkId = newSinkId;
          // Immediately set local volume to current device's volume
          localOutputVolume = AudioService.volume;
        }
      } else {
        lastSinkId = -1;
        localOutputVolume = 0;
      }
    }
  }

  Connections {
    target: AudioService
    function onSourceChanged() {
      if (AudioService.source) {
        const newSourceId = AudioService.source.id;
        if (newSourceId !== lastSourceId) {
          lastSourceId = newSourceId;
          // Immediately set local volume to current device's volume
          localInputVolume = AudioService.inputVolume;
        }
      } else {
        lastSourceId = -1;
        localInputVolume = 0;
      }
    }
  }

  // Connections to update local volumes when AudioService changes
  Connections {
    target: AudioService
    function onVolumeChanged() {
      if (!localOutputVolumeChanging && AudioService.sink && AudioService.sink.id === lastSinkId) {
        localOutputVolume = AudioService.volume;
      }
    }
  }

  Connections {
    target: AudioService.sink?.audio ? AudioService.sink?.audio : null
    function onVolumeChanged() {
      if (!localOutputVolumeChanging && AudioService.sink && AudioService.sink.id === lastSinkId) {
        localOutputVolume = AudioService.volume;
      }
    }
  }

  Connections {
    target: AudioService
    function onInputVolumeChanged() {
      if (!localInputVolumeChanging && AudioService.source && AudioService.source.id === lastSourceId) {
        localInputVolume = AudioService.inputVolume;
      }
    }
  }

  Connections {
    target: AudioService.source?.audio ? AudioService.source?.audio : null
    function onVolumeChanged() {
      if (!localInputVolumeChanging && AudioService.source && AudioService.source.id === lastSourceId) {
        localInputVolume = AudioService.inputVolume;
      }
    }
  }

  // Timer to debounce volume changes
  // Only sync if the device hasn't changed (check by comparing IDs)
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      // Only sync if sink hasn't changed
      if (AudioService.sink && AudioService.sink.id === lastSinkId) {
        if (Math.abs(localOutputVolume - AudioService.volume) >= 0.01) {
          AudioService.setVolume(localOutputVolume);
        }
      }
      // Only sync if source hasn't changed
      if (AudioService.source && AudioService.source.id === lastSourceId) {
        if (Math.abs(localInputVolume - AudioService.inputVolume) >= 0.01) {
          AudioService.setInputVolume(localInputVolume);
        }
      }
    }
  }

  panelContent: Item {
    // Use implicitHeight from content + margins to avoid binding loops
    property real contentPreferredHeight: mainColumn.implicitHeight + Style.marginL * 2

    // property real contentPreferredHeight: Math.min(screen.height * 0.42, mainColumn.implicitHeight) + Style.marginL * 2
    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // HEADER
      NBox {
        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight + (Style.marginM * 2)

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            icon: "settings-audio"
            pointSize: Style.fontSizeXXL
            color: Color.mPrimary
          }

          NText {
            text: I18n.tr("settings.audio.title")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NIconButton {
            icon: AudioService.getOutputIcon()
            tooltipText: I18n.tr("tooltips.output-muted")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              AudioService.suppressOutputOSD();
              AudioService.setOutputMuted(!AudioService.muted);
            }
          }

          NIconButton {
            icon: AudioService.getInputIcon()
            tooltipText: I18n.tr("tooltips.input-muted")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              AudioService.suppressInputOSD();
              AudioService.setInputMuted(!AudioService.inputMuted);
            }
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("tooltips.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              root.close();
            }
          }
        }
      }

      NScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded
        clip: true
        contentWidth: availableWidth

        // AudioService Devices
        ColumnLayout {
          spacing: Style.marginM
          width: parent.width

          // -------------------------------
          // Output Devices
          ButtonGroup {
            id: sinks
          }

          NBox {
            Layout.fillWidth: true
            Layout.preferredHeight: outputColumn.implicitHeight + (Style.marginM * 2)

            ColumnLayout {
              id: outputColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.marginM
              spacing: Style.marginS

              NText {
                text: I18n.tr("settings.audio.devices.output-device.label")
                pointSize: Style.fontSizeL
                color: Color.mPrimary
              }

              // Output Volume Slider
              NValueSlider {
                Layout.fillWidth: true
                from: 0
                to: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
                value: localOutputVolume
                stepSize: 0.01
                heightRatio: 0.5
                onMoved: value => localOutputVolume = value
                onPressedChanged: (pressed, value) => localOutputVolumeChanging = pressed
                text: Math.round(localOutputVolume * 100) + "%"
                Layout.bottomMargin: Style.marginM
              }

              Repeater {
                model: AudioService.sinks
                NRadioButton {
                  ButtonGroup.group: sinks
                  required property PwNode modelData
                  pointSize: Style.fontSizeS
                  text: modelData.description
                  checked: AudioService.sink?.id === modelData.id
                  onClicked: {
                    AudioService.setAudioSink(modelData);
                    localOutputVolume = AudioService.volume;
                  }
                  Layout.fillWidth: true
                }
              }
            }
          }

          // -------------------------------
          // Input Devices
          ButtonGroup {
            id: sources
          }

          NBox {
            Layout.fillWidth: true
            Layout.preferredHeight: inputColumn.implicitHeight + (Style.marginM * 2)

            ColumnLayout {
              id: inputColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.margins: Style.marginM
              spacing: Style.marginS

              NText {
                text: I18n.tr("settings.audio.devices.input-device.label")
                pointSize: Style.fontSizeL
                color: Color.mPrimary
              }

              // Input Volume Slider
              NValueSlider {
                Layout.fillWidth: true
                from: 0
                to: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
                value: localInputVolume
                stepSize: 0.01
                heightRatio: 0.5
                onMoved: value => localInputVolume = value
                onPressedChanged: (pressed, value) => localInputVolumeChanging = pressed
                text: Math.round(localInputVolume * 100) + "%"
                Layout.bottomMargin: Style.marginM
              }

              Repeater {
                model: AudioService.sources
                NRadioButton {
                  ButtonGroup.group: sources
                  required property PwNode modelData
                  pointSize: Style.fontSizeS
                  text: modelData.description
                  checked: AudioService.source?.id === modelData.id
                  onClicked: AudioService.setAudioSource(modelData)
                  Layout.fillWidth: true
                }
              }
            }
          }
        }
      }
    }
  }
}
