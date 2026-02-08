import QtQuick
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
  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
  readonly property string displayMode: (widgetSettings.displayMode !== undefined) ? widgetSettings.displayMode : widgetMetadata.displayMode
  readonly property string middleClickCommand: (widgetSettings.middleClickCommand !== undefined) ? widgetSettings.middleClickCommand : widgetMetadata.middleClickCommand
  readonly property string iconColorKey: widgetSettings.iconColor !== undefined ? widgetSettings.iconColor : widgetMetadata.iconColor
  readonly property string textColorKey: widgetSettings.textColor !== undefined ? widgetSettings.textColor : widgetMetadata.textColor
  readonly property bool reverseScroll: Settings.data.general.reverseScroll

  // Used to avoid opening the pill on Quickshell startup
  property bool firstVolumeReceived: false
  property int wheelAccumulator: 0

  implicitWidth: pill.width
  implicitHeight: pill.height

  // Connection used to open the pill when volume changes
  Connections {
    target: AudioService.sink?.audio ? AudioService.sink?.audio : null
    function onVolumeChanged() {
      // Logger.i("Bar:Volume", "onVolumeChanged")
      if (!firstVolumeReceived) {
        // Ignore the first volume change
        firstVolumeReceived = true;
      } else {
        // Hide any tooltip while the pill is visible / being updated
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

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.toggle-mute"),
        "action": "toggle-mute",
        "icon": AudioService.muted ? "volume-off" : "volume"
      },
      {
        "label": I18n.tr("actions.run-custom-command"),
        "action": "custom-command",
        "icon": "adjustments"
      },
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "toggle-mute") {
                     AudioService.setOutputMuted(!AudioService.muted);
                   } else if (action === "custom-command") {
                     Quickshell.execDetached(["sh", "-c", middleClickCommand]);
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  BarPill {
    id: pill

    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    customIconColor: Color.resolveColorKeyOptional(root.iconColorKey)
    customTextColor: Color.resolveColorKeyOptional(root.textColorKey)
    icon: AudioService.getOutputIcon()
    autoHide: false // Important to be false so we can hover as long as we want
    text: {
      const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
      const displayVolume = Math.min(maxVolume, AudioService.volume);
      return Math.round(displayVolume * 100);
    }
    suffix: "%"
    forceOpen: displayMode === "alwaysShow"
    forceClose: displayMode === "alwaysHide"
    tooltipText: I18n.tr("tooltips.volume-at", {
                           "volume": (() => {
                                        const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
                                        const displayVolume = Math.min(maxVolume, AudioService.volume);
                                        return Math.round(displayVolume * 100);
                                      })()
                         })

    onWheel: function (delta) {
      // Hide tooltip as soon as the user starts scrolling to adjust volume
      TooltipService.hide();

      if (root.reverseScroll)
        delta *= -1;

      wheelAccumulator += delta;
      if (wheelAccumulator >= 120) {
        wheelAccumulator = 0;
        AudioService.increaseVolume();
      } else if (wheelAccumulator <= -120) {
        wheelAccumulator = 0;
        AudioService.decreaseVolume();
      }
    }
    onClicked: {
      PanelService.getPanel("audioPanel", screen)?.toggle(this);
    }
    onRightClicked: {
      PanelService.showContextMenu(contextMenu, pill, screen);
    }
    onMiddleClicked: {
      Quickshell.execDetached(["sh", "-c", middleClickCommand]);
    }
  }
}
