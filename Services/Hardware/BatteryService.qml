pragma Singleton
import QtQml
import QtQuick

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Services.Networking // For Bluetooth device presence check
import qs.Services.System // For UPower availability
import qs.Services.UI

Singleton {
  id: root

  readonly property bool upowerInstalled: ProgramCheckerService.upowerAvailable
  readonly property var primaryDevice: UPower.displayDevice.isPresent ? UPower.displayDevice : (laptopBatteries.length > 0 ? laptopBatteries[0] : (peripheralBatteries.length > 0 ? peripheralBatteries[0] : null)) // Primary battery device (prioritizes laptop over peripherals)
  readonly property real warningThreshold: Settings.data.systemMonitor.batteryWarningThreshold
  readonly property real criticalThreshold: Settings.data.systemMonitor.batteryCriticalThreshold
  readonly property var laptopBatteries: {
    if (!upowerInstalled) {
      return [];
    }
    let laptopBatteriesList = (UPower.devices?.values ?? []).filter(d => d && d.isLaptopBattery).sort((x, y) => x.nativePath.localeCompare(y.nativePath, undefined, {
                                                                                                                                             numeric: true
                                                                                                                                           }));
    if (laptopBatteriesList.length > 1 && UPower.displayDevice.isPresent) {
      return [UPower.displayDevice].concat(laptopBatteriesList);
    }
    return laptopBatteriesList;
  }
  readonly property var peripheralBatteries: upowerInstalled ? (UPower.devices?.values ?? []).filter(d => d && isPeripheral(d) && isDeviceReady(d)).sort((x, y) => (x.percentage || 0) - (y.percentage || 0)) : []

  property var deviceModel: {
    var model = [
      {
        "key": "__default__",
        "name": I18n.tr("bar.battery.device-default")
      }
    ];
    if (upowerInstalled) {
      const devices = UPower.devices?.values || [];
      for (let d of devices) {
        if (!d || d.type === UPowerDeviceType.LinePower) {
          continue;
        }
        model.push({
                     key: d.nativePath || "",
                     name: d.model || d.nativePath || I18n.tr("common.unknown")
                   });
      }
    }
    return model;
  }

  property var _hasNotified: ({})

  function findDevice(nativePath) {
    if (!nativePath || nativePath === "__default__" || nativePath === "DisplayDevice") {
      return primaryDevice;
    }

    if (!UPower.devices) {
      return null;
    }

    const devices = UPower.devices?.values || [];
    for (let d of devices) {
      if (d && d.nativePath === nativePath) {
        if (d.type === UPowerDeviceType.LinePower) {
          continue;
        }
        return d;
      }
    }
    return null;
  }

  function isDevicePresent(device) {
    if (!device) {
      return false;
    }

    if (!device.isLaptopBattery && device.type !== UPowerDeviceType.LinePower) {
      const path = (device.nativePath || "").toLowerCase();
      if (path.includes("bluez") && path.includes("dev_")) {
        const macMatch = path.match(/dev_([a-f0-9_]{17})/i);
        if (macMatch) {
          const mac = macMatch[1].replace(/_/g, ":").toUpperCase();
          const btDevice = (BluetoothService.devices?.values || []).find(d => (d.address || "").toUpperCase() === mac);
          if (btDevice && !btDevice.connected) {
            return false;
          }
        }
      }
    }

    if (device.type !== undefined) {
      if (device.isPresent !== undefined) {
        return device.isPresent === true;
      }
      return device.ready && device.percentage !== undefined;
    }

    return device.percentage !== undefined;
  }

  function isDeviceReady(device) {
    if (!isDevicePresent(device)) {
      return false;
    }
    return device.ready && device.percentage !== undefined;
  }

  function getPercentage(device) {
    if (!device || isNaN(device.percentage)) {
      return -1;
    }
    const z = device.percentage;
    return Math.round(z > 1.0 ? z : z * 100);
  }

  function isCharging(device) {
    if (!device) {
      return false;
    }
    if (device.state !== undefined) {
      return device.state === UPowerDeviceState.Charging;
    }
    return false;
  }

  function isPluggedIn(device) {
    if (!device) {
      return false;
    }
    if (device.state !== undefined) {
      return device.state === UPowerDeviceState.FullyCharged || device.state === UPowerDeviceState.PendingCharge;
    }
    return false;
  }

  function isCriticalBattery(device) {
    return (!isCharging(device) && !isPluggedIn(device)) && getPercentage(device) <= criticalThreshold;
  }

  function isLowBattery(device) {
    return (!isCharging(device) && !isPluggedIn(device)) && getPercentage(device) <= warningThreshold && getPercentage(device) > criticalThreshold;
  }

  function isPeripheral(device) {
    if (!device) {
      return false;
    }
    // Anything that isn't a main laptop battery or line power is a peripheral for our UI purposes
    return !device.isLaptopBattery && device.type !== UPowerDeviceType.LinePower;
  }

  function getDeviceName(device) {
    if (!device || !isDeviceReady(device)) {
      return "";
    }

    const isDD = device === UPower.displayDevice || (device.nativePath && device.nativePath.includes("DisplayDevice"));
    if (isDD) {
      return I18n.tr("battery.all-batteries");
    }

    if (device.isLaptopBattery) {
      // If there is more than one battery explicitly name them
      // Logger.e("BatteryDebug", "Available Battery count: " + laptopBatteries.length); // can be useful for debugging
      const i = laptopBatteries.indexOf(device);
      const hasDD = laptopBatteries.length > 0 && (laptopBatteries[0] === UPower.displayDevice || (laptopBatteries[0].nativePath && laptopBatteries[0].nativePath.includes("DisplayDevice")));
      if (i !== -1 && laptopBatteries.length > (hasDD ? 2 : 1)) {
        // If there's an aggregate device at 0, physical batteries start at index (dIx) 1 and we want them labeled starting at 'Battery 1'
        const dIx = hasDD ? i : i + 1;
        return I18n.tr("common.battery") + " " + dIx;
      }
      // Return Battery if there is only one
      return I18n.tr("common.battery");
    }
    return device.name || device.deviceName || device.model || "";
  }

  function getIcon(percent, charging, pluggedIn, isReady) {
    if (!isReady) {
      return percent < 0 ? "battery-off" : "battery-exclamation";
    }
    if (charging) {
      return "battery-charging";
    }
    if (pluggedIn) {
      return "battery-charging-2";
    }

    const icons = [
            {
              threshold: 86,
              icon: "battery-4"
            },
            {
              threshold: 56,
              icon: "battery-3"
            },
            {
              threshold: 31,
              icon: "battery-2"
            },
            {
              threshold: 11,
              icon: "battery-1"
            },
            {
              threshold: 0,
              icon: "battery"
            }
          ];

    const match = icons.find(tier => percent >= tier.threshold);
    return match ? match.icon : "battery-off"; // New fallback icon clearly represent if nothing is true here.
  }

  function getRateText(device) {
    if (!device || device.changeRate === undefined) {
      return "";
    }
    const rate = Math.abs(device.changeRate);
    if (device.timeToFull > 0) {
      return I18n.tr("battery.charging-rate", {
                       "rate": rate.toFixed(2)
                     });
    } else if (device.timeToEmpty > 0) {
      return I18n.tr("battery.discharging-rate", {
                       "rate": rate.toFixed(2)
                     });
    }
  }

  function getTimeRemainingText(device) {
    if (!isDeviceReady(device)) {
      return I18n.tr("battery.no-battery-detected");
    }
    if (isPluggedIn(device)) {
      return I18n.tr("battery.plugged-in");
    } else if (device.timeToFull > 0) {
      return I18n.tr("battery.time-until-full", {
                       "time": Time.formatVagueHumanReadableDuration(device.timeToFull)
                     });
    } else if (device.timeToEmpty > 0) {
      return I18n.tr("battery.time-left", {
                       "time": Time.formatVagueHumanReadableDuration(device.timeToEmpty)
                     });
    }
    return I18n.tr("common.idle");
  }

  function checkDevice(device) {
    if (!device || !isDeviceReady(device)) {
      return;
    }

    const percentage = getPercentage(device);
    const charging = isCharging(device);
    const pluggedIn = isPluggedIn(device);
    const level = isLowBattery(device) ? "low" : (isCriticalBattery(device) ? "critical" : "");
    var deviceKey = device.nativePath || "";

    if (!_hasNotified[deviceKey]) {
      _hasNotified[deviceKey] = {
        low: false,
        critical: false
      };
    }

    if (charging || pluggedIn) {
      _hasNotified[deviceKey].low = false;
      _hasNotified[deviceKey].critical = false;
    }

    if (percentage > warningThreshold) {
      _hasNotified[deviceKey].low = false;
      _hasNotified[deviceKey].critical = false;
    } else if (percentage > criticalThreshold) {
      _hasNotified[deviceKey].critical = false;
    }

    if (level) {
      if (!_hasNotified[deviceKey][level]) {
        notify(device, level);
        _hasNotified[deviceKey][level] = true;
      }
    }
  }

  function notify(device, level) {
    if (!Settings.data.notifications.enableBatteryToast) {
      return;
    }
    var name = getDeviceName(device);
    var titleKey = level === "critical" ? "toast.battery.critical" : "toast.battery.low";
    var descKey = level === "critical" ? "toast.battery.critical-desc" : "toast.battery.low-desc";

    var title = I18n.tr(titleKey); // - "Low Battery" & "Critical Battery"
    var desc = I18n.tr(descKey, {
                         "percent": getPercentage(device)
                       });
    var icon = level === "critical" ? "battery-exclamation" : "battery-charging-2";

    if (isPeripheral(device) && name) {
      title = name + " - " + title;
      // ex A: 'Turann_s AirPods Pro III - Low Battery' - I prefer this makes most sense.
      // ex B: 'Low Battery - Turann_s AirPods Pro III'
    }

    // Only 'showNotice' supports custom icons
    ToastService.showNotice(title, desc, icon, 6000);
  }

  function getDeviceIcon(device) {
    if (!device) {
      return "bt-device-undefined";
    }

    const name = (device.model || device.name || "").toLowerCase();
    const nativePath = (device.nativePath || "").toLowerCase();
    const iconHint = (device.icon || device.iconName || "").toLowerCase();  // Some devices are not known to UPower (eg: Bluetooth devices, hint is often does the heavy lifting for recognition)
    const isEarbud = name.includes("pod") || name.includes("bud") || iconHint.includes("earbud");
    // 3: UPS
    if (device.type === UPowerDeviceType.Ups || nativePath.includes("ups")) {
      return "device-ups";
    }
    // 4: Monitor
    if (device.type === UPowerDeviceType.Monitor || nativePath.includes("monitor") || iconHint.includes("display")) {
      return "device-monitor";
    }
    // 5: Mouse
    if (device.type === UPowerDeviceType.Mouse || nativePath.includes("mouse") || iconHint.includes("mouse")) {
      return "device-mouse";
    }
    // 6: Keyboard
    if (device.type === UPowerDeviceType.Keyboard || nativePath.includes("keyboard") || iconHint.includes("keyboard")) {
      return "device-keyboard";
    }
    // 8: Phone
    if (device.type === UPowerDeviceType.Phone || nativePath.includes("phone") || iconHint.includes("phone")) {
      return "device-phone";
    }
    // 9: Media Player
    if (device.type === UPowerDeviceType.MediaPlayer || nativePath.includes("media_player")) {
      return "device-media-player";
    }
    // 10: Tablet
    if (device.type === UPowerDeviceType.Tablet || nativePath.includes("tablet") || iconHint.includes("tablet")) {
      return "device-tablet";
    }
    // 11: Computer
    if (device.type === UPowerDeviceType.Computer || nativePath.includes("computer")) {
      return "device-desktop";
    }
    // 12: Gaming Input
    if (device.type === UPowerDeviceType.GamingInput || nativePath.includes("gaming_input") || nativePath.includes("controller") || nativePath.includes("joypad") || iconHint.includes("gamepad") || iconHint.includes("controller") || iconHint.includes("dualshock") || iconHint.includes("dualsense") || iconHint.includes("ps5") || iconHint.includes("xbox")) {
      return "device-gamepad";
    }
    // 13: Pen
    if (device.type === UPowerDeviceType.Pen || nativePath.includes("pen")) {
      return "device-pen";
    }
    // 14: Touchpad
    if (device.type === UPowerDeviceType.Touchpad || nativePath.includes("touchpad")) {
      return "device-touchpad";
    }
    // 15: Modem
    if (device.type === UPowerDeviceType.Modem || nativePath.includes("modem")) {
      return "device-modem";
    }
    // 17: Headset
    if (device.type === UPowerDeviceType.Headset || nativePath.includes("headset") || iconHint.includes("headset")) {
      return isEarbud ? "device-earbuds" : "device-headset";
    }
    // 18: Speakers
    if (device.type === UPowerDeviceType.Speakers || nativePath.includes("speaker") || iconHint.includes("speaker")) {
      return "device-speaker";
    }
    // 19: Headphones
    if (device.type === UPowerDeviceType.Headphones || nativePath.includes("headphones") || iconHint.includes("headphones")) {
      return isEarbud ? "device-earbuds" : "device-headphones";
    }
    // 20: Video
    if (device.type === UPowerDeviceType.Video || device.type === UPowerDeviceType.OtherVideo || nativePath.includes("video")) {
      return "device-monitor";
    }
    // 21: Other Audio
    if (device.type === UPowerDeviceType.OtherAudio || nativePath.includes("audio") || nativePath.includes("sound")) {
      return "device-audio";
    }
    // 22: Remote Control
    if (device.type === UPowerDeviceType.RemoteControl || nativePath.includes("remote")) {
      return "device-remote";
    }
    // 23: Printer
    if (device.type === UPowerDeviceType.Printer || nativePath.includes("printer")) {
      return "device-printer";
    }
    // 24: Scanner
    if (device.type === UPowerDeviceType.Scanner || nativePath.includes("scanner")) {
      return "device-scanner";
    }
    // 25: Camera
    if (device.type === UPowerDeviceType.Camera || nativePath.includes("camera")) {
      return "device-camera";
    }
    // 26: Wearable
    if (device.type === UPowerDeviceType.Wearable || nativePath.includes("watch") || iconHint.includes("watch")) {
      return "device-watch";
    }

    // 2. Context-aware fallback:
    // If it's a battery-reporting device (UPower), show its battery level as the icon.
    // Otherwise (Bluetooth), return the generic bluetooth device icon.
    if (device.percentage !== undefined) {
      return getIcon(getPercentage(device), isCharging(device), isPluggedIn(device), isDeviceReady(device));
    }

    return "bt-device-undefined"; // 28
  }

  Instantiator {
    model: deviceModel
    delegate: Connections {
      required property var modelData
      property var device: findDevice(modelData.key)
      target: device

      function onPercentageChanged() {
        if (device.isLaptopBattery && modelData.key !== "__default__") {
          return;
        }
        checkDevice(device);
      }
      function onStateChanged() {
        if (device.isLaptopBattery && modelData.key !== "__default__") {
          return;
        }
        checkDevice(device);
      }
    }
  }
}
