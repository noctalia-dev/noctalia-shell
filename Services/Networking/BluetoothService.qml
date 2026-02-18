pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "../../Helpers/BluetoothUtils.js" as BluetoothUtils
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  // Constants (centralized tunables)
  readonly property int ctlPollMs: 10000
  readonly property int ctlPollSoonMs: 250

  readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter

  // Airplane mode status
  readonly property bool airplaneModeEnabled: Settings.data.network.airplaneModeEnabled
  property bool airplaneModeToggled: false

  // Power/blocked/availability state
  property bool ctlAvailable: false
  readonly property bool bluetoothAvailable: !!adapter || root.ctlAvailable
  readonly property bool enabled: adapter?.enabled ?? root.ctlPowered
  property bool ctlPowered: false
  property bool ctlPowerBlocked: false
  property bool ctlDiscovering: false
  property bool ctlDiscoverable: false

  // Exposed scanning flag for UI button state; reflects adapter discovery when available
  readonly property bool scanningActive: adapter?.discovering ?? root.ctlDiscovering

  // Adapter discoverability (advertising) flag
  readonly property bool discoverable: adapter?.discoverable ?? root.ctlDiscoverable
  readonly property var devices: adapter ? adapter.devices : null
  readonly property var connectedDevices: {
    if (!adapter || !adapter.devices) {
      return [];
    }
    return adapter.devices.values.filter(dev => dev && dev.connected);
  }

  // Current backend in use for scanning (e.g., "native", "bluetoothctl")
  property string backendUsed: ""

  // Experimental: best‑effort RSSI polling for connected devices (without root)
  // Enabled in debug mode or via user setting in Settings > Network
  property bool rssiPollingEnabled: Settings?.data?.network?.bluetoothRssiPollingEnabled || Settings?.isDebug || false
  // Interval can be configured from Settings; defaults to 60s
  property int rssiPollIntervalMs: Settings?.data?.network?.bluetoothRssiPollIntervalMs || 60000
  // RSSI helper sub‑component
  property BluetoothRssi rssi: BluetoothRssi {
    enabled: root.enabled && root.rssiPollingEnabled
    intervalMs: root.rssiPollIntervalMs
    connectedDevices: root.connectedDevices
  }

  // Tunables for CLI pairing/connect flow
  property int pairWaitSeconds: 45
  property int connectAttempts: 5
  property int connectRetryIntervalMs: 2000

  // Internal: temporarily pause discovery during pair/connect to reduce HCI churn
  property bool _discoveryWasRunning: false
  property bool _ctlInit: false
  // Track whether the bluetoothctl CLI is available on the system
  property bool ctlBinaryAvailable: false

  Timer {
    id: initDelayTimer
    interval: 3000
    running: true
    repeat: false
  }

  function init() {
    Logger.i("Bluetooth", "Service started");
  }

  Component.onCompleted: {
    pollCtlState();
    // Ensure Airplane Mode persists upon reboot
    if (root.airplaneModeEnabled) {
      Quickshell.execDetached(["rfkill", "block", "wifi"]);
      Quickshell.execDetached(["rfkill", "block", "bluetooth"]);
    }
  }

  // Handle system wakeup to force-poll and ensure state is up-to-date
  Connections {
    target: Time
    function onResumed() {
      Logger.i("Bluetooth", "System resumed - forcing state poll");
      requestCtlPoll();
    }
  }

  // Track adapter state changes
  Connections {
    target: adapter
    function onStateChanged() {
      if (!adapter || adapter.state === BluetoothAdapter.Enabling || adapter.state === BluetoothAdapter.Disabling) {
        return;
      }
      checkAirplaneMode.running = true;
    }
  }

  onAdapterChanged: {
    pollCtlState();
    if (!adapter) {
      ctlPollTimer.interval = 2000;
    }
  }

  function setAirplaneMode(state) {
    if (state) {
      Quickshell.execDetached(["rfkill", "block", "wifi"]);
      Quickshell.execDetached(["rfkill", "block", "bluetooth"]);
    } else {
      Quickshell.execDetached(["rfkill", "unblock", "wifi"]);
      Quickshell.execDetached(["rfkill", "unblock", "bluetooth"]);
    }
    if (!adapter) {
      root.ctlPowered = !state;
      root.ctlPowerBlocked = state;
      root.airplaneModeToggled = true;
      NetworkService.setWifiEnabled(!state);
      Settings.data.network.airplaneModeEnabled = state;
      ToastService.showNotice(I18n.tr("toast.airplane-mode.title"), state ? I18n.tr("common.enabled") : I18n.tr("common.disabled"), state ? "plane" : "plane-off");
      Logger.i("AirplaneMode", state ? "Wi-Fi & Bluetooth adapter blocked" : "Wi-Fi & Bluetooth adapter unblocked");
      root.airplaneModeToggled = false;
    }
  }

  Process {
    id: checkAirplaneMode
    running: false
    command: ["rfkill", "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        var output = this.text || "";
        var wifiBlocked = /^\d+:.*Wireless LAN[^\n]*\n\s*Soft blocked:\s*yes/im.test(output);
        var btBlocked = /^\d+:.*Bluetooth[^\n]*\n\s*Soft blocked:\s*yes/im.test(output);
        var isAirplaneModeActive = wifiBlocked && btBlocked;

        // Check if airplane mode has been toggled
        if (isAirplaneModeActive && !root.airplaneModeEnabled) {
          root.airplaneModeToggled = true;
          NetworkService.setWifiEnabled(false);
          Settings.data.network.airplaneModeEnabled = true;
          ToastService.showNotice(I18n.tr("toast.airplane-mode.title"), I18n.tr("common.enabled"), "plane");
          Logger.i("AirplaneMode", "Wi-Fi & Bluetooth adapter blocked");
        } else if (!isAirplaneModeActive && root.airplaneModeEnabled) {
          root.airplaneModeToggled = true;
          NetworkService.setWifiEnabled(true);
          Settings.data.network.airplaneModeEnabled = false;
          ToastService.showNotice(I18n.tr("toast.airplane-mode.title"), I18n.tr("common.disabled"), "plane-off");
          Logger.i("AirplaneMode", "Wi-Fi & Bluetooth adapter unblocked");
        } else if (adapter ? adapter.enabled : root.ctlPowered) {
          ToastService.showNotice(I18n.tr("common.bluetooth"), I18n.tr("common.enabled"), "bluetooth");
          Logger.d("Bluetooth", "Adapter enabled");
        } else {
          ToastService.showNotice(I18n.tr("common.bluetooth"), I18n.tr("common.disabled"), "bluetooth-off");
          Logger.d("Bluetooth", "Adapter disabled");
        }
        root.airplaneModeToggled = false;
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("AirplaneMode", "rfkill stderr:", text.trim());
        }
      }
    }
  }

  // Periodic state polling
  Timer {
    id: ctlPollTimer
    interval: adapter ? ctlPollMs : 2000
    repeat: true
    running: adapter || root.ctlBinaryAvailable
    onTriggered: {
      pollCtlState();
      var targetInterval = adapter ? ctlPollMs : 2000;
      if (interval !== targetInterval) {
        interval = targetInterval;
      }
    }
  }

  function requestCtlPoll(delayMs) {
    if (!adapter && !root.ctlBinaryAvailable) {
      return;
    }
    ctlPollTimer.interval = Math.max(50, delayMs || ctlPollSoonMs);
    ctlPollTimer.restart();
  }

  function pollCtlState() {
    if (!adapter && !root.ctlBinaryAvailable) {
      return;
    }
    if (ctlShowProcess.running) {
      return;
    }
    try {
      ctlShowProcess.running = true;
    } catch (_) {}
  }

  // One-time detection of bluetoothctl binary presence to avoid spamming logs on systems without Bluetooth
  Process {
    id: ctlBinaryCheck
    running: true
    command: ["sh", "-c", "command -v bluetoothctl >/dev/null 2>&1 && echo yes || echo no"]
    stdout: StdioCollector {
      onStreamFinished: {
        var available = (text || "").trim() === "yes";
        root.ctlBinaryAvailable = available;
        if (!available) {
          Logger.i("Bluetooth", "bluetoothctl not found; disabling CLI fallback polling");
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.d("Bluetooth", "bluetoothctl check stderr:", text.trim());
        }
      }
    }
  }

  // bluetoothctl state polling
  Process {
    id: ctlShowProcess
    command: ["bluetoothctl", "show"]
    running: false
    stdout: StdioCollector {
      id: ctlStdout
    }
    onExited: function (exitCode, exitStatus) {
      try {
        var text = ctlStdout.text || "";
        var lines = text.split('\n');
        var foundController = false;
        var powered = false;
        var powerBlocked = false;
        var discoverable = false;
        var discovering = false;

        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim();
          if (line.indexOf("Controller") === 0) {
            foundController = true;
          }

          var mp = line.match(/\bPowered:\s*(yes|no)\b/i);
          if (mp) {
            powered = (mp[1].toLowerCase() === "yes");
          }

          var mps = line.match(/\bPowerState:\s*([A-Za-z-]+)\b/i);
          if (mps) {
            powerBlocked = (mps[1].toLowerCase() === "off-blocked");
          }

          var md = line.match(/\bDiscoverable:\s*(yes|no)\b/i);
          if (md) {
            discoverable = (md[1].toLowerCase() === "yes");
          }

          var ms = line.match(/\bDiscovering:\s*(yes|no)\b/i);
          if (ms) {
            discovering = (ms[1].toLowerCase() === "yes");
          }
        }

        if (!adapter && (root.ctlPowered !== powered || root.ctlPowerBlocked !== powerBlocked)) {
          root.ctlPowered = powered;
          root.ctlPowerBlocked = powerBlocked;
          if (root._ctlInit) {
            checkAirplaneMode.running = true;
          }
          root._ctlInit = true;
        }

        root.ctlAvailable = foundController;
        root.ctlPowered = powered;
        root.ctlPowerBlocked = powerBlocked;
        root.ctlDiscoverable = discoverable;
        root.ctlDiscovering = discovering;
      } catch (e) {
        Logger.d("Bluetooth", "Failed to parse bluetoothctl show output", e);
      }
    }
  }

  // Persistent process for bluetoothctl scanning when native discovery is unavailable
  Process {
    id: bluetoothctlScanProcess
    command: ["bluetoothctl", "scan", "on"]
    onExited: Logger.d("Bluetooth", "bluetoothctl scan process exited.")
  }

  // Unify discovery controls
  function setScanActive(active) {
    if (!adapter && !root.ctlBinaryAvailable) {
      Logger.d("Bluetooth", "Scan request ignored: bluetoothctl unavailable");
      return;
    }
    var nativeSuccess = false;
    try {
      if (adapter && adapter.discovering !== undefined) {
        if (active || adapter.discovering) { // Only attempt to set if activating, or if deactivating and currently currently discovering
          adapter.discovering = active;
        }
        nativeSuccess = true; // Mark as success if adapter was handled without error
      }
    } catch (e) {
      Logger.e("Bluetooth", "setScanActive native failed", e);
    }

    if (!nativeSuccess) {
      if (active) {
        bluetoothctlScanProcess.running = true;
      } else {
        bluetoothctlScanProcess.running = false;
        btExec(["bluetoothctl", "scan", "off"]);
      }
    } else if (bluetoothctlScanProcess.running) {
      bluetoothctlScanProcess.running = false;
    }

    requestCtlPoll(ctlPollSoonMs);
  }

  // Adapter power (enable/disable) via bluetoothctl
  function setBluetoothEnabled(state) {
    Logger.i("Bluetooth", "SetBluetoothEnabled", state);
    if (!adapter && !root.ctlBinaryAvailable) {
      Logger.i("Bluetooth", "Enable/Disable skipped: no adapter or bluetoothctl");
      return;
    }
    try {
      if (adapter) {
        adapter.enabled = state;
      } else {
        btExec(["bluetoothctl", "power", state ? "on" : "off"]);
        root.ctlPowered = state;
        requestCtlPoll(ctlPollSoonMs);
        ToastService.showNotice(I18n.tr("common.bluetooth"), state ? I18n.tr("common.enabled") : I18n.tr("common.disabled"), state ? "bluetooth" : "bluetooth-off");
        Logger.d("Bluetooth", state ? "Adapter enabled" : "Adapter disabled");
      }
    } catch (e) {
      Logger.w("Bluetooth", "Enable/Disable failed", e);
      ToastService.showWarning(I18n.tr("common.bluetooth"), I18n.tr("toast.bluetooth.state-change-failed"));
    }
  }

  // Toggle adapter discoverability (advertising visibility) via bluetoothctl
  function setDiscoverable(state) {
    if (!adapter && !root.ctlBinaryAvailable) {
      Logger.d("Bluetooth", "Discoverable change skipped: no adapter or bluetoothctl");
      return;
    }
    try {
      if (adapter) {
        adapter.discoverable = state;
      } else {
        btExec(["bluetoothctl", "discoverable", state ? "on" : "off"]);
        root.ctlDiscoverable = state; // optimistic
        requestCtlPoll(ctlPollSoonMs);
      }
      Logger.i("Bluetooth", "Discoverable state set to:", state);
    } catch (e) {
      Logger.w("Bluetooth", "Failed to change discoverable state", e);
      ToastService.showWarning(I18n.tr("common.bluetooth"), I18n.tr("toast.bluetooth.discoverable-change-failed"));
    }
  }

  function sortDevices(devices) {
    return devices.sort(function (a, b) {
      var aName = a.name || a.deviceName || "";
      var bName = b.name || b.deviceName || "";

      var aHasRealName = aName.indexOf(" ") !== -1 && aName.length > 3;
      var bHasRealName = bName.indexOf(" ") !== -1 && bName.length > 3;

      if (aHasRealName && !bHasRealName) {
        return -1;
      }
      if (!aHasRealName && bHasRealName) {
        return 1;
      }

      var aSignal = (a.signalStrength !== undefined && a.signalStrength > 0) ? a.signalStrength : 0;
      var bSignal = (b.signalStrength !== undefined && b.signalStrength > 0) ? b.signalStrength : 0;
      return bSignal - aSignal;
    });
  }

  function getDeviceIcon(device) {
    if (!device) {
      return "bt-device-generic";
    }
    return BluetoothUtils.deviceIcon(device.name || device.deviceName, device.icon);
  }

  function canConnect(device) {
    if (!device) {
      return false;
    }
    return !device.connected && (device.paired || device.trusted) && !device.pairing && !device.blocked;
  }

  function canDisconnect(device) {
    if (!device) {
      return false;
    }
    return device.connected && !device.pairing && !device.blocked;
  }

  // Textual signal quality (translated)
  function getSignalStrength(device) {
    var p = getSignalPercent(device);
    if (p === null) {
      return I18n.tr("bluetooth.panel.signal-text-unknown");
    }
    if (p >= 80) {
      return I18n.tr("bluetooth.panel.signal-text-excellent");
    }
    if (p >= 60) {
      return I18n.tr("bluetooth.panel.signal-text-good");
    }
    if (p >= 40) {
      return I18n.tr("bluetooth.panel.signal-text-fair");
    }
    if (p >= 20) {
      return I18n.tr("bluetooth.panel.signal-text-poor");
    }
    return I18n.tr("bluetooth.panel.signal-text-very-poor");
  }

  // Numeric helpers for UI rendering
  function getSignalPercent(device) {
    // Establish binding dependency so UI updates when RSSI cache changes
    var _v = rssi.version;
    return BluetoothUtils.signalPercent(device, rssi.cache, _v);
  }

  function getBatteryPercent(device) {
    return BluetoothUtils.batteryPercent(device);
  }

  function getSignalIcon(device) {
    var p = getSignalPercent(device);
    return BluetoothUtils.signalIcon(p);
  }

  function isDeviceBusy(device) {
    if (!device) {
      return false;
    }
    return device.pairing || device.state === BluetoothDevice.Disconnecting || device.state === BluetoothDevice.Connecting;
  }

  // Return a stable unique key for a device (prefer MAC address)
  function deviceKey(device) {
    return BluetoothUtils.deviceKey(device);
  }

  // Deduplicate a list of devices using the stable key
  function dedupeDevices(devList) {
    return BluetoothUtils.dedupeDevices(devList);
  }

  // Separate capability helpers
  function canPair(device) {
    if (!device) {
      return false;
    }
    return !device.connected && !device.paired && !device.trusted && !device.pairing && !device.blocked;
  }

  // Pairing and unpairing helpers
  function pairDevice(device) {
    if (!device) {
      return;
    }
    ToastService.showNotice(I18n.tr("common.bluetooth"), I18n.tr("common.pairing"), "bluetooth");
    try {
      pairWithBluetoothctl(device);
    } catch (e) {
      Logger.w("Bluetooth", "pairDevice failed", e);
      ToastService.showWarning(I18n.tr("common.bluetooth"), I18n.tr("toast.bluetooth.pair-failed"));
    }
  }

  // Interaction state
  property bool pinRequired: false

  function submitPin(pin) {
    if (pairingProcess.running) {
      pairingProcess.write(pin + "\n");
      root.pinRequired = false;
    }
  }

  function cancelPairing() {
    if (pairingProcess.running) {
      pairingProcess.running = false;
    }
    root.pinRequired = false;
  }

  // Interactive pairing process
  Process {
    id: pairingProcess
    stdout: SplitParser {
      onRead: data => {
        Logger.d("Bluetooth", data);
        if (data.indexOf("PIN_REQUIRED") !== -1) {
          root.pinRequired = true;
          Logger.i("Bluetooth", "PIN required for pairing");
        }
      }
    }
    onExited: {
      root.pinRequired = false;
      Logger.i("Bluetooth", "Pairing process exited.");
      // Restore discovery if we paused it
      if (root._discoveryWasRunning) {
        root.setScanActive(true);
      }
      root._discoveryWasRunning = false;
      root.requestCtlPoll();
    }
    environment: ({
                    "LC_ALL": "C"
                  })
  }

  // Pair using bluetoothctl which registers its own BlueZ agent internally.
  function pairWithBluetoothctl(device) {
    if (!device) {
      return;
    }
    var addr = BluetoothUtils.macFromDevice(device);
    if (!addr || addr.length < 7) {
      Logger.w("Bluetooth", "pairWithBluetoothctl: no valid address for device");
      return;
    }

    Logger.i("Bluetooth", "pairWithBluetoothctl", addr);

    if (pairingProcess.running) {
      pairingProcess.running = false;
    }
    root.pinRequired = false;

    const pairWait = Math.max(5, Number(root.pairWaitSeconds) | 0);
    const attempts = Math.max(1, Number(root.connectAttempts) | 0);
    const intervalMs = Math.max(500, Number(root.connectRetryIntervalMs) | 0);
    const intervalSec = Math.max(1, Math.round(intervalMs / 1000));

    // Pause discovery during pair/connect to avoid interference
    root._discoveryWasRunning = root.scanningActive;
    if (root.scanningActive) {
      root.setScanActive(false);
    }

    const scriptPath = Quickshell.shellDir + "/Scripts/python/src/network/bluetooth-pair.py";
    pairingProcess.command = ["python3", scriptPath, String(addr), String(pairWait), String(attempts), String(intervalSec)];
    pairingProcess.running = true;
  }

  // Helper to run bluetoothctl and scripts with consistent error logging
  function btExec(args) {
    try {
      Quickshell.execDetached(args);
    } catch (e) {
      Logger.w("Bluetooth", "btExec failed", e);
    }
  }

  // Status key for a device (untranslated)
  function getStatusKey(device) {
    if (!device) {
      return "";
    }
    try {
      if (device.pairing)
        return "pairing";
      if (device.blocked)
        return "blocked";
      if (device.state === BluetoothDevice.Connecting)
        return "connecting";
      if (device.state === BluetoothDevice.Disconnecting)
        return "disconnecting";
    } catch (_) {}
    return "";
  }

  function unpairDevice(device) {
    forgetDevice(device);
  }

  function connectDeviceWithTrust(device) {
    if (!device) {
      return;
    }
    try {
      device.trusted = true;
      device.connect();
    } catch (e) {
      Logger.w("Bluetooth", "connectDeviceWithTrust failed", e);
      ToastService.showWarning(I18n.tr("common.bluetooth"), I18n.tr("toast.bluetooth.connect-failed"));
    }
  }

  function disconnectDevice(device) {
    if (!device) {
      return;
    }
    try {
      device.disconnect();
    } catch (e) {
      Logger.w("Bluetooth", "disconnectDevice failed", e);
      ToastService.showWarning(I18n.tr("common.bluetooth"), I18n.tr("toast.bluetooth.disconnect-failed"));
    }
  }

  function forgetDevice(device) {
    if (!device) {
      return;
    }
    try {
      device.trusted = false;
      device.forget();
    } catch (e) {
      Logger.w("Bluetooth", "forgetDevice failed", e);
      ToastService.showWarning(I18n.tr("common.bluetooth"), I18n.tr("toast.bluetooth.forget-failed"));
    }
  }
}
