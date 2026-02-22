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
  property list<var> availableBacklightDevices: []

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

  function setBrightness(value: real): void {
    monitors.forEach(m => m.setBrightnessDebounced(value));
  }

  function getDetectedDisplays(): list<var> {
    return detectedDisplays;
  }

  function normalizeBacklightDevicePath(devicePath): string {
    if (devicePath === undefined || devicePath === null)
      return "";

    var normalized = String(devicePath).trim();
    if (normalized === "")
      return "";

    if (normalized.startsWith("/sys/class/backlight/"))
      return normalized;

    if (normalized.indexOf("/") === -1)
      return "/sys/class/backlight/" + normalized;

    return normalized;
  }

  function getBacklightDeviceName(devicePath): string {
    var normalized = normalizeBacklightDevicePath(devicePath);
    if (normalized === "")
      return "";

    var parts = normalized.split("/");
    while (parts.length > 0 && parts[parts.length - 1] === "") {
      parts.pop();
    }
    return parts.length > 0 ? parts[parts.length - 1] : "";
  }

  function getMappedBacklightDevice(outputName): string {
    var normalizedOutput = String(outputName || "").trim();
    if (normalizedOutput === "")
      return "";

    var mappings = Settings.data.brightness.backlightDeviceMappings || [];
    for (var i = 0; i < mappings.length; i++) {
      var mapping = mappings[i];
      if (!mapping || typeof mapping !== "object")
        continue;

      if (String(mapping.output || "").trim() === normalizedOutput)
        return normalizeBacklightDevicePath(mapping.device || "");
    }

    return "";
  }

  function setMappedBacklightDevice(outputName, devicePath): void {
    var normalizedOutput = String(outputName || "").trim();
    if (normalizedOutput === "")
      return;

    var normalizedDevicePath = normalizeBacklightDevicePath(devicePath);
    var mappings = Settings.data.brightness.backlightDeviceMappings || [];
    var nextMappings = [];
    var replaced = false;

    for (var i = 0; i < mappings.length; i++) {
      var mapping = mappings[i];
      if (!mapping || typeof mapping !== "object")
        continue;

      var mappingOutput = String(mapping.output || "").trim();
      var mappingDevice = normalizeBacklightDevicePath(mapping.device || "");
      if (mappingOutput === "" || mappingDevice === "")
        continue;

      if (mappingOutput === normalizedOutput) {
        if (!replaced && normalizedDevicePath !== "") {
          nextMappings.push({
            "output": normalizedOutput,
            "device": normalizedDevicePath
          });
        }
        replaced = true;
      } else {
        nextMappings.push({
          "output": mappingOutput,
          "device": mappingDevice
        });
      }
    }

    if (!replaced && normalizedDevicePath !== "") {
      nextMappings.push({
        "output": normalizedOutput,
        "device": normalizedDevicePath
      });
    }

    Settings.data.brightness.backlightDeviceMappings = nextMappings;
  }

  function scanBacklightDevices(): void {
    if (!scanBacklightProc.running)
      scanBacklightProc.running = true;
  }

  reloadableId: "brightness"

  Component.onCompleted: {
    Logger.i("Brightness", "Service started");
    scanBacklightDevices();
    if (Settings.data.brightness.enableDdcSupport) {
      ddcProc.running = true;
    }
  }

  onMonitorsChanged: {
    ddcMonitors = [];
    scanBacklightDevices();
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
    function onBacklightDeviceMappingsChanged() {
      scanBacklightDevices();
      for (var i = 0; i < monitors.length; i++) {
        var m = monitors[i];
        if (m && !m.isDdc && !m.isAppleDisplay)
          m.initBrightness();
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

  // Detect available internal backlight devices
  Process {
    id: scanBacklightProc
    command: ["sh", "-c", "for dev in /sys/class/backlight/*; do if [ -f \"$dev/brightness\" ] && [ -f \"$dev/max_brightness\" ]; then echo \"$dev\"; fi; done"]
    stdout: StdioCollector {
      onStreamFinished: {
        var data = text.trim();
        if (data === "") {
          root.availableBacklightDevices = [];
          return;
        }

        var lines = data.split("\n");
        var found = [];
        var seen = ({});
        for (var i = 0; i < lines.length; i++) {
          var path = root.normalizeBacklightDevicePath(lines[i]);
          if (path === "" || seen[path])
            continue;
          seen[path] = true;
          found.push(path);
        }

        root.availableBacklightDevices = found;
      }
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
                                             var connectorMatch = d.match(/DRM[_ ]connector:\s*card\d+-(.+)/);
                                             var ddcModel = ddcModelMatch ? ddcModelMatch.length > 0 : false;
                                             var model = modelMatch ? modelMatch[1] : "Unknown";
                                             var bus = busMatch ? busMatch[1] : "Unknown";
                                             var connector = connectorMatch ? connectorMatch[1].trim() : "";
                                             Logger.i("Brightness", "Detected DDC Monitor:", model, "connector:", connector, "bus:", bus, "is DDC:", !ddcModel);
                                             return {
                                               "model": model,
                                               "busNum": bus,
                                               "connector": connector,
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
    readonly property bool isDdc: Settings.data.brightness.enableDdcSupport && root.ddcMonitors.some(m => m.connector === modelData.name)
    readonly property string busNum: root.ddcMonitors.find(m => m.connector === modelData.name)?.busNum ?? ""
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
    property bool commandRunning: false

    // For internal displays - store the backlight device path
    property string backlightDevice: ""
    property string brightnessPath: ""
    property string maxBrightnessPath: ""
    property int maxBrightness: 100
    property bool ignoreNextChange: false
    property bool initInProgress: false

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

          var newBrightness = NaN;

          if (monitor.isAppleDisplay) {
            // Apple display format: single integer (0-101)
            var val = parseInt(dataText);
            if (!isNaN(val)) {
              newBrightness = val / 101;
            }
          } else if (monitor.isDdc) {
            // DDC format: "VCP 10 C 100 100" (space-separated)
            var parts = dataText.split(" ");
            if (parts.length >= 4) {
              var current = parseInt(parts[3]);
              var max = parseInt(parts[4]);
              if (!isNaN(current) && !isNaN(max) && max > 0) {
                monitor.maxBrightness = max;
                newBrightness = current / max;
              }
            }
          } else {
            // Internal display format: two lines (current\nmax)
            var lines = dataText.split("\n");
            if (lines.length >= 2) {
              var current = parseInt(lines[0].trim());
              var max = parseInt(lines[1].trim());
              if (!isNaN(current) && !isNaN(max) && max > 0) {
                newBrightness = current / max;
              }
            }
          }

          // Update if we got a valid brightness value
          if (!isNaN(newBrightness) && (Math.abs(newBrightness - monitor.brightness) > 0.001 || monitor.brightness === 0)) {
            monitor.brightness = newBrightness;
            monitor.brightnessUpdated(monitor.brightness);
            root.monitorBrightnessChanged(monitor, monitor.brightness);
            Logger.d("Brightness", "Refreshed brightness from system:", monitor.modelData.name, monitor.brightness);
          }
        }
      }
    }

    readonly property Process setBrightnessProc: Process {
      stdout: StdioCollector {}
      onExited: (exitCode, exitStatus) => {
        monitor.commandRunning = false;
        // If there's a queued brightness change, process it now
        if (!isNaN(monitor.queuedBrightness)) {
          Qt.callLater(() => {
                         monitor.setBrightness(monitor.queuedBrightness);
                         monitor.queuedBrightness = NaN;
                       });
        }
      }
    }

    // Function to actively refresh the brightness from system
    function refreshBrightnessFromSystem() {
      if (!monitor.isDdc && !monitor.isAppleDisplay) {
        // For internal displays, query the system directly
        refreshProc.command = ["sh", "-c", "cat " + monitor.brightnessPath + " && " + "cat " + monitor.maxBrightnessPath];
        refreshProc.running = true;
      } else if (monitor.isDdc && monitor.busNum !== "") {
        // For DDC displays, get the current value
        refreshProc.command = ["ddcutil", "-b", monitor.busNum, "--sleep-multiplier=0.05", "getvcp", "10", "--brief"];
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
                monitor.maxBrightness = max;
                monitor.brightness = current / max;
                Logger.d("Brightness", "DDC brightness:", current + "/" + max + " =", monitor.brightness);
              }
            }
          } else {
            // Internal backlight - parse the response which includes device path
            var lines = dataText.split("\n");
            if (lines.length >= 3) {
              monitor.backlightDevice = lines[0];
              monitor.brightnessPath = monitor.backlightDevice + "/brightness";
              monitor.maxBrightnessPath = monitor.backlightDevice + "/max_brightness";

              var current = parseInt(lines[1]);
              var max = parseInt(lines[2]);
              if (!isNaN(current) && !isNaN(max) && max > 0) {
                monitor.maxBrightness = max;
                monitor.brightness = current / max;
                Logger.d("Brightness", "Internal brightness:", current + "/" + max + " =", monitor.brightness);
                Logger.d("Brightness", "Using backlight device:", monitor.backlightDevice);
              }
            } else {
              monitor.backlightDevice = "";
              monitor.brightnessPath = "";
              monitor.maxBrightnessPath = "";
            }
          }

          // Always update
          monitor.brightnessUpdated(monitor.brightness);
          root.monitorBrightnessChanged(monitor, monitor.brightness);
          monitor.initInProgress = false;
        }
      }
      onExited: (exitCode, exitStatus) => {
        monitor.initInProgress = false;
      }
    }

    readonly property real stepSize: Settings.data.brightness.brightnessStep / 100.0
    readonly property real minBrightnessValue: (Settings.data.brightness.enforceMinimum ? 0.01 : 0.0)

    // Timer for debouncing rapid changes
    readonly property Timer timer: Timer {
      interval: 250
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

      // Always update internal value and trigger UI feedback immediately
      monitor.brightness = value;
      monitor.brightnessUpdated(value);
      root.monitorBrightnessChanged(monitor, monitor.brightness);

      if (timer.running) {
        monitor.queuedBrightness = value;
        return;
      }

      // If a command is already running, queue this value
      if (monitor.commandRunning) {
        monitor.queuedBrightness = value;
        return;
      }

      // Execute the brightness change command
      if (isAppleDisplay) {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        setBrightnessProc.command = ["asdbctl", "set", rounded];
        setBrightnessProc.running = true;
      } else if (isDdc && busNum !== "") {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        var ddcValue = Math.round(value * monitor.maxBrightness);
        var ddcBus = busNum;
        Qt.callLater(() => {
                       setBrightnessProc.command = ["ddcutil", "-b", ddcBus, "--noverify", "--async", "--sleep-multiplier=0.05", "setvcp", "10", ddcValue];
                       setBrightnessProc.running = true;
                     });
      } else if (!isDdc) {
        monitor.commandRunning = true;
        monitor.ignoreNextChange = true;
        var backlightDeviceName = root.getBacklightDeviceName(monitor.backlightDevice);
        if (backlightDeviceName !== "") {
          setBrightnessProc.command = ["brightnessctl", "-d", backlightDeviceName, "s", rounded + "%"];
        } else {
          setBrightnessProc.command = ["brightnessctl", "s", rounded + "%"];
        }
        setBrightnessProc.running = true;
      }
    }

    function initBrightness(): void {
      monitor.initInProgress = true;
      if (isAppleDisplay) {
        initProc.command = ["asdbctl", "get"];
        initProc.running = true;
      } else if (isDdc && busNum !== "") {
        initProc.command = ["ddcutil", "-b", busNum, "--sleep-multiplier=0.05", "getvcp", "10", "--brief"];
        initProc.running = true;
      } else if (!isDdc) {
        // Internal backlight: first try explicit output mapping, then fall back to first available.
        var preferredDevicePath = root.getMappedBacklightDevice(modelData.name);
        var probeScript = [
          "preferred=\"$1\"",
          "if [ -n \"$preferred\" ] && [ ! -d \"$preferred\" ]; then preferred=\"/sys/class/backlight/$preferred\"; fi",
          "selected=\"\"",
          "if [ -n \"$preferred\" ] && [ -f \"$preferred/brightness\" ] && [ -f \"$preferred/max_brightness\" ]; then selected=\"$preferred\"; else for dev in /sys/class/backlight/*; do if [ -f \"$dev/brightness\" ] && [ -f \"$dev/max_brightness\" ]; then selected=\"$dev\"; break; fi; done; fi",
          "if [ -n \"$selected\" ]; then echo \"$selected\"; cat \"$selected/brightness\"; cat \"$selected/max_brightness\"; fi"
        ].join("; ");
        initProc.command = ["sh", "-c", probeScript, "sh", preferredDevicePath];
        initProc.running = true;
      } else {
        monitor.initInProgress = false;
      }
    }

    onBusNumChanged: initBrightness()
    onIsDdcChanged: initBrightness()
    Component.onCompleted: initBrightness()
  }
}
