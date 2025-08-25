import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Modules.SettingsPanel
import qs.Services
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)

  // Used to avoid opening the pill on Quickshell startup
  property bool firstVolumeReceived: false

  implicitWidth: pill.width
  implicitHeight: pill.height

  function getIcon() {
    if (AudioService.muted) {
      return "volume_off"
    }
    return AudioService.volume <= Number.EPSILON ? "volume_off" : (AudioService.volume < 0.33 ? "volume_down" : "volume_up")
  }

  // Connection used to open the pill when volume changes
  Connections {
    target: AudioService.sink?.audio ? AudioService.sink?.audio : null
    function onVolumeChanged() {
      // Logger.log("Bar:Volume", "onVolumeChanged")
      if (!firstVolumeReceived) {
        // Ignore the first volume change
        firstVolumeReceived = true
      } else {
        pill.show()
        externalHideTimer.restart()
      }
    }
  }

  Timer {
    id: externalHideTimer
    running: false
    interval: 1500
    onTriggered: {
      pill.hide()
    }
  }

  NPill {
    id: pill
    icon: getIcon()
    iconCircleColor: Color.mPrimary
    collapsedIconColor: Color.mOnSurface
    autoHide: false // Important to be false so we can hover as long as we want
    text: Math.floor(AudioService.volume * 100) + "%"
    tooltipText: "Volume: " + Math.round(
                   AudioService.volume * 100) + "%\nLeft click for advanced settings.\nScroll up/down to change volume."

    onWheel: function (angle) {
      if (angle > 0) {
        AudioService.increaseVolume()
      } else if (angle < 0) {
        AudioService.decreaseVolume()
      }
    }
    onClicked: {
      var settingsPanel = PanelService.getPanel("settingsPanel")
      settingsPanel.requestedTab = SettingsPanel.Tab.AudioService
      settingsPanel.open(screen)
    }
  }
}
