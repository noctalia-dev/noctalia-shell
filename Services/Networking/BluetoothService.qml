pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  property bool airplaneModeToggled: false
  property bool lastBluetoothBlocked: false
  readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
  readonly property int state: (adapter && adapter.state !== undefined) ? adapter.state : 0
  readonly property bool available: (adapter !== null)
  readonly property bool enabled: (adapter && adapter.enabled !== undefined) ? adapter.enabled : false
  readonly property bool blocked: (adapter && adapter.state === BluetoothAdapterState.Blocked)
  readonly property bool discovering: (adapter && adapter.discovering) ? adapter.discovering : false
  // Adapter discoverability (advertising) flag
  readonly property bool discoverable: (adapter && adapter.discoverable !== undefined) ? adapter.discoverable : false
  readonly property var devices: adapter ? adapter.devices : null
  readonly property var pairedDevices: {
    if (!adapter || !adapter.devices) {
      return [];
    }
    return adapter.devices.values.filter(function (dev) {
      return dev && (dev.paired || dev.trusted);
    });
  }
  readonly property var connectedDevices: {
    if (!adapter || !adapter.devices) {
      return [];
    }
    return adapter.devices.values.filter(function (dev) {
      return dev && dev.connected;
    });
  }

  readonly property var allDevicesWithBattery: {
    if (!adapter || !adapter.devices) {
      return [];
    }
    return adapter.devices.values.filter(function (dev) {
      return dev && dev.batteryAvailable && dev.battery > 0;
    });
  }

  function init() {
    Logger.i("Bluetooth", "Service started");
  }

  // --- Bluetooth Agent ---
  // Registers an authentication agent with BlueZ so pairing that requires
  // user interaction (numeric comparison, passkey, etc.) can complete.
  // Note: We keep the first implementation minimal to unblock common cases
  // (numeric comparison). A richer UI prompt can be added later.
  // The Quickshell Bluetooth module provides the Agent type and handlers.

  // Pending request context (exposed for future UI prompts)
  property var pendingPairDevice: null
  property string pendingPairType: ""   // "confirmation" | "passkey" | "pincode"
  property string pendingPairPasskey: ""

  // Dynamically create agent if the type exists (older Quickshell builds may not provide BluetoothAgent)
  property var btAgent: null
  property bool btAgentRegistered: false
  // Track if we attempted to start an external fallback agent
  property bool fallbackAgentAttempted: false

  // Start a fallback agent using bluetoothctl when Quickshell's BluetoothAgent
  // type is unavailable. This registers a BlueZ agent with KeyboardDisplay
  // capability so pairing can proceed.
  function startFallbackAgent() {
    if (fallbackAgentAttempted)
      return;
    fallbackAgentAttempted = true;
    try {
      Logger.i("Bluetooth", "Starting fallback bluetoothctl agent (KeyboardDisplay)");
      fallbackBluetoothctlAgent.running = true;
    } catch (e) {
      Logger.w("Bluetooth", "Failed to start fallback bluetoothctl agent", e);
    }
  }

  // Force-start the fallback agent shortly after startup to guarantee
  // BlueZ has an agent even if the dynamic QML agent is unavailable or fails.
  Timer {
    id: fallbackForceTimer
    interval: 500
    running: true
    repeat: false
    onTriggered: startFallbackAgent()
  }

  Component.onCompleted: {
    try {
      const qml = `
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Commons
import qs.Services.UI

BluetoothAgent {
  id: dynAgent
  capability: BluetoothAgentCapability.KeyboardDisplay

  onRequestConfirmation: function(device, passkey, accept, reject) {
    try {
      Logger.i("Bluetooth", "Agent RequestConfirmation", passkey);
      ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.confirm-code", { value: passkey }), "bluetooth");
      accept();
    } catch (e) {
      Logger.w("Bluetooth", "Agent RequestConfirmation failed", e);
      reject();
    }
  }

  onRequestPasskey: function(device, accept, reject) {
    try {
      Logger.i("Bluetooth", "Agent RequestPasskey");
      ToastService.showWarning(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.passkey-required"));
    } catch (e) {
      Logger.w("Bluetooth", "Agent RequestPasskey handler error", e);
    } finally {
      reject();
    }
  }

  onRequestPinCode: function(device, accept, reject) {
    try {
      Logger.i("Bluetooth", "Agent RequestPinCode");
      ToastService.showWarning(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.pincode-required"));
    } catch (e) {
      Logger.w("Bluetooth", "Agent RequestPinCode handler error", e);
    } finally {
      reject();
    }
  }

  onDisplayPasskey: function(device, passkey) {
    try {
      Logger.i("Bluetooth", "Agent DisplayPasskey", passkey);
      ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.display-code", { value: passkey }), "bluetooth");
    } catch (e) {
      Logger.w("Bluetooth", "Agent DisplayPasskey handler error", e);
    }
  }

  onAuthorizeService: function(device, uuid, accept, reject) {
    Logger.d("Bluetooth", "Agent AuthorizeService", uuid);
    accept();
  }

  onCancel: function() {
    Logger.d("Bluetooth", "Agent request canceled");
  }
}
`;

      btAgent = Qt.createQmlObject(qml, root, "DynamicBluetoothAgent");
      // Attempt to register the agent from the outer scope so we can
      // trigger a fallback if registration fails at runtime.
      try {
        Bluetooth.agent = btAgent;
        if (btAgent.register)
        btAgent.register();
        Logger.i("Bluetooth", "BluetoothAgent registered (dynamic)");
        btAgentRegistered = true;
      } catch (regErr) {
        Logger.w("Bluetooth", "Failed to register BluetoothAgent (dynamic)", regErr);
        btAgentRegistered = false;
        startFallbackAgent();
      }
    } catch (e) {
      Logger.i("Bluetooth", "BluetoothAgent type appears unavailable; starting fallback agent");
      btAgentRegistered = false;
      startFallbackAgent();
    }
  }

  // External fallback agent process (bt-agent or bluetoothctl)
  Process {
    id: fallbackBluetoothctlAgent
    // Prefer bt-agent (if available). Otherwise, fall back to bluetoothctl
    // and register as the default agent, keeping the session alive.
    command: ["sh", "-c", "(pkill -f '^bt-agent( |$)' 2>/dev/null || true; pkill -f '^bluetoothctl( |$)' 2>/dev/null || true; " + "if command -v bt-agent >/dev/null 2>&1; then exec bt-agent -c DisplayYesNo; " + "else (printf 'agent off\nagent on\nagent KeyboardDisplay\ndefault-agent\n'; while sleep 3600; do :; done) | bluetoothctl; fi)"]
    running: false
    stdout: StdioCollector {}
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Bluetooth", "bluetoothctl agent stderr:", text.trim());
        }
      }
    }
  }

  Timer {
    id: discoveryTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (adapter)
      adapter.discovering = true;
    }
  }

  Connections {
    target: adapter
    function onStateChanged() {
      if (!adapter) {
        Logger.w("Bluetooth", "onStateChanged", "No adapter available");
        return;
      }
      if (adapter.state === BluetoothAdapterState.Enabling || adapter.state === BluetoothAdapterState.Disabling) {
        return;
      }

      Logger.d("Bluetooth", "onStateChanged", adapter.state);
      const bluetoothBlockedToggled = (root.blocked !== lastBluetoothBlocked);
      root.lastBluetoothBlocked = root.blocked;
      if (bluetoothBlockedToggled) {
        checkWifiBlocked.running = true;
      } else if (adapter.state === BluetoothAdapterState.Enabled) {
        ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.enabled"), "bluetooth");
        discoveryTimer.running = true;
      } else if (adapter.state === BluetoothAdapterState.Disabled) {
        ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.disabled"), "bluetooth-off");
      }
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

    var name = (device.name || device.deviceName || "").toLowerCase();
    var icon = (device.icon || "").toLowerCase();
    if (icon.indexOf("controller") !== -1 || icon.indexOf("gamepad") !== -1 || name.indexOf("controller") !== -1 || name.indexOf("gamepad") !== -1) {
      return "bt-device-gamepad";
    }
    if (icon.indexOf("microphone") !== -1 || name.indexOf("microphone") !== -1) {
      return "bt-device-microphone";
    }
    if (name.indexOf("pod") !== -1 || name.indexOf("bud") !== -1 || name.indexOf("minor") !== -1) {
      return "bt-device-earbuds";
    }
    if (icon.indexOf("headset") !== -1 || name.indexOf("arctis") !== -1 || name.indexOf("headset") !== -1 || name.indexOf("major") !== -1) {
      return "bt-device-headset";
    }
    if (icon.indexOf("headphone") !== -1 || name.indexOf("headphone") !== -1) {
      return "bt-device-headphones";
    }
    if (icon.indexOf("mouse") !== -1 || name.indexOf("mouse") !== -1) {
      return "bt-device-mouse";
    }
    if (icon.indexOf("keyboard") !== -1 || name.indexOf("keyboard") !== -1) {
      return "bt-device-keyboard";
    }
    if (icon.indexOf("watch") !== -1 || name.indexOf("watch") !== -1) {
      return "bt-device-watch";
    }
    if (icon.indexOf("speaker") !== -1 || name.indexOf("speaker") !== -1 || name.indexOf("audio") !== -1 || name.indexOf("sound") !== -1) {
      return "bt-device-speaker";
    }
    if (icon.indexOf("display") !== -1 || name.indexOf("tv") !== -1) {
      return "bt-device-tv";
    }
    if (icon.indexOf("phone") !== -1 || name.indexOf("phone") !== -1 || name.indexOf("iphone") !== -1 || name.indexOf("android") !== -1 || name.indexOf("samsung") !== -1) {
      return "bt-device-phone";
    }
    return "bt-device-generic";
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

  function getStatusString(device) {
    if (device.state === BluetoothDeviceState.Connecting) {
      return I18n.tr("bluetooth.panel.connecting");
    }
    if (device.pairing) {
      return I18n.tr("bluetooth.panel.pairing");
    }
    if (device.blocked) {
      return I18n.tr("bluetooth.panel.blocked");
    }
    return "";
  }

  function getSignalStrength(device) {
    if (!device || device.signalStrength === undefined || device.signalStrength <= 0) {
      return "Signal: Unknown";
    }
    var signal = device.signalStrength;
    if (signal >= 80) {
      return "Signal: Excellent";
    }
    if (signal >= 60) {
      return "Signal: Good";
    }
    if (signal >= 40) {
      return "Signal: Fair";
    }
    if (signal >= 20) {
      return "Signal: Poor";
    }
    return "Signal: Very poor";
  }

  function getBattery(device) {
    return "Battery: " + Math.round(device.battery * 100) + "%";
  }

  function getSignalIcon(device) {
    if (!device || device.signalStrength === undefined || device.signalStrength <= 0) {
      return "antenna-bars-off";
    }
    var signal = device.signalStrength;
    if (signal >= 80) {
      return "antenna-bars-5";
    }
    if (signal >= 60) {
      return "antenna-bars-4";
    }
    if (signal >= 40) {
      return "antenna-bars-3";
    }
    if (signal >= 20) {
      return "antenna-bars-2";
    }
    return "antenna-bars-1";
  }

  function isDeviceBusy(device) {
    if (!device) {
      return false;
    }

    return device.pairing || device.state === BluetoothDeviceState.Disconnecting || device.state === BluetoothDeviceState.Connecting;
  }

  // Return a stable unique key for a device (prefer MAC address)
  function deviceKey(device) {
    if (!device)
      return "";
    if (device.address && device.address.length > 0)
      return device.address.toUpperCase();
    if (device.nativePath && device.nativePath.length > 0)
      return device.nativePath;
    if (device.devicePath && device.devicePath.length > 0)
      return device.devicePath;
    return (device.name || device.deviceName || "") + "|" + (device.icon || "");
  }

  // Deduplicate a list of devices using the stable key
  function dedupeDevices(devList) {
    if (!devList || devList.length === 0)
      return [];
    const seen = ({});
    const out = [];
    for (let i = 0; i < devList.length; ++i) {
      const d = devList[i];
      if (!d)
        continue;
      const key = deviceKey(d);
      if (key && !seen[key]) {
        seen[key] = true;
        out.push(d);
      }
    }
    return out;
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
    try {
      // If the in-app agent is not registered/available, use bluetoothctl which manages its own agent
      if (!btAgentRegistered) {
        pairWithBluetoothctl(device);
        return;
      }
      if (typeof device.pair === 'function') {
        device.pair();
      } else {
        // Fallback: trust and connect (most stacks will pair during connect)
        device.trusted = true;
        device.connect();
      }
    } catch (e) {
      Logger.w("Bluetooth", "pairDevice failed", e);
      ToastService.showWarning(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.pair-failed"));
      // CLI fallback: use bluetoothctl to perform pairing with an internal agent
      // This mirrors the manual pairing flow that works for the user.
      try {
        pairWithBluetoothctl(device);
      } catch (e3) {
        Logger.w("Bluetooth", "pairWithBluetoothctl failed", e3);
        // Fallback to connect if pair not supported
        try {
          device.trusted = true;
          device.connect();
        } catch (e2) {
          Logger.w("Bluetooth", "pairDevice connect fallback failed", e2);
          ToastService.showWarning(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.connect-failed"));
        }
      }
    }
  }

  // Pair using bluetoothctl which registers its own BlueZ agent internally.
  // Useful on systems where the QML BluetoothAgent type is unavailable.
  function pairWithBluetoothctl(device) {
    if (!device)
      return;
    var addr = "";
    try {
      if (device.address && device.address.length > 0) {
        addr = device.address;
      } else if (device.nativePath && device.nativePath.indexOf("/dev_") !== -1) {
        // Extract MAC from nativePath like /org/bluez/hci0/dev_XX_XX_...
        addr = device.nativePath.split("dev_")[1].replaceAll("_", ":");
      }
    } catch (_) {}
    if (!addr || addr.length < 7) {
      Logger.w("Bluetooth", "pairWithBluetoothctl: no valid address for device");
      return;
    }

    Logger.i("Bluetooth", "pairWithBluetoothctl", addr);
    const script = `(
      printf 'agent DisplayYesNo\n';
      printf 'default-agent\n';
      printf 'pair ${addr}\n';
      sleep 2;
      printf 'yes\n';
      printf 'trust ${addr}\n';
      sleep 1;
      printf 'connect ${addr}\n';
      printf 'quit\n';
    ) | bluetoothctl`;

    try {
      Quickshell.execDetached(["sh", "-c", script]);
    } catch (e) {
      Logger.w("Bluetooth", "execDetached bluetoothctl failed", e);
    }
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

  function setBluetoothEnabled(state) {
    if (!adapter) {
      Logger.w("Bluetooth", "No adapter available");
      return;
    }

    Logger.i("Bluetooth", "SetBluetoothEnabled", state);
    try {
      adapter.enabled = state;
    } catch (e) {
      Logger.w("Bluetooth", "Enable/Disable failed", e);
      ToastService.showWarning(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.state-change-failed"));
    }
  }

  // Toggle adapter discoverability (advertising visibility)
  function setDiscoverable(state) {
    if (!adapter) {
      Logger.w("Bluetooth", "setDiscoverable: No adapter available");
      return;
    }
    try {
      adapter.discoverable = state;
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

  Process {
    id: checkWifiBlocked
    running: false
    command: ["rfkill", "list", "wifi"]

    stdout: StdioCollector {
      onStreamFinished: {
        var wifiBlocked = text && text.trim().indexOf("Soft blocked: yes") !== -1;
        Logger.d("Network", "Wi-Fi adapter was detected as blocked:", wifiBlocked);

        // Check if airplane mode has been toggled
        if (wifiBlocked && wifiBlocked === root.blocked) {
          root.airplaneModeToggled = true;
          NetworkService.setWifiEnabled(false);
          ToastService.showNotice(I18n.tr("toast.airplane-mode.title"), I18n.tr("toast.airplane-mode.enabled"), "plane");
        } else if (!wifiBlocked && wifiBlocked === root.blocked) {
          root.airplaneModeToggled = true;
          NetworkService.setWifiEnabled(true);
          ToastService.showNotice(I18n.tr("toast.airplane-mode.title"), I18n.tr("toast.airplane-mode.disabled"), "plane-off");
        } else if (adapter.enabled) {
          ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.enabled"), "bluetooth");
          discoveryTimer.running = true;
        } else {
          ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.disabled"), "bluetooth-off");
        }
        root.airplaneModeToggled = false;
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Bluetooth", "rfkill (wifi) stderr:", text.trim());
        }
      }
    }
  }
}
