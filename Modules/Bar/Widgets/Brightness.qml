import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Modules.Panels.Settings
import qs.Services.Hardware
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
  property bool firstBrightnessReceived: false

  implicitWidth: pill.width
  implicitHeight: pill.height
  visible: getMonitor() !== null
  opacity: getMonitor() !== null ? 1.0 : 0.0

  function getMonitor() {
    return BrightnessService.getMonitorForScreen(screen) || null;
  }

  function getIcon() {
    var monitor = getMonitor();
    var brightness = monitor ? monitor.brightness : 0;
    if (brightness <= 0.001)
      return "sun-off";
    return brightness <= 0.5 ? "brightness-low" : "brightness-high";
  }

  // Connection used to open the pill when brightness changes
  Connections {
    target: getMonitor()
    ignoreUnknownSignals: true
    function onBrightnessUpdated() {
      // Ignore if this is the first time we receive an update.
      // Most likely service just kicked off.
      if (!firstBrightnessReceived) {
        firstBrightnessReceived = true;
        return;
      }

      pill.show();
      hideTimerAfterChange.restart();
    }
  }

  Timer {
    id: hideTimerAfterChange
    interval: 2500
    running: false
    repeat: false
    onTriggered: pill.hide()
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("context-menu.open-display-settings"),
        "action": "open-display-settings",
        "icon": "sun"
      },
      {
        "label": I18n.tr("context-menu.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   if (action === "open-display-settings") {
                     var settingsPanel = PanelService.getPanel("settingsPanel", screen);
                     settingsPanel.requestedTab = SettingsPanel.Tab.Display;
                     settingsPanel.open();
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  BarPill {
    id: pill

    screen: root.screen
    density: Settings.data.bar.density
    oppositeDirection: BarService.getPillDirection(root)
    icon: getIcon()
    autoHide: false // Important to be false so we can hover as long as we want
    text: {
      var monitor = getMonitor();
      return monitor ? Math.round(monitor.brightness * 100) : "";
    }
    suffix: text.length > 0 ? "%" : "-"
    forceOpen: displayMode === "alwaysShow"
    forceClose: displayMode === "alwaysHide"
    tooltipText: {
      var monitor = getMonitor();
      if (!monitor)
        return "";
      return I18n.tr("tooltips.brightness-at", {
                       "brightness": Math.round(monitor.brightness * 100)
                     });
    }

    onWheel: function (angle) {
      var monitor = getMonitor();
      if (!monitor || !monitor.brightnessControlAvailable)
        return;

      if (angle > 0) {
        monitor.increaseBrightness();
      } else if (angle < 0) {
        monitor.decreaseBrightness();
      }
    }

    onClicked: PanelService.getPanel("brightnessPanel", screen)?.toggle(this)

    onRightClicked: {
      var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
      if (popupMenuWindow) {
        popupMenuWindow.showContextMenu(contextMenu);
        contextMenu.openAtItem(pill, screen);
      }
    }
  }
}
