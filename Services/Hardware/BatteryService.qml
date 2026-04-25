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
  readonly property var primaryDevice: UPower.displayDevice.isPresent ? UPower.displayDevice : (laptopBatteries.length > 0 ? laptopBatteries[0] : (peripheralBatteries.length > 0 ? peripheralBatteries[0] : null)) // Primary battery device (prioritizes laptop battery over peripherals)
  readonly property real warningThreshold: Settings.data.systemMonitor.batteryWarningThreshold
  readonly property real criticalThreshold: Settings.data.systemMonitor.batteryCriticalThreshold
  readonly property var laptopBatteries: {
    if (!upowerInstalled) {
      return [];
    }
    let physicalBatteries = (UPower.devices?.values ?? []).filter(d => d && d.isLaptopBattery && !isDisplayDevice(d));
    physicalBatteries.sort((x, y) => x.nativePath.localeCompare(y.nativePath, undefined, {
                                                                  numeric: true
                                                                }));

    if (UPower.displayDevice.isPresent && physicalBatteries.length > 0) {
      // displayDevice only makes sense there is > 1 battery.
      // Prefer primary physical battery because DisplayDevice doesn't have infornation we use (BatteryHealth) - and possibly stuff (e.g: Vendor/Model)
      return (physicalBatteries.length > 1) ? [UPower.displayDevice].concat(physicalBatteries) : physicalBatteries;
    }
    return physicalBatteries;
  }
  // Peripherals are sorted by battery percentage asending to prioritize showing low batteries first in the UI when there are multiple.
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
    // Get selected device based on nativePath, with a fallback to primaryDevice for the default entry.
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
    // For Bluetooth devices, check if they're connected before considering them "present" in the UI. They can report battery levels even when disconnected, which is confusing. UPower remembers devices even after they disconnect.
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
    // Checks that we don't show devices that are still connecting or haven't fully initialized yet.
    if (!isDevicePresent(device)) {
      return false;
    }
    return device.ready && device.percentage !== undefined;
  }

  function getPercentage(device) {
    // Ensure we always return a number regardless of what the device reports. The UI expects a number.
    if (!device || isNaN(device.percentage)) {
      return -1;
    }
    const z = device.percentage;
    // Some devices (especially Bluetooth) can report a 0-1 value instead of 0-100, so we handle both and ensure we always return a 0-100 value for the UI.
    return Math.round(z > 1.0 ? z : z * 100);
  }

  function isCharging(device) {
    // Detect if the selected device is charging.
    if (!device) {
      return false;
    }
    if (device.state !== undefined) {
      return device.state === UPowerDeviceState.Charging;
    }
    return false;
  }

  function isPluggedIn(device) {
    // Detect if the selected device is plugged in (but not charging).
    if (!device) {
      return false;
    }
    if (device.state !== undefined) {
      return device.state === UPowerDeviceState.FullyCharged || device.state === UPowerDeviceState.PendingCharge;
    }
    return false;
  }

  function isCriticalBattery(device) {
    // When selected device is below the threshold and not charging or plugged in, return true - Crank up alarm level.
    return (!isCharging(device) && !isPluggedIn(device)) && getPercentage(device) <= criticalThreshold;
  }

  function isLowBattery(device) {
    // When selected device is below the threshold and not charging or plugged in, return true - Give user a warning.
    return (!isCharging(device) && !isPluggedIn(device)) && getPercentage(device) <= warningThreshold && getPercentage(device) > criticalThreshold;
  }

  function isDisplayDevice(device) {
    // Well for one thing we want to identify the display device as a special case. But what is a display device? It's a virtual device that represents the aggregate of all laptop batteries. - TLDR: it does math stuff laptops with multiple batteries (eg: Some Thinkpad models)
    return device === UPower.displayDevice || (device.nativePath && device.nativePath.includes("DisplayDevice"));
  }

  function isPeripheral(device) {
    // Determine if a device is a peripheral with battery (e.g., Bluetooth headphones, wireless mouse, etc.)
    if (!device) {
      return false;
    }
    // Anything that isn't a main laptop battery or line power is a peripheral for our UI purposes
    return !device.isLaptopBattery && device.type !== UPowerDeviceType.LinePower;
  }

  function getDeviceName(device) {
    // Return name for device, with various fallbacks.
    if (!device || !isDeviceReady(device)) {
      return "";
    }

    if (isDisplayDevice(device)) {
      // Return correct name for display device. - DisplayDevice only shown when matters (when there more batteries than 1)
      return I18n.tr("battery.all-batteries");
    }

    if (device.isLaptopBattery) {
      // If there is more than one battery explicitly name them
      // Logger.e("BatteryDebug", "Available Battery count: " + laptopBatteries.length); // can be useful for debugging
      const i = laptopBatteries.indexOf(device);
      const hasDD = laptopBatteries.length > 0 && isDisplayDevice(laptopBatteries[0]);
      if (i !== -1 && laptopBatteries.length > (hasDD ? 2 : 1)) {
        // If there's an aggregate device at 0, physical batteries start at index (dIx) 1 and we want them labeled starting at 'Battery 1'
        const dIx = hasDD ? i : i + 1;
        return I18n.tr("common.battery") + " " + dIx;
      } else {
        // If there is only one battery do not append numbers.
        return I18n.tr("common.battery");
      }
    }
    // For peripherals, not every device is equal so we press all the buttons hoping one works.
    return device.name || device.deviceName || device.model || I18n.tr("common.battery");
    // device.name comes from BlueZ ~ mostly here for aliases.
    // device.deviceName comes from Quickshell
    // device.model comes from UPower.
  }

  function getIcon(percent, charging, pluggedIn, isReady) {
    // Return battery icon with given attributes.
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
    return match ? match.icon : "battery-off"; // New fallback icon to clearly represent when nothing else matches.
  }

  function getRateText(device) {
    // Return charging/discharging rate text based on device status.
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
    // Return approximate time remaining based on conditions, primarily what UPower says.
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

  function thresholdLatch(device) {
    // Decides when to send a low/critical battery notification.
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
    // The function that sends the notification.
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
      // Naming for external devices.
      title = title + ": " + name;
    }

    // Only 'showNotice' supports custom icons
    ToastService.showNotice(title, desc, icon, 6000);
  }

  function getDeviceIcon(device) {
    // This looks a bit complicated, but it's actually not. Returns specific icon based on what we know about the device.
    if (!device) {
      return "bt-device-undefined";
    }

    const name = (device.model || device.name || "").toLowerCase();
    const nativePath = (device.nativePath || "").toLowerCase(); // nativePath where UPower sees the device
    const iconHint = (device.icon || device.iconName || "").toLowerCase();  // Some devices are not known to UPower (e.g., Bluetooth devices). The icon hint often does the heavy lifting for recognition here.
    // A: DisplayDevice - If you read you know, if not go back and read.
    if (isDisplayDevice(device)) {
      return "device-laptop";
    }
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
    // 9: Media Player - don't ask me i don't know what this was.
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
      return (name.includes("pod") || name.includes("bud")) ? "device-earbuds" : "device-headset";
    }
    // 18: Speakers
    if (device.type === UPowerDeviceType.Speakers || nativePath.includes("speaker") || iconHint.includes("speaker")) {
      return "device-speaker";
    }
    // 19: Headphones
    if (device.type === UPowerDeviceType.Headphones || nativePath.includes("headphones") || iconHint.includes("headphones")) {
      return (name.includes("pod") || name.includes("bud")) ? "device-earbuds" : "device-headphones";
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

    // 2. Context-aware fallback: A (simple) trick BatteryPanel when opened, knows percentages - BluetoothPanel doesn't.
    // But wait there is more, BluetoothPanel knows icon hints, BatteryPanel doesn't.
    if (device.percentage !== undefined) {
      return getIcon(getPercentage(device), isCharging(device), isPluggedIn(device), isDeviceReady(device));
    }
    // 28: Fallback
    return "bt-device-undefined";
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
        thresholdLatch(device);
      }
      function onStateChanged() {
        if (device.isLaptopBattery && modelData.key !== "__default__") {
          return;
        }
        thresholdLatch(device);
      }
    }
  }
}
