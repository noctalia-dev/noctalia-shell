pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  property list<var> ddcMonitors: []
  readonly property list<Monitor> monitors: variants.instances
  property bool appleDisplayPresent: false

  function getMonitorForScreen(screen: ShellScreen): var {
    return monitors.find(m => m.modelData === screen);
  }

  // Signal emitted when a specific monitor's brightness changes, includes monitor context
  signal monitorBrightnessChanged(var monitor, real newBrightness)

  function getAvailableMethods(): list<string> {
    var methods = [];
    if (Settings.data.brightness.enableDdcSupport && monitors.some(m => m.isDdc))
      methods.push("ddcutil");
    if (monitors.some(m => !m.isDdc))
      methods.push("internal");
    if (appleDisplayPresent)
      methods.push("apple");
    return methods;
  }

  // Global helpers for IPC and shortcuts
  function increaseBrightness(): void {
    monitors.forEach(m => m.increaseBrightness());
  }

  function decreaseBrightness(): void {
    monitors.forEach(m => m.decreaseBrightness());
  }

  function getDetectedDisplays(): list<var> {
    return detectedDisplays;
  }

  reloadableId: "brightness"

  Component.onCompleted: {
    Logger.i("Brightness", "Service started");
    if (Settings.data.brightness.enableDdcSupport) {
      ddcProc.running = true;
    }
  }

  onMonitorsChanged: {
    ddcMonitors = [];
    if (Settings.data.brightness.enableDdcSupport) {
      ddcProc.running = true;
    }
  }

  Connections {
    target: Settings.data.brightness
    function onEnableDdcSupportChanged() {
      if (Settings.data.brightness.enableDdcSupport) {
        // Re-detect DDC monitors when enabled
        ddcMonitors = [];
        ddcProc.running = true;
      } else {
        // Clear DDC monitors when disabled
        ddcMonitors = [];
      }
    }
  }

  Variants {
    id: variants
    model: Quickshell.screens
    Monitor {}
  }

  // Check for Apple Display support
  Process {
    running: true
    command: ["sh", "-c", "which asdbctl >/dev/null 2>&1 && asdbctl get || echo ''"]
    stdout: StdioCollector {
      onStreamFinished: root.appleDisplayPresent = text.trim().length > 0
    }
  }

  // Detect DDC monitors
  Process {
    id: ddcProc
    property list<var> ddcMonitors: []
    command: ["ddcutil", "detect", "--sleep-multiplier=0.5"]
    stdout: StdioCollector {
      onStreamFinished: {
        var displays = text.trim().split("\n\n");
        ddcProc.ddcMonitors = displays.map(d => {
                                             var ddcModelMatch = d.match(/(This monitor does not support DDC\/CI|Invalid display)/);
                                             var modelMatch = d.match(/Model:\s*(.*)/);
                                             var busMatch = d.match(/I2C bus:[ ]*\/dev\/i2c-([0-9]+)/);
                                             var ddcModel = ddcModelMatch ? ddcModelMatch.length > 0 : false;
                                             var model = modelMatch ? modelMatch[1] : "Unknown";
                                             var bus = busMatch ? busMatch[1] : "Unknown";
                                             Logger.i("Brigthness", "Detected DDC Monitor:", model, "on bus", bus, "is DDC:", !ddcModel);
                                             return {
                                               "model": model,
                                               "busNum": bus,
                                               "isDdc": !ddcModel
                                             };
                                           });
        root.ddcMonitors = ddcProc.ddcMonitors.filter(m => m.isDdc);
      }
    }
  }

  component Monitor: QtObject {
    id: monitor

    required property ShellScreen modelData
    readonly property bool isDdc: Settings.data.brightness.enableDdcSupport && root.ddcMonitors.some(m => m.model === modelData.model)
    readonly property string busNum: root.ddcMonitors.find(m => m.model === modelData.model)?.busNum ?? ""
    readonly property bool isAppleDisplay: root.appleDisplayPresent && modelData.model.startsWith("StudioDisplay")
    readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : "internal")

    // Check if brightness control is available for this monitor
    readonly property bool brightnessControlAvailable: {
      if (isAppleDisplay)
      return true;
      if (isDdc)
      return true;
      // For internal displays, check if we have a brightness path
      return brightnessPath !== "";
    }

    property real brightness
    property real lastBrightness: 0
    property real queuedBrightness: NaN

    // For internal displays - store the backlight device paths (supports multiple devices)
    property list<var> backlightDevices: []
    property string backlightDevice: ""  // Primary device for compatibility
    property string brightnessPath: ""
    property string maxBrightnessPath: ""
    property int maxBrightness: 100
    property bool ignoreNextChange: false

    // Signal for brightness changes
    signal brightnessUpdated(real newBrightness)

    // Execute a system command to get the current brightness value directly
    readonly property Process refreshProc: Process {
      stdout: StdioCollector {
        onStreamFinished: {
          var dataText = text.trim();
          if (dataText === "") {
            return;
          }

          var lines = dataText.split("\n");
          if (lines.length >= 2) {
            var current = parseInt(lines[0].trim());
            var max = parseInt(lines[1].trim());
            if (!isNaN(current) && !isNaN(max) && max > 0) {
              var newBrightness = current / max;
              // Only update if it's actually different (avoid feedback loops)
              if (Math.abs(newBrightness - monitor.brightness) > 0.01) {
                // Update internal value to match system state
                monitor.brightness = newBrightness;
                monitor.brightnessUpdated(monitor.brightness);
                root.monitorBrightnessChanged(monitor, monitor.brightness);
                //Logger.i("Brightness", "Refreshed brightness from system:", monitor.modelData.name, monitor.brightness)
              }
            }
          }
        }
      }
    }

    // Function to actively refresh the brightness from system
    function refreshBrightnessFromSystem() {
      if (!monitor.isDdc && !monitor.isAppleDisplay) {
        // For internal displays, query the system directly
        refreshProc.command = ["sh", "-c", `cat ${monitor.brightnessPath} && cat ${monitor.maxBrightnessPath}`];
        refreshProc.running = true;
      } else if (monitor.isDdc) {
        // For DDC displays, get the current value
        refreshProc.command = ["ddcutil", "-b", monitor.busNum, "getvcp", "10", "--brief"];
        refreshProc.running = true;
      } else if (monitor.isAppleDisplay) {
        // For Apple displays, get the current value
        refreshProc.command = ["asdbctl", "get"];
        refreshProc.running = true;
      }
    }

    // FileView to watch for external brightness changes (internal displays only)
    readonly property FileView brightnessWatcher: FileView {
      id: brightnessWatcher
      // Only set path for internal displays with a valid brightness path
      path: (!monitor.isDdc && !monitor.isAppleDisplay && monitor.brightnessPath !== "") ? monitor.brightnessPath : ""
      watchChanges: path !== ""
      onFileChanged: {
        // When a file change is detected, actively refresh from system
        // to ensure we get the most up-to-date value
        Qt.callLater(() => {
                       monitor.refreshBrightnessFromSystem();
                     });
      }
    }

    // Initialize brightness
    readonly property Process initProc: Process {
      stdout: StdioCollector {
        onStreamFinished: {
          var dataText = text.trim();
          if (dataText === "") {
            return;
          }

          //Logger.i("Brightness", "Raw brightness data for", monitor.modelData.name + ":", dataText)
          if (monitor.isAppleDisplay) {
            var val = parseInt(dataText);
            if (!isNaN(val)) {
              monitor.brightness = val / 101;
              Logger.d("Brightness", "Apple display brightness:", monitor.brightness);
            }
          } else if (monitor.isDdc) {
            var parts = dataText.split(" ");
            if (parts.length >= 4) {
              var current = parseInt(parts[3]);
              var max = parseInt(parts[4]);
              if (!isNaN(current) && !isNaN(max) && max > 0) {
                monitor.brightness = current / max;
                Logger.d("Brightness", "DDC brightness:", current + "/" + max + " =", monitor.brightness);
              }
            }
          } else {
            // Internal backlight - parse all detected devices
            var lines = dataText.split("\n").filter(l => l.trim() !== "");
            var devices = [];
            
            // Parse device info in groups of 3 lines: device_path, current, max
            for (var i = 0; i + 2 < lines.length; i += 3) {
              var devicePath = lines[i].trim();
              var current = parseInt(lines[i + 1]);
              var max = parseInt(lines[i + 2]);
              
              if (!isNaN(current) && !isNaN(max) && max > 0) {
                devices.push({
                  path: devicePath,
                  current: current,
                  max: max
                });
                Logger.d("Brightness", "Detected backlight device:", devicePath, current + "/" + max);
              }
            }
            
            if (devices.length > 0) {
              monitor.backlightDevices = devices;
              // Use the first device as primary for compatibility and brightness reading
              monitor.backlightDevice = devices[0].path;
              monitor.brightnessPath = `${monitor.backlightDevice}/brightness`;
              monitor.maxBrightnessPath = `${monitor.backlightDevice}/max_brightness`;
              monitor.maxBrightness = devices[0].max;
              monitor.brightness = devices[0].current / devices[0].max;
              
              Logger.d("Brightness", "Internal brightness:", devices[0].current + "/" + devices[0].max + " =", monitor.brightness);
              Logger.d("Brightness", "Primary backlight device:", monitor.backlightDevice);
              if (devices.length > 1) {
                Logger.i("Brightness", "Found", devices.length, "backlight devices, will control all of them");
              }
            }
          }

          // Always update
          monitor.brightnessUpdated(monitor.brightness);
          root.monitorBrightnessChanged(monitor, monitor.brightness);
        }
      }
    }

    readonly property real stepSize: Settings.data.brightness.brightnessStep / 100.0
    readonly property real minBrightnessValue: (Settings.data.brightness.enforceMinimum ? 0.01 : 0.0)

    // Timer for debouncing rapid changes
    readonly property Timer timer: Timer {
      interval: 100
      onTriggered: {
        if (!isNaN(monitor.queuedBrightness)) {
          monitor.setBrightness(monitor.queuedBrightness);
          monitor.queuedBrightness = NaN;
        }
      }
    }

    function setBrightnessDebounced(value: real): void {
      monitor.queuedBrightness = value;
      timer.start();
    }

    function increaseBrightness(): void {
      const value = !isNaN(monitor.queuedBrightness) ? monitor.queuedBrightness : monitor.brightness;
      // Enforce minimum brightness if enabled
      if (Settings.data.brightness.enforceMinimum && value < minBrightnessValue) {
        setBrightnessDebounced(Math.max(stepSize, minBrightnessValue));
      } else {
        // Normal brightness increase
        setBrightnessDebounced(value + stepSize);
      }
    }

    function decreaseBrightness(): void {
      const value = !isNaN(monitor.queuedBrightness) ? monitor.queuedBrightness : monitor.brightness;
      setBrightnessDebounced(value - stepSize);
    }

    function setBrightness(value: real): void {
      value = Math.max(minBrightnessValue, Math.min(1, value));
      var rounded = Math.round(value * 100);

      if (timer.running) {
        monitor.queuedBrightness = value;
        return;
      }

      // Update internal value and trigger UI feedback
      monitor.brightness = value;
      monitor.brightnessUpdated(value);
      root.monitorBrightnessChanged(monitor, monitor.brightness);

      if (isAppleDisplay) {
        monitor.ignoreNextChange = true;
        Quickshell.execDetached(["asdbctl", "set", rounded]);
      } else if (isDdc) {
        monitor.ignoreNextChange = true;
        Quickshell.execDetached(["ddcutil", "-b", busNum, "setvcp", "10", rounded]);
      } else {
        monitor.ignoreNextChange = true;
        // Set brightness for all detected backlight devices
        if (monitor.backlightDevices.length > 0) {
          monitor.backlightDevices.forEach(device => {
            // Extract device name from path (e.g., /sys/class/backlight/intel_backlight -> intel_backlight)
            var deviceName = device.path.split("/").pop();
            if (deviceName && deviceName.length > 0) {
              Quickshell.execDetached(["brightnessctl", "-d", deviceName, "s", `${rounded}%`]);
            }
          });
        } else {
          // Fallback to brightnessctl without device specification if no devices detected
          Quickshell.execDetached(["brightnessctl", "s", `${rounded}%`]);
        }
      }

      if (isDdc) {
        timer.restart();
      }
    }

    function initBrightness(): void {
      if (isAppleDisplay) {
        initProc.command = ["asdbctl", "get"];
      } else if (isDdc) {
        initProc.command = ["ddcutil", "-b", busNum, "getvcp", "10", "--brief"];
      } else {
        // Internal backlight - find ALL available backlight devices and get their info
        // This returns for each device: device_path, current_brightness, max_brightness (on separate lines)
        initProc.command = ["sh", "-c", `for dev in /sys/class/backlight/*; do
          if [ -f "$dev/brightness" ] && [ -f "$dev/max_brightness" ]; then
            echo "$dev";
            cat "$dev/brightness";
            cat "$dev/max_brightness";
          fi;
        done`];
      }
      initProc.running = true;
    }

    onBusNumChanged: initBrightness()
    Component.onCompleted: initBrightness()
  }
}
