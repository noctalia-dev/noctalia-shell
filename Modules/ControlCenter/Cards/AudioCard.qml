import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

// Audio controls card: output and input volume controls
NBox {
  id: root

  property real localOutputVolume: AudioService.volume || 0
  property bool localOutputVolumeChanging: false

  property real localInputVolume: AudioService.inputVolume || 0
  property bool localInputVolumeChanging: false

  // Timer to debounce volume changes
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (Math.abs(localOutputVolume - AudioService.volume) >= 0.01) {
        AudioService.setVolume(localOutputVolume)
      }
      if (Math.abs(localInputVolume - AudioService.inputVolume) >= 0.01) {
        AudioService.setInputVolume(localInputVolume)
      }
    }
  }

  // Connections to update local volumes when AudioService changes
  Connections {
    target: AudioService.sink?.audio ? AudioService.sink?.audio : null
    function onVolumeChanged() {
      if (!localOutputVolumeChanging) {
        localOutputVolume = AudioService.volume
      }
    }
  }

  Connections {
    target: AudioService.source?.audio ? AudioService.source?.audio : null
    function onVolumeChanged() {
      if (!localInputVolumeChanging) {
        localInputVolume = AudioService.inputVolume
      }
    }
  }

  RowLayout {
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginM

    // Output Volume Section
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true
      Layout.preferredWidth: 0
      opacity: AudioService.sink ? 1.0 : 0.5
      enabled: AudioService.sink

      // Output Volume Header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS

        NIconButton {
          icon: AudioService.muted ? "volume-off" : "volume-high"
          baseSize: Style.baseWidgetSize * 0.5
          colorFg: AudioService.muted ? Color.mError : Color.mOnSurface
          colorBg: Color.transparent
          colorBgHover: Color.mHover
          colorFgHover: Color.mOnHover
          onClicked: {
            if (AudioService.sink && AudioService.sink.audio) {
              AudioService.sink.audio.muted = !AudioService.muted
            }
          }
        }

        NText {
          text: AudioService.sink ? AudioService.sink.description : "No output device"
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
          font.weight: Style.fontWeightMedium
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      // Output Volume Slider
      NSlider {
        Layout.fillWidth: true
        from: 0
        to: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
        value: localOutputVolume
        stepSize: 0.01
        heightRatio: 0.5
        onMoved: localOutputVolume = value
        onPressedChanged: localOutputVolumeChanging = pressed
        tooltipText: `${Math.round(localOutputVolume * 100)}%`
        tooltipDirection: "bottom"
      }
    }

    // Input Volume Section
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true
      Layout.preferredWidth: 0
      opacity: AudioService.source ? 1.0 : 0.5
      enabled: AudioService.source

      // Input Volume Header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS

        NIconButton {
          icon: AudioService.inputMuted ? "microphone-off" : "microphone"
          baseSize: Style.baseWidgetSize * 0.5
          colorFg: AudioService.inputMuted ? Color.mError : Color.mOnSurface
          colorBg: Color.transparent
          colorBgHover: Color.mHover
          colorFgHover: Color.mOnHover
          onClicked: AudioService.setInputMuted(!AudioService.inputMuted)
        }

        NText {
          text: AudioService.source ? AudioService.source.description : "No input device"
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
          font.weight: Style.fontWeightMedium
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      // Input Volume Slider
      NSlider {
        Layout.fillWidth: true
        from: 0
        to: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
        value: localInputVolume
        stepSize: 0.01
        heightRatio: 0.5
        onMoved: localInputVolume = value
        onPressedChanged: localInputVolumeChanging = pressed
        tooltipText: `${Math.round(localInputVolume * 100)}%`
        tooltipDirection: "bottom"
      }
    }
  }
}
