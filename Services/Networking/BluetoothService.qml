pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "../../Helpers/BluetoothUtils.js" as BluetoothUtils
import qs.Commons
import qs.Services.System
import qs.Services.UI

Singleton {
  id: root

  readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter

  // Power/availability state
  readonly property bool bluetoothAvailable: !!adapter
  readonly property bool enabled: adapter?.enabled ?? false
  readonly property bool blocked: adapter?.state === BluetoothAdapter.Blocked

  // Exposed scanning flag for UI button state; reflects adapter discovery when available
  readonly property bool scanningActive: adapter?.discovering ?? false

  // Adapter discoverability (advertising) flag
  readonly property bool discoverable: adapter?.discoverable ?? false
  readonly property var devices: adapter ? adapter.devices : null
  readonly property var connectedDevices: {
    if (!adapter || !adapter.devices) {
      return [];
    }
    return adapter.devices.values.filter(dev => dev && dev.connected);
  }

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

  // Interaction state
  property bool pinRequired: false

  // Internal variables
  property bool _discoveryWasRunning: false
  property bool _ctlInit: false
  property var _autoConnectQueue: []

  // Persistent cache for per-device auto-connect toggle
  property string cacheFile: Settings.cacheDir + "bluetooth_devices.json"

  FileView {
    id: cacheFileView
    path: root.cacheFile
    printErrors: false

    JsonAdapter {
      id: cacheAdapter
      property var autoConnectSettings: ({})
    }
  }

  // Handle system wakeup to force-poll and ensure state is up-to-date
  Connections {
    target: Time
    function onResumed() {
      Logger.i("Bluetooth", "System resumed - forcing state poll");
      ctlPollTimer.restart();
    }
  }

  // Track adapter state changes
  Connections {
    target: adapter
    function onStateChanged() {
      if (!adapter || adapter.state === BluetoothAdapter.Enabling || adapter.state === BluetoothAdapter.Disabling) {
        return;
      }
      checkAirplaneMode();
    }
    function onEnabledChanged() {
      if (adapter && adapter.enabled && Settings.data.network.bluetoothAutoConnect) {
        autoConnectTimer.restart();
      }
    }
  }

  Connections {
    target: Settings.data.network
    function onBluetoothAutoConnectChanged() {
      if (Settings.data.network.bluetoothAutoConnect && adapter && adapter.enabled) {
        autoConnectTimer.restart();
      } else {
        autoConnectTimer.stop();
      }
    }
  }

  Component.onCompleted: {
    Logger.i("Bluetooth", "Service started");
    autoConnectTimer.restart();
  }

  Timer {
    id: autoConnectTimer
    interval: 1500
    repeat: false
    onTriggered: attemptAutoConnect()
  }

  Timer {
    id: autoConnectStepTimer
    interval: 500
    repeat: false
    onTriggered: {
      var device = root._autoConnectQueue.shift();
      if (device && device.paired && !device.connected && !device.blocked) {
        Logger.i("Bluetooth", "Auto-connecting to:", device.name || device.deviceName);
        connectDeviceWithTrust(device);
      }
      if (root._autoConnectQueue.length > 0) {
        autoConnectStepTimer.restart();
      }
    }
  }

  Timer {
    id: ctlPollTimer
    interval: 250
    running: false
    onTriggered: {
      if (!adapter || !ProgramCheckerService.bluetoothctlAvailable) {
        return;
      }
      ctlPollProcess.running = true;
    }
  }

  // Adapter power (enable/disable) via bluetoothctl
  function setBluetoothEnabled(state) {
    if (!adapter) {
      Logger.d("Bluetooth", "Enable/Disable skipped: no adapter");
      return;
    }
    try {
      adapter.enabled = state;
      Logger.i("Bluetooth", "SetBluetoothEnabled", state);
    } catch (e) {
      Logger.w("Bluetooth", "Enable/Disable failed", e);
      ToastService.showWarning(I18n.tr("common.bluetooth"), I18n.tr("toast.bluetooth.state-change-failed"));
    }
  }

  // Check if airplane mode has been toggled
  function checkAirplaneMode() {
    var isAirplaneModeActive = !NetworkService.wifiEnabled && adapter.state === BluetoothAdapter.Blocked;
    if (isAirplaneModeActive && !NetworkService.airplaneModeEnabled) {
      NetworkService.airplaneModeToggled = true;
      NetworkService.airplaneModeEnabled = true;
      ToastService.showNotice(I18n.tr("toast.airplane-mode.title"), I18n.tr("common.enabled"), "plane");
      Logger.i("AirplaneMode", "Enabled");
    } else if (!isAirplaneModeActive && NetworkService.airplaneModeEnabled) {
      NetworkService.airplaneModeToggled = true;
      NetworkService.airplaneModeEnabled = false;
      ToastService.showNotice(I18n.tr("toast.airplane-mode.title"), I18n.tr("common.disabled"), "plane-off");
      Logger.i("AirplaneMode", "Disabled");
    } else if (adapter.enabled) {
      ToastService.showNotice(I18n.tr("common.bluetooth"), I18n.tr("common.enabled"), "bluetooth");
      Logger.d("Bluetooth", "Adapter enabled");
    } else {
      ToastService.showNotice(I18n.tr("common.bluetooth"), I18n.tr("common.disabled"), "bluetooth-off");
      Logger.d("Bluetooth", "Adapter disabled");
    }
  }

  // Unify discovery controls
  function setScanActive(active) {
    if (!adapter) {
      Logger.d("Bluetooth", "Scan request ignored: adapter unavailable");
      return;
    }
    try {
      if (active || adapter.discovering) { // Only attempt to set if activating, or if deactivating and currently currently discovering
        adapter.discovering = active;
      }
    } catch (e) {
      Logger.e("Bluetooth", "setScanActive failed", e);
    }
  }

  // Toggle adapter discoverability (advertising visibility) via bluetoothctl
  function setDiscoverable(state) {
    if (!adapter) {
      Logger.d("Bluetooth", "Discoverable change skipped: no adapter");
      return;
    }
    try {
      adapter.discoverable = state;
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

    // Temporarily pause discovery during pair/connect to reduce HCI churn
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

  function getDeviceAutoConnect(device) {
    if (!device || !device.address || !cacheAdapter.autoConnectSettings) {
      return false;
    }
    const mac = device.address;
    const settings = cacheAdapter.autoConnectSettings[mac];
    return settings ? !!settings.autoConnect : false;
  }

  function setDeviceAutoConnect(device, enabled) {
    if (!device || !device.address) {
      return;
    }
    const mac = device.address;
    let settings = cacheAdapter.autoConnectSettings || ({});
    if (enabled) {
      settings[mac] = {
        autoConnect: true,
        deviceName: device.name || device.deviceName || ""
      };
    } else {
      delete settings[mac];
    }
    cacheAdapter.autoConnectSettings = settings;
    cacheFileView.writeAdapter();
  }

  function attemptAutoConnect() {
    if (NetworkService.airplaneModeEnabled || !adapter || !adapter.enabled || !Settings.data.network.bluetoothAutoConnect) {
      return;
    }

    _autoConnectQueue = adapter.devices.values.filter(dev => dev && dev.paired && !dev.connected && !dev.blocked && getDeviceAutoConnect(dev) === true);

    if (root._autoConnectQueue.length > 0) {
      autoConnectStepTimer.restart();
    }
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

  // Poll Bluetooth power state with bluetoothctl to handle a Quickshell bug on resume after suspend
  Process {
    id: ctlPollProcess
    command: ["bluetoothctl", "show"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var powered = false;
        var mp = text.match(/\bPowered:\s*(yes|no)\b/i);
        if (mp) {
          powered = mp[1].toLowerCase() === 'yes';
        }
        if (adapter.enabled !== powered) {
          adapter.enabled = powered;
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.d("Bluetooth", "Failed to parse bluetoothctl show output" + text);
        }
      }
    }
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
    }
    environment: ({
                    "LC_ALL": "C"
                  })
  }
}
