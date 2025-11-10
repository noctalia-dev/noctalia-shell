import QtQuick
import Quickshell
import Quickshell.Services.UPower
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Services.Hardware
import qs.Widgets
import qs.Modules.Bar.Extras

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
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property bool isBarVertical: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
  readonly property string displayMode: widgetSettings.displayMode !== undefined ? widgetSettings.displayMode : widgetMetadata.displayMode
  readonly property real warningThreshold: widgetSettings.warningThreshold !== undefined ? widgetSettings.warningThreshold : widgetMetadata.warningThreshold

  // Test mode
  readonly property bool testMode: false
  readonly property int testPercent: 100
  readonly property bool testCharging: false

  // Main properties
  readonly property var battery: UPower.displayDevice
  readonly property bool isReady: testMode ? true : (battery && battery.ready && battery.isLaptopBattery && battery.isPresent)
  readonly property real percent: testMode ? testPercent : (isReady ? (battery.percentage * 100) : 0)
  readonly property bool charging: testMode ? testCharging : (isReady ? battery.state === UPowerDeviceState.Charging : false)
  property bool hasNotifiedLowBattery: false

  implicitWidth: pill.width
  implicitHeight: pill.height

  // Helper to evaluate and possibly notify
  function maybeNotify(percent, charging) {
    // Only notify once we are a below threshold
    if (!charging && !root.hasNotifiedLowBattery && percent <= warningThreshold) {
      root.hasNotifiedLowBattery = true
      ToastService.showWarning(I18n.tr("toast.battery.low"), I18n.tr("toast.battery.low-desc", {
                                                                       "percent": Math.round(percent)
                                                                     }))
    } else if (root.hasNotifiedLowBattery && (charging || percent > warningThreshold + 5)) {
      // Reset when charging starts or when battery recovers 5% above threshold
      root.hasNotifiedLowBattery = false
    }
  }

  // Watch for battery changes
  Connections {
    target: UPower.displayDevice
    function onPercentageChanged() {
      var currentPercent = UPower.displayDevice.percentage * 100
      var isCharging = UPower.displayDevice.state === UPowerDeviceState.Charging
      root.maybeNotify(currentPercent, isCharging)
    }

    function onStateChanged() {
      var isCharging = UPower.displayDevice.state === UPowerDeviceState.Charging
      // Reset notification flag when charging starts
      if (isCharging) {
        root.hasNotifiedLowBattery = false
      }
      // Also re-evaluate maybeNotify, as state might have changed
      var currentPercent = UPower.displayDevice.percentage * 100
      root.maybeNotify(currentPercent, isCharging)
    }
  }

  BarPill {
    id: pill

    density: Settings.data.bar.density
    oppositeDirection: BarService.getPillDirection(root)
    icon: testMode ? BatteryService.getIcon(testPercent, testCharging, true) : BatteryService.getIcon(percent, charging, isReady)
    text: (isReady || testMode) ? Math.round(percent) : "-"
    suffix: "%"
    autoHide: false
    forceOpen: isReady && (testMode || battery.isLaptopBattery) && displayMode === "alwaysShow"
    forceClose: displayMode === "alwaysHide" || !isReady || (!testMode && !battery.isLaptopBattery)
    onClicked: PanelService.getPanel("batteryPanel", screen)?.toggle(this)
    tooltipText: {
      let lines = []
      if (testMode) {
        lines.push(`Time left: ${Time.formatVagueHumanReadableDuration(12345)}.`)
        return lines.join("\n")
      }
      if (!isReady || !battery.isLaptopBattery) {
        return I18n.tr("battery.no-battery-detected")
      }
      if (battery.timeToEmpty > 0) {
        lines.push(I18n.tr("battery.time-left", {
                             "time": Time.formatVagueHumanReadableDuration(battery.timeToEmpty)
                           }))
      }
      if (battery.timeToFull > 0) {
        lines.push(I18n.tr("battery.time-until-full", {
                             "time": Time.formatVagueHumanReadableDuration(battery.timeToFull)
                           }))
      }
      if (battery.changeRate !== undefined) {
        const rate = battery.changeRate
        if (rate > 0) {
          lines.push(charging ? I18n.tr("battery.charging-rate", {
                                          "rate": rate.toFixed(2)
                                        }) : I18n.tr("battery.discharging-rate", {
                                                       "rate": rate.toFixed(2)
                                                     }))
        } else if (rate < 0) {
          lines.push(I18n.tr("battery.discharging-rate", {
                               "rate": Math.abs(rate).toFixed(2)
                             }))
        } else {
          // Rate is 0 - check if plugged in (charging state) or idle
          lines.push(charging ? I18n.tr("battery.plugged-in") : I18n.tr("battery.idle"))
        }
      } else {
        lines.push(charging ? I18n.tr("battery.charging") : I18n.tr("battery.discharging"))
      }
      if (battery.healthPercentage !== undefined && battery.healthPercentage > 0) {
        lines.push(I18n.tr("battery.health", {
                             "percent": Math.round(battery.healthPercentage)
                           }))
      }
      return lines.join("\n")
    }
  }
}
