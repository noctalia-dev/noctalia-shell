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
  readonly property bool isLowBattery: isReady && (!isCharging && !isPluggedIn) && percent <= warningThreshold

  // Visibility: show if hideIfNotDetected is false, or if battery is ready
  readonly property bool shouldShow: !hideIfNotDetected || (isReady && (hideIfIdle ? (!isCharging && !isPluggedIn) : true))

  // Test mode
  readonly property bool testMode: false
  readonly property int testPercent: 35
  readonly property bool testCharging: false
  readonly property bool testPluggedIn: false

  readonly property string deviceNativePath: widgetSettings.deviceNativePath !== undefined ? widgetSettings.deviceNativePath : widgetMetadata.deviceNativePath
  readonly property var selectedBattery: BatteryService.findUPowerDevice(deviceNativePath)
  readonly property var selectedBluetoothDevice: BatteryService.findBluetoothDevice(deviceNativePath)
  readonly property var selectedDevice: {
    if (BatteryService.isDevicePresent(selectedBluetoothDevice)) {
      return selectedBluetoothDevice;
    }
    if (BatteryService.isDevicePresent(selectedBattery)) {
      return selectedBattery;
    }
    return null;
  }

  // Check if selected device is actually present/connected
  readonly property bool isPresent: testMode ? true : BatteryService.isDevicePresent(selectedDevice)
  readonly property bool isReady: testMode ? true : BatteryService.isDeviceReady(selectedDevice)

  readonly property real percent: testMode ? testPercent : (isReady ? Math.round(BatteryService.getPercentage(selectedDevice)) : -1)
  readonly property bool isCharging: testMode ? testCharging : (isReady ? BatteryService.isCharging(selectedDevice) : false)
  readonly property bool isPluggedIn: testMode ? testPluggedIn : (isReady ? BatteryService.isPluggedIn(selectedDevice) : false)

  property bool hasNotifiedLowBattery: false

  visible: shouldShow
  opacity: shouldShow ? 1.0 : 0.0

  implicitWidth: pill.width
  implicitHeight: pill.height

  function maybeNotify(currentPercent, charging, pluggedIn, isReady) {
    if (isReady && (!charging && !pluggedIn) && !hasNotifiedLowBattery && currentPercent <= warningThreshold) {
      hasNotifiedLowBattery = true;
      ToastService.showWarning(I18n.tr("toast.battery.low"), I18n.tr("toast.battery.low-desc", {
                                                                       "percent": Math.round(currentPercent)
                                                                     }), "battery-exclamation");
    } else if (hasNotifiedLowBattery && (charging || pluggedIn || currentPercent > warningThreshold + 5)) {
      hasNotifiedLowBattery = false;
    }
  }

  Connections {
    target: selectedDevice?.type === UPowerDeviceType.Battery ? selectedDevice : null

    function onPercentageChanged() {
      maybeNotify(BatteryService.getPercentage(selectedDevice), isCharging, isPluggedIn, isReady);
    }
    function onStateChanged() {
      if (isCharging || isPluggedIn) {
        hasNotifiedLowBattery = false;
      }
      maybeNotify(BatteryService.getPercentage(selectedDevice), isCharging, isPluggedIn, isReady);
    }
  }

  Connections {
    target: selectedDevice?.batteryAvailable ? selectedDevice : null

    function onBatteryChanged() {
      maybeNotify(BatteryService.getPercentage(selectedDevice), isCharging, isPluggedIn, isReady);
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
    forceClose: displayMode === "alwaysHide" || !isReady
    customBackgroundColor: isCharging ? Color.mPrimary : (isLowBattery ? Color.mError : "transparent")
    customTextIconColor: isCharging ? Color.mOnPrimary : (isLowBattery ? Color.mOnError : "transparent")

    tooltipText: {
      let lines = [];
      if (testMode) {
        lines.push("Time left: " + Time.formatVagueHumanReadableDuration(12345));
        return lines.join("\n");
      }
      if (!isReady || !isPresent) {
        return I18n.tr("battery.no-battery-detected");
      }
      const isInternal = selectedDevice.type === UPowerDeviceType.Battery && BatteryService.isLaptopBattery;

      if (isInternal) {
        let timeText = BatteryService.getTimeRemainingText(selectedDevice);
        if (timeText && timeText !== I18n.tr("common.idle") && timeText !== I18n.tr("battery.no-battery-detected") && timeText !== I18n.tr("battery.plugged-in")) {
          lines.push(timeText);
        }

        let rateText = BatteryService.getRateText(selectedDevice);
        if (rateText) {
          lines.push(rateText);
        }
      } else if (selectedDevice) {
        // External / Peripheral Device (Phone, Keyboard, Mouse, Gamepad, Headphone etc.)
        let name = BatteryService.getDeviceName(selectedDevice);
        let pct = Math.round(percent);
        lines.push(name + ": " + pct + suffix);
      }

      // If we are showing the main laptop battery, append external devices
      if (isInternal) {
        var external = BatteryService.externalBatteries;
        if (external.length > 0) {
          if (lines.length > 0)
            lines.push(""); // Separator
          for (var j = 0; j < external.length; j++) {
            var dev = external[j];
            var dName = BatteryService.getDeviceName(dev);
            var dPct = Math.round(BatteryService.getPercentage(dev));
            lines.push(dName + ": " + dPct + suffix);
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
