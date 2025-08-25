import QtQuick
import Quickshell
import Quickshell.Services.UPower
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)

  implicitWidth: pill.width
  implicitHeight: pill.height

  NPill {
    id: pill

    // Test mode
    property bool testMode: false
    property int testPercent: 49
    property bool testCharging: false

    property var battery: UPower.displayDevice
    property bool isReady: testMode ? true : (battery && battery.ready && battery.isLaptopBattery && battery.isPresent)
    property real percent: testMode ? testPercent : (isReady ? (battery.percentage * 100) : 0)
    property bool charging: testMode ? testCharging : (isReady ? battery.state === UPowerDeviceState.Charging : false)

    // Choose icon based on charge and charging state
    function batteryIcon() {

      if (!isReady || !battery.isLaptopBattery)
        return "battery_android_alert"

      if (charging)
        return "battery_android_bolt"

      if (percent >= 95)
        return "battery_android_full"

      // Hardcoded battery symbols
      if (percent >= 85)
        return "battery_android_6"
      if (percent >= 70)
        return "battery_android_5"
      if (percent >= 55)
        return "battery_android_4"
      if (percent >= 40)
        return "battery_android_3"
      if (percent >= 25)
        return "battery_android_2"
      if (percent >= 10)
        return "battery_android_1"
      if (percent >= 0)
        return "battery_android_0"
    }

    icon: batteryIcon()
    text: (isReady && battery.isLaptopBattery) ? Math.round(percent) + "%" : "-"
    textColor: charging ? Color.mPrimary : Color.mOnSurface
    forceOpen: isReady && battery.isLaptopBattery && Settings.data.bar.alwaysShowBatteryPercentage
    disableOpen: (!isReady || !battery.isLaptopBattery)
    tooltipText: {
      let lines = []

      if (testMode) {
        lines.push("Time Left: " + Time.formatVagueHumanReadableDuration(12345))
        return lines.join("\n")
      }

      if (!isReady || !battery.isLaptopBattery) {
        return "No Battery Detected"
      }

      if (battery.timeToEmpty > 0) {
        lines.push("Time Left: " + Time.formatVagueHumanReadableDuration(battery.timeToEmpty))
      }

      if (battery.timeToFull > 0) {
        lines.push("Time Until Full: " + Time.formatVagueHumanReadableDuration(battery.timeToFull))
      }

      if (battery.changeRate !== undefined) {
        const rate = battery.changeRate
        if (rate > 0) {
          lines.push(charging ? "Charging Rate: " + rate.toFixed(2) + " W" : "Discharging Rate: " + rate.toFixed(
                                  2) + " W")
        } else if (rate < 0) {
          lines.push("Discharging Rate: " + Math.abs(rate).toFixed(2) + " W")
        } else {
          lines.push("Estimating...")
        }
      } else {
        lines.push(charging ? "Charging" : "Discharging")
      }

      if (battery.healthPercentage !== undefined && battery.healthPercentage > 0) {
        lines.push("Health: " + Math.round(battery.healthPercentage) + "%")
      }
      return lines.join("\n")
    }
  }
}
