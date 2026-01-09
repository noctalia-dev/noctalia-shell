import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Modules.Panels.Settings
import qs.Services.Media
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property bool isBarVertical: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
  readonly property string displayMode: (widgetSettings.displayMode !== undefined) ? widgetSettings.displayMode : widgetMetadata.displayMode

  // Used to avoid opening the pill on Quickshell startup
  property bool firstInputVolumeReceived: false
  property int wheelAccumulator: 0

  implicitWidth: pill.width
  implicitHeight: pill.height

  // Connection used to open the pill when input volume changes
  Connections {
    target: AudioService.source?.audio ? AudioService.source?.audio : null
    function onVolumeChanged() {
      // Logger.i("Bar:Microphone", "onInputVolumeChanged")
      if (!firstInputVolumeReceived) {
        // Ignore the first volume change
        firstInputVolumeReceived = true;
      } else {
        // If a tooltip is visible while we show the pill
        // hide it so it doesn't overlap the volume slider.
        TooltipService.hide();
        pill.show();
        externalHideTimer.restart();
      }
    }
  }

  // Connection used to open the pill when input mute state changes
  Connections {
    target: AudioService.source?.audio ? AudioService.source?.audio : null
    function onMutedChanged() {
      // Logger.i("Bar:Microphone", "onInputMutedChanged")
      if (!firstInputVolumeReceived) {
        // Ignore the first mute change
        firstInputVolumeReceived = true;
      } else {
        TooltipService.hide();
        pill.show();
        externalHideTimer.restart();
      }
    }
  }

  Timer {
    id: externalHideTimer
    running: false
    interval: 1500
    onTriggered: {
      pill.hide();
    }
  }

  function openExternalMixer() {
    Quickshell.execDetached(["sh", "-c", Settings.data.audio.externalMixer]);
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.toggle-mute"),
        "action": "toggle-mute",
        "icon": AudioService.inputMuted ? "microphone-off" : "microphone"
      },
      {
        "label": I18n.tr("actions.open-mixer"),
        "action": "open-mixer",
        "icon": "adjustments"
      },
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   if (action === "toggle-mute") {
                     AudioService.setInputMuted(!AudioService.inputMuted);
                   } else if (action === "open-mixer") {
                     root.openExternalMixer();
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  BarPill {
    id: pill

    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: AudioService.getInputIcon()
    autoHide: false // Important to be false so we can hover as long as we want
    text: {
      const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
      const displayVolume = Math.min(maxVolume, AudioService.inputVolume);
      return Math.round(displayVolume * 100);
    }
    suffix: "%"
    forceOpen: displayMode === "alwaysShow"
    forceClose: displayMode === "alwaysHide"
    tooltipText: I18n.tr("tooltips.microphone-volume-at", {
                           "volume": (() => {
                                        const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
                                        const displayVolume = Math.min(maxVolume, AudioService.inputVolume);
                                        return Math.round(displayVolume * 100);
                                      })()
                         })

    onWheel: function (delta) {
      // As soon as we start scrolling to adjust volume, hide the tooltip
      TooltipService.hide();

      wheelAccumulator += delta;
      if (wheelAccumulator >= 120) {
        wheelAccumulator = 0;
        AudioService.setInputVolume(AudioService.inputVolume + AudioService.stepVolume);
      } else if (wheelAccumulator <= -120) {
        wheelAccumulator = 0;
        AudioService.setInputVolume(AudioService.inputVolume - AudioService.stepVolume);
      }
    }
    onClicked: {
      PanelService.getPanel("audioPanel", screen)?.toggle(this);
    }
    onRightClicked: {
      var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
      if (popupMenuWindow) {
        popupMenuWindow.showContextMenu(contextMenu);
        contextMenu.openAtItem(pill, screen);
      }
    }
    onMiddleClicked: root.openExternalMixer()
  }
}
