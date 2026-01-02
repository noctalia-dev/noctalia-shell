pragma Singleton
import QtQml

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "../../Helpers/BluetoothUtils.js" as BluetoothUtils
import "."
import qs.Commons
import qs.Services.UI

QtObject {
  id: root

  // ---- Constants (centralized tunables) ----
  readonly property int ctlPollMs: 1500
  readonly property int ctlPollSoonMs: 250
  readonly property int scanAutoStopMs: 6000

  property bool airplaneModeToggled: false
  readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter

  // Power/blocked state
  property bool enabled: false // driven by bluetoothctl
  property bool ctlPowered: false
  property bool ctlDiscovering: false
  property bool ctlDiscoverable: false
  // Adapter discoverability (advertising) flag (driven by bluetoothctl)
  readonly property bool discoverable: root.ctlDiscoverable
  readonly property var devices: adapter ? adapter.devices : null
  readonly property var connectedDevices: {
    if (!adapter || !adapter.devices) {
      return [];
    }
    return adapter.devices.values.filter(function (dev) {
      return dev && dev.connected;
    });
  }

  // Experimental: best‑effort RSSI polling for connected devices (without root)
  // Enabled in debug mode or via user setting in Settings > Network
  property bool rssiPollingEnabled: (Settings && (Settings.isDebug || (Settings.data && Settings.data.network && Settings.data.network.bluetoothRssiPollingEnabled))) ? true : false
  // Interval can be configured from Settings; defaults to 10s
  property int rssiPollIntervalMs: (Settings && Settings.data && Settings.data.network && Settings.data.network.bluetoothRssiPollIntervalMs) ? Settings.data.network.bluetoothRssiPollIntervalMs : 10000
  // RSSI helper sub‑component
  property BluetoothRssi rssi: BluetoothRssi {
    enabled: root.enabled && root.rssiPollingEnabled
    intervalMs: root.rssiPollIntervalMs
    connectedDevices: root.connectedDevices
  }

  // Tunables for CLI pairing/connect flow
  property int pairWaitSeconds: 20
  property int connectAttempts: 5
  property int connectRetryIntervalMs: 2000

  // Internal: temporarily pause discovery during pair/connect to reduce HCI churn
  // Use a resume deadline to coalesce overlapping pauses safely
  property bool _discoveryWasRunning: false
  property double _discoveryResumeAtMs: 0
  // Timer used to restore discovery after temporary pause during pair/connect
  property Timer restoreDiscoveryTimer: Timer {
    repeat: false
    onTriggered: {
      const now = Date.now();
      if (now < root._discoveryResumeAtMs) {
        // Not yet time to resume; reschedule
        interval = Math.max(100, root._discoveryResumeAtMs - now);
        restart();
        return;
      }
      if (root._discoveryWasRunning) {
        root.setScanActive(true, 0);
      }
      root._discoveryWasRunning = false;
      root._discoveryResumeAtMs = 0;
    }
  }

  function _pauseDiscoveryFor(ms) {
    try {
      // Remember if discovery was running before the first pause
      root._discoveryWasRunning = root._discoveryWasRunning || !!root.ctlDiscovering;
      if (root.ctlDiscovering) {
        root.setScanActive(false, 0);
      }
      if (ms && ms > 0) {
        const now = Date.now();
        const resumeAt = now + ms;
        if (resumeAt > root._discoveryResumeAtMs)
          root._discoveryResumeAtMs = resumeAt;
        restoreDiscoveryTimer.interval = Math.max(100, root._discoveryResumeAtMs - now);
        restoreDiscoveryTimer.restart();
      }
    } catch (_) {}
  }

  // Unify discovery controls and auto‑stop window
  function setScanActive(active, durationMs) {
    // Cancel any scheduled resume so manual toggle wins
    try {
      root._discoveryResumeAtMs = 0;
      restoreDiscoveryTimer.stop();
      root._discoveryWasRunning = false;
    } catch (_) {}

    // Prefer Quickshell API if available, fall back to bluetoothctl
    try {
      if (adapter) {
        if (active && adapter.startDiscovery !== undefined) {
          adapter.startDiscovery();
        } else if (!active && adapter.stopDiscovery !== undefined) {
          adapter.stopDiscovery();
        }
      }
    } catch (e1) {}

    // Always issue bluetoothctl as a compatibility fallback
    btExec(["bluetoothctl", "scan", active ? "on" : "off"]);

    if (active && durationMs && durationMs > 0) {
      manualScanTimer.interval = durationMs;
      manualScanTimer.restart();
    } else {
      if (manualScanTimer.running)
        manualScanTimer.stop();
    }
    requestCtlPoll(ctlPollSoonMs);
  }

  // Explicit toggle that cancels any pending restore so UI button behaves predictably
  function toggleDiscovery() {
    if (!adapter)
      return;
    setScanActive(!root.scanningActive, scanAutoStopMs);
  }

  // Auto-stop manual discovery after a short window
  property Timer manualScanTimer: Timer {
    repeat: false
    onTriggered: {
      // Stop scan if currently active
      if (root.scanningActive) {
        root.setScanActive(false, 0);
      }
    }
  }

  // Exposed scanning flag for UI button state; reflects adapter discovery when available
  readonly property bool scanningActive: ((adapter && adapter.discovering) ? true : (root.ctlDiscovering === true)) || manualScanTimer.running

  function init() {
    Logger.i("Bluetooth", "Service started");
  }

  Component.onCompleted: {
    // Prime state immediately so UI reflects correct power/discovery flags
    pollCtlState();
  }

  // Note: We intentionally avoid creating or managing a custom BlueZ agent in-process.
  // Pairing flows are delegated to `bluetoothctl` as needed to keep behavior
  // consistent and reduce maintenance complexity.

  // No implicit discovery auto-start; state polled from bluetoothctl instead

  // Track adapter state changes (for enabled/disabled logging only; avoid discovery writes here)
  property Connections adapterConnections: Connections {
    target: adapter
    function onStateChanged() {
      if (!adapter)
        return;
      if (adapter.state === BluetoothAdapterState.Enabled) {
        Logger.d("Bluetooth", "Adapter enabled");
        // Keep UI default to refresh icon; bluetoothctl polling will set ctlDiscovering accordingly.
      } else if (adapter.state === BluetoothAdapterState.Disabled) {
        Logger.d("Bluetooth", "Adapter disabled");
      }
    }
  }

  // --- bluetoothctl state polling ---
  property Process ctlShowProcess: Process {
    id: ctlProc
    running: false
    stdout: StdioCollector {
      id: ctlStdout
    }
    onExited: function (exitCode, exitStatus) {
      try {
        var text = ctlStdout.text || "";
        // Parse Powered/Discoverable/Discovering lines
        var mp = text.match(/\bPowered:\s*(yes|no)\b/i);
        if (mp && mp.length > 1) {
          root.ctlPowered = (mp[1].toLowerCase() === "yes");
          root.enabled = root.ctlPowered;
        }
        var md = text.match(/\bDiscoverable:\s*(yes|no)\b/i);
        if (md && md.length > 1) {
          root.ctlDiscoverable = (md[1].toLowerCase() === "yes");
        }
        var ms = text.match(/\bDiscovering:\s*(yes|no)\b/i);
        if (ms && ms.length > 1) {
          root.ctlDiscovering = (ms[1].toLowerCase() === "yes");
        }
      } catch (e) {
        Logger.d("Bluetooth", "Failed to parse bluetoothctl show output", e);
      }
    }
  }

  function pollCtlState() {
    if (ctlProc.running)
      return;
    try {
      ctlProc.command = ["bluetoothctl", "show"];
      ctlProc.running = true;
    } catch (_) {}
  }

  // Periodic state polling
  property Timer ctlPollTimer: Timer {
    interval: ctlPollMs
    repeat: true
    running: true
    onTriggered: pollCtlState()
  }

  // Short-delay poll scheduler
  property Timer pollCtlStateSoonTimer: Timer {
    interval: ctlPollSoonMs
    repeat: false
    onTriggered: pollCtlState()
  }

  function requestCtlPoll(delayMs) {
    pollCtlStateSoonTimer.interval = Math.max(50, delayMs || ctlPollSoonMs);
    pollCtlStateSoonTimer.restart();
  }

  // Adapter power (enable/disable) via bluetoothctl
  function setBluetoothEnabled(state) {
    Logger.i("Bluetooth", "SetBluetoothEnabled", state);
    try {
      btExec(["bluetoothctl", "power", state ? "on" : "off"]);
      root.ctlPowered = !!state;
      root.enabled = root.ctlPowered;
      if (state) {
        ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.enabled"), "bluetooth");
      } else {
        ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.disabled"), "bluetooth-off");
      }
      requestCtlPoll(ctlPollSoonMs);
    } catch (e) {
      Logger.w("Bluetooth", "Enable/Disable failed", e);
      ToastService.showWarning(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.state-change-failed"));
    }
  }

  // Toggle adapter discoverability (advertising visibility) via bluetoothctl
  function setDiscoverable(state) {
    try {
      btExec(["bluetoothctl", "discoverable", state ? "on" : "off"]);
      root.ctlDiscoverable = !!state; // optimistic
      requestCtlPoll(ctlPollSoonMs);
      if (state) {
        ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.discoverable-enabled"), "broadcast");
      } else {
        ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.discoverable-disabled"), "broadcast-off");
      }
      Logger.i("Bluetooth", "Discoverable state set to:", state);
    } catch (e) {
      Logger.w("Bluetooth", "Failed to change discoverable state", e);
      ToastService.showWarning(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.discoverable-change-failed"));
    }
  }

  function sortDevices(devices) {
    return devices.sort(function (a, b) {
      var aName = a.name || a.deviceName || "";
      var bName = b.name || b.deviceName || "";

      var aHasRealName = aName.indexOf(" ") !== -1 && aName.length > 3;
      var bHasRealName = bName.indexOf(" ") !== -1 && bName.length > 3;

      if (aHasRealName && !bHasRealName)
        return -1;
      if (!aHasRealName && bHasRealName)
        return 1;

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
    if (!device)
      return false;

    /*
    Paired
    Means you’ve successfully exchanged keys with the device.
    The devices remember each other and can authenticate without repeating the pairing process.
    Example: once your headphones are paired, you don’t need to type a PIN every time.
    Hence, instead of !device.paired, should be device.connected
    */
    // Only allow connect if device is already paired or trusted
    return !device.connected && (device.paired || device.trusted) && !device.pairing && !device.blocked;
  }

  function canDisconnect(device) {
    if (!device)
      return false;
    return device.connected && !device.pairing && !device.blocked;
  }
  // Status string for a device (translated)
  function getStatusString(device) {
    if (!device)
      return "";
    try {
      if (device.pairing)
        return I18n.tr("bluetooth.panel.pairing");
      if (device.blocked)
        return I18n.tr("bluetooth.panel.blocked");
      if (device.state === BluetoothDeviceState.Connecting)
        return I18n.tr("bluetooth.panel.connecting");
      if (device.state === BluetoothDeviceState.Disconnecting)
        return I18n.tr("bluetooth.panel.disconnecting");
    } catch (_) {}
    return "";
  }

  // Textual signal quality (translated)
  function getSignalStrength(device) {
    var p = getSignalPercent(device);
    if (p === null)
      return I18n.tr("bluetooth.panel.signal-text.unknown");
    if (p >= 80)
      return I18n.tr("bluetooth.panel.signal-text.excellent");
    if (p >= 60)
      return I18n.tr("bluetooth.panel.signal-text.good");
    if (p >= 40)
      return I18n.tr("bluetooth.panel.signal-text.fair");
    if (p >= 20)
      return I18n.tr("bluetooth.panel.signal-text.poor");
    return I18n.tr("bluetooth.panel.signal-text.very-poor");
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

    return device.pairing || device.state === BluetoothDeviceState.Disconnecting || device.state === BluetoothDeviceState.Connecting;
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
    if (!device)
      return false;
    return !device.connected && !device.paired && !device.trusted && !device.pairing && !device.blocked;
  }

  // Pairing and unpairing helpers
  function pairDevice(device) {
    if (!device)
      return;
    ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("bluetooth.panel.pairing"), "bluetooth");
    // Delegate pairing to bluetoothctl which registers/uses its own agent
    try {
      pairWithBluetoothctl(device);
    } catch (e) {
      Logger.w("Bluetooth", "pairDevice failed", e);
      ToastService.showWarning(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.pair-failed"));
    }
  }

  // Pair using bluetoothctl which registers its own BlueZ agent internally.
  function pairWithBluetoothctl(device) {
    if (!device)
      return;
    var addr = BluetoothUtils.macFromDevice(device);
    if (!addr || addr.length < 7) {
      Logger.w("Bluetooth", "pairWithBluetoothctl: no valid address for device");
      return;
    }

    Logger.i("Bluetooth", "pairWithBluetoothctl", addr);

    // Compute bounded waits from tunables
    const pairWait = Math.max(5, Number(root.pairWaitSeconds) | 0);
    const attempts = Math.max(1, Number(root.connectAttempts) | 0);
    const intervalMs = Math.max(500, Number(root.connectRetryIntervalMs) | 0);
    const intervalSec = Math.max(1, Math.round(intervalMs / 1000));

    // Pause discovery during pair/connect to avoid interference
    const totalPauseMs = (pairWait * 1000) + (attempts * intervalSec * 1000) + 2000;
    _pauseDiscoveryFor(totalPauseMs);

    // Prefer external dev script for pairing/connecting; executed detached
    const scriptPath = Quickshell.shellDir + "/Bin/bluetooth-connect.sh";
    // Use bash explicitly to avoid relying on executable bit in all environments
    btExec(["bash", scriptPath, String(addr), String(pairWait), String(attempts), String(intervalSec)]);
  }

  // --- Helper to run bluetoothctl and scripts with consistent error logging ---
  function btExec(args) {
    try {
      Quickshell.execDetached(args);
    } catch (e) {
      Logger.w("Bluetooth", "btExec failed", e);
    }
  }

  // Status key for a device (untranslated)
  function getStatusKey(device) {
    if (!device)
      return "";
    try {
      if (device.pairing)
        return "pairing";
      if (device.blocked)
        return "blocked";
      if (device.state === BluetoothDeviceState.Connecting)
        return "connecting";
      if (device.state === BluetoothDeviceState.Disconnecting)
        return "disconnecting";
    } catch (_) {}
    return "";
  }

  function unpairDevice(device) {
    // Alias to forgetDevice for clarity in UI
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
      ToastService.showWarning(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.connect-failed"));
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
      ToastService.showWarning(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.disconnect-failed"));
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
      ToastService.showWarning(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.forget-failed"));
    }
  }
}
