import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Media
import qs.Widgets

// Audio controls card: output and input volume controls
NBox {
  id: root

  property real localOutputVolume: 0
  property bool localOutputVolumeChanging: false
  property int lastSinkId: -1

  property real localInputVolume: 0
  property bool localInputVolumeChanging: false
  property int lastSourceId: -1

  Component.onCompleted: {
    var vol = AudioService.volume;
    localOutputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
    var inputVol = AudioService.inputVolume;
    localInputVolume = (inputVol !== undefined && !isNaN(inputVol)) ? inputVol : 0;
    if (AudioService.sink) {
      lastSinkId = AudioService.sink.id;
    }
    if (AudioService.source) {
      lastSourceId = AudioService.source.id;
    }
  }

  // Reset local volume when device changes - use current device's volume
  Connections {
    target: AudioService
    function onSinkChanged() {
      if (AudioService.sink) {
        const newSinkId = AudioService.sink.id;
        if (newSinkId !== lastSinkId) {
          lastSinkId = newSinkId;
          // Immediately set local volume to current device's volume
          var vol = AudioService.volume;
          localOutputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
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
          var vol = AudioService.inputVolume;
          localInputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
        }
      } else {
        lastSourceId = -1;
        localInputVolume = 0;
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

  // Connections to update local volumes when AudioService changes
  Connections {
    target: AudioService
    function onVolumeChanged() {
      if (!localOutputVolumeChanging && AudioService.sink && AudioService.sink.id === lastSinkId) {
        var vol = AudioService.volume;
        localOutputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
      }
    }
  }

  Connections {
    target: AudioService.sink?.audio ? AudioService.sink?.audio : null
    function onVolumeChanged() {
      if (!localOutputVolumeChanging && AudioService.sink && AudioService.sink.id === lastSinkId) {
        var vol = AudioService.volume;
        localOutputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
      }
    }
  }

  Connections {
    target: AudioService
    function onInputVolumeChanged() {
      if (!localInputVolumeChanging && AudioService.source && AudioService.source.id === lastSourceId) {
        var vol = AudioService.inputVolume;
        localInputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
      }
    }
  }

  Connections {
    target: AudioService.source?.audio ? AudioService.source?.audio : null
    function onVolumeChanged() {
      if (!localInputVolumeChanging && AudioService.source && AudioService.source.id === lastSourceId) {
        var vol = AudioService.inputVolume;
        localInputVolume = (vol !== undefined && !isNaN(vol)) ? vol : 0;
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
              AudioService.sink.audio.muted = !AudioService.muted;
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
          Layout.preferredWidth: 0
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
          Layout.preferredWidth: 0
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
