import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Modules.SettingsPanel
import qs.Services
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property real scaling: 1.0
  property string barSection: ""
  property int sectionWidgetIndex: 0
  property int sectionWidgetsCount: 0

  // Used to avoid opening the pill on Quickshell startup
  property bool firstVolumeReceived: false
  property int wheelAccumulator: 0

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

    rightOpen: BarWidgetRegistry.getNPillDirection(root)
    icon: getIcon()
    iconCircleColor: Color.mPrimary
    collapsedIconColor: Color.mOnSurface
    autoHide: false // Important to be false so we can hover as long as we want
    text: Math.floor(AudioService.volume * 100) + "%"
    tooltipText: "Volume: " + Math.round(
                   AudioService.volume * 100) + "%\nLeft click for advanced settings.\nScroll up/down to change volume.\nRight click to toggle mute."

    onWheel: function (delta) {
      wheelAccumulator += delta
      if (wheelAccumulator >= 120) {
        wheelAccumulator = 0
        AudioService.increaseVolume()
      } else if (wheelAccumulator <= -120) {
        wheelAccumulator = 0
        AudioService.decreaseVolume()
      }
    }
    onClicked: {
      var settingsPanel = PanelService.getPanel("settingsPanel")
      settingsPanel.requestedTab = SettingsPanel.Tab.Audio
      settingsPanel.open(screen)
    }
    onRightClicked: {
      AudioService.setMuted(!AudioService.muted)
    }
    // onMiddleClicked: {
    //   Quickshell.execDetached(["pwvucontrol"]);
    // }
  }
}
