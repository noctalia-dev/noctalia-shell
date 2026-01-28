import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Hardware
import qs.Services.Networking
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
  readonly property string displayMode: widgetSettings.displayMode !== undefined ? widgetSettings.displayMode : widgetMetadata.displayMode
  readonly property real warningThreshold: widgetSettings.warningThreshold !== undefined ? widgetSettings.warningThreshold : widgetMetadata.warningThreshold
  readonly property bool hideIfNotDetected: widgetSettings.hideIfNotDetected !== undefined ? widgetSettings.hideIfNotDetected : widgetMetadata.hideIfNotDetected
  readonly property bool hideIfIdle: widgetSettings.hideIfIdle !== undefined ? widgetSettings.hideIfIdle : widgetMetadata.hideIfIdle
  // Only show low battery warning if device is ready (prevents false positive during initialization)
  readonly property bool isLowBattery: isReady && (!isCharging && !isPluggedIn) && percent <= warningThreshold

  // Visibility: show if hideIfNotDetected is false, or if battery is ready (after initialization)
  readonly property bool shouldShow: !hideIfNotDetected || (isReady && (hideIfIdle ? (!isCharging && !isPluggedIn) : true))

  // Test mode
  readonly property bool testMode: false
  readonly property int testPercent: 35
  readonly property bool testCharging: false
  readonly property bool testPluggedIn: false
  readonly property string deviceNativePath: widgetSettings.deviceNativePath || ""

  readonly property var device: BatteryService.resolveDevice(deviceNativePath)
  readonly property var battery: device && !BatteryService.isBluetoothDevice(device) ? device : null
  readonly property var bluetoothDevice: device && BatteryService.isBluetoothDevice(device) ? device : null
  readonly property bool hasBluetoothBattery: BatteryService.isBluetoothDevice(device)

  readonly property bool isReady: testMode ? true : (BatteryService.ready && BatteryService.isDeviceReady(device))
  readonly property real percent: testMode ? testPercent : (isReady ? BatteryService.getPercentage(device) : 0)
  readonly property bool isCharging: testMode ? testCharging : (isReady ? BatteryService.isCharging(device) : false)
  readonly property bool isPluggedIn: testMode ? testPluggedIn : (isReady ? BatteryService.isPluggedIn(device) : false)

  property bool hasNotifiedLowBattery: false

  visible: shouldShow
  opacity: shouldShow ? 1.0 : 0.0

  readonly property bool isDevicePresent: {
    if (testMode)
      return true;
    return BatteryService.isDevicePresent(device);
  }

  implicitWidth: pill.width
  implicitHeight: pill.height

  function maybeNotify(currentPercent, charging, pluggedIn, isReady) {
    if (isReady && (!charging && !pluggedIn) && !hasNotifiedLowBattery && currentPercent <= warningThreshold) {
      hasNotifiedLowBattery = true;
      ToastService.showWarning(I18n.tr("toast.battery.low"), I18n.tr("toast.battery.low-desc", {
                                                                       "percent": Math.round(currentPercent)
                                                                     }));
    } else if (hasNotifiedLowBattery && (charging || pluggedIn || currentPercent > warningThreshold + 5)) {
      hasNotifiedLowBattery = false;
    }
  }

  function getCurrentPercent() {
    return BatteryService.getPercentage(device);
  }

  Connections {
    target: battery
    function onPercentageChanged() {
      if (battery) {
        maybeNotify(getCurrentPercent(), isCharging, isPluggedIn, isReady);
      }
    }
    function onStateChanged() {
      if (battery) {
        if (isCharging || isPluggedIn) {
          hasNotifiedLowBattery = false;
        }
        maybeNotify(getCurrentPercent(), isCharging, isPluggedIn, isReady);
      }
    }
  }

  Connections {
    target: bluetoothDevice
    function onBatteryChanged() {
      if (BatteryService.isDeviceReady(bluetoothDevice)) {
        maybeNotify(BatteryService.getPercentage(bluetoothDevice), BatteryService.isCharging(bluetoothDevice), BatteryService.isPluggedIn(bluetoothDevice), true);
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  BarPill {
    id: pill

    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: testMode ? BatteryService.getIcon(testPercent, testCharging, testPluggedIn, true) : BatteryService.getIcon(percent, isCharging, isPluggedIn, isReady)
    text: (isReady || testMode) ? Math.round(percent) : "-"
    suffix: "%"
    autoHide: false
    forceOpen: isReady && displayMode === "alwaysShow"
    forceClose: displayMode === "alwaysHide" || (BatteryService.ready && !isReady)
    customBackgroundColor: !BatteryService.ready ? "transparent" : (isCharging ? Color.mPrimary : (isLowBattery ? Color.mError : "transparent"))
    customTextIconColor: !BatteryService.ready ? "transparent" : (isCharging ? Color.mOnPrimary : (isLowBattery ? Color.mOnError : "transparent"))

    tooltipText: {
      let lines = [];
      if (testMode) {
        lines.push(`Time left: ${Time.formatVagueHumanReadableDuration(12345)}.`);
        return lines.join("\n");
      }
      if (!isReady || !isDevicePresent) {
        return I18n.tr("battery.no-battery-detected");
      }
      if (battery) {
        if (!isPluggedIn && battery.timeToEmpty > 0) {
          lines.push(I18n.tr("battery.time-left", {
                               "time": Time.formatVagueHumanReadableDuration(battery.timeToEmpty)
                             }));
        }
        if (!isPluggedIn && battery.timeToFull > 0) {
          lines.push(I18n.tr("battery.time-until-full", {
                               "time": Time.formatVagueHumanReadableDuration(battery.timeToFull)
                             }));
        }
        if (battery.changeRate !== undefined) {
          const rate = Math.abs(battery.changeRate);
          if (isPluggedIn) {
            lines.push(I18n.tr("battery.plugged-in"));
          } else if (isCharging) {
            lines.push(I18n.tr("battery.charging-rate", {
                                 "rate": rate.toFixed(2)
                               }));
          } else {
            lines.push(I18n.tr("battery.discharging-rate", {
                                 "rate": rate.toFixed(2)
                               }));
          }
        }
      }
      return lines.join("\n");
    }
    onClicked: PanelService.getPanel("batteryPanel", screen)?.toggle(this)
    onRightClicked: {
      PanelService.showContextMenu(contextMenu, pill, screen);
    }
  }
}
