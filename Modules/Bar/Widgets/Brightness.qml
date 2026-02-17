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
  readonly property string iconColorKey: widgetSettings.iconColor !== undefined ? widgetSettings.iconColor : widgetMetadata.iconColor
  readonly property string textColorKey: widgetSettings.textColor !== undefined ? widgetSettings.textColor : widgetMetadata.textColor
  readonly property bool applyScrollToAllMonitors: widgetSettings.applyScrollToAllMonitors !== undefined ? widgetSettings.applyScrollToAllMonitors : (Settings.data.brightness.syncAllMonitors !== undefined ? Settings.data.brightness.syncAllMonitors : widgetMetadata.applyScrollToAllMonitors)
  readonly property bool reverseScroll: Settings.data.general.reverseScroll

  // Used to avoid opening the pill on Quickshell startup
  property bool firstBrightnessReceived: false

  implicitWidth: pill.width
  implicitHeight: pill.height

  // Track the brightness monitor reactively; explicitly update on screen/monitors changes
  property var brightnessMonitor: null

  function updateMonitor() {
    brightnessMonitor = BrightnessService.getMonitorForScreen(screen) || null;
  }

  function getControllableMonitorCount() {
    var monitors = BrightnessService.monitors || [];
    var count = 0;
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i] && monitors[i].brightnessControlAvailable)
        count++;
    }
    return count;
  }

  onScreenChanged: updateMonitor()

  Connections {
    target: BrightnessService
    function onMonitorsChanged() {
      root.updateMonitor();
    }
    function onDdcMonitorsChanged() {
      root.updateMonitor();
    }
  }

  visible: brightnessMonitor !== null
  opacity: brightnessMonitor !== null ? 1.0 : 0.0

  function getIcon() {
    var monitor = brightnessMonitor;
    if (!monitor || !monitor.brightnessControlAvailable || isNaN(monitor.brightness))
      return "sun-off";
    var brightness = monitor.brightness;
    if (brightness <= 0.001)
      return "sun-off";
    return brightness <= 0.5 ? "brightness-low" : "brightness-high";
  }

  // Connection used to open the pill when brightness changes
  Connections {
    target: brightnessMonitor
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
        "label": I18n.tr("actions.open-display-settings"),
        "action": "open-display-settings",
        "icon": "sun"
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
    oppositeDirection: BarService.getPillDirection(root)
    customIconColor: Color.resolveColorKeyOptional(root.iconColorKey)
    customTextColor: Color.resolveColorKeyOptional(root.textColorKey)
    icon: getIcon()
    autoHide: false // Important to be false so we can hover as long as we want
    text: {
      var monitor = brightnessMonitor;
      if (!monitor || !monitor.brightnessControlAvailable || isNaN(monitor.brightness))
        return "";
      return Math.round(monitor.brightness * 100);
    }
    suffix: text.length > 0 ? "%" : "-"
    forceOpen: displayMode === "alwaysShow"
    forceClose: displayMode === "alwaysHide"
    tooltipText: {
      var monitor = brightnessMonitor;
      if (!monitor || !monitor.brightnessControlAvailable || isNaN(monitor.brightness))
        return "";
      return I18n.tr("tooltips.brightness-at", {
                       "brightness": Math.round(monitor.brightness * 100)
                     });
    }

    onWheel: function (angle) {
      var monitor = brightnessMonitor;
      if (!monitor || !monitor.brightnessControlAvailable)
        return;

      if (root.reverseScroll)
        angle *= -1;

      if (angle === 0)
        return;

      var shouldApplyToAll = root.applyScrollToAllMonitors && root.getControllableMonitorCount() > 1;
      if (shouldApplyToAll) {
        var direction = angle > 0 ? 1 : -1;
        var baseValue = !isNaN(monitor.queuedBrightness) ? monitor.queuedBrightness : monitor.brightness;
        var step = monitor.stepSize;
        var minValue = monitor.minBrightnessValue;

        if (direction > 0 && Settings.data.brightness.enforceMinimum && baseValue < minValue) {
          baseValue = Math.max(step, minValue);
        } else {
          baseValue = baseValue + direction * step;
        }

        var targetValue = Math.max(minValue, Math.min(1, baseValue));

        BrightnessService.monitors.forEach(function (m) {
          if (m && m.brightnessControlAvailable) {
            m.setBrightnessDebounced(targetValue);
          }
        });
      } else if (angle > 0) {
        monitor.increaseBrightness();
      } else if (angle < 0) {
        monitor.decreaseBrightness();
      }
    }

    onClicked: PanelService.getPanel("brightnessPanel", screen)?.toggle(this)

    onRightClicked: {
      PanelService.showContextMenu(contextMenu, pill, screen);
    }
  }
}
