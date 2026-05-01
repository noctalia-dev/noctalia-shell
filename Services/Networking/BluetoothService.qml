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
  property var _deviceCodecSelections: ({})
  property var _deviceCodecOptions: ({})
  property var _deviceActiveCodecProfile: ({})
  property var _deviceCodecProfileIndices: ({})
  property var _deviceCodecBackendMeta: ({})
  property var _codecSetRequestedKey: ({})
  property var _codecSetPendingUntil: ({})
  property var _codecQueryPending: ({})
  property var _codecQueryQueue: []
  property string _codecQueryCurrentAddr: ""
  property string _codecSetCurrentAddr: ""
  property bool _codecBackendAvailable: true

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

  // Handle potential case where Quickshell doesnt't properly update adapter after system wakeup
  Connections {
    target: Time
    function onResumed() {
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
      if (adapter?.enabled && Settings.data.network.bluetoothAutoConnect) {
        autoConnectTimer.restart();
      }
    }
  }

  Connections {
    target: Settings.data.network
    function onBluetoothAutoConnectChanged() {
      if (Settings.data.network.bluetoothAutoConnect && adapter?.enabled) {
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
    interval: 2000
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

  function codecOptions(device) {
    if (!device) {
      return [];
    }
    var addr = BluetoothUtils.macFromDevice(device);
    if (!addr || !_deviceCodecOptions[addr]) {
      return [];
    }
    return _deviceCodecOptions[addr];
  }

  function _profileLabel(profileKey, description) {
    var p = String(profileKey || "").toLowerCase();
    var d = String(description || "").toLowerCase();
    var dm = d.match(/codec\s+([a-z0-9+\-]+)/i);
    if (dm && dm[1]) {
      var codec = dm[1].toLowerCase();
      if (codec === "ldac")
        return "LDAC";
      if (codec === "aac")
        return "AAC";
      if (codec === "sbc")
        return "SBC";
      if (codec === "aptx-hd" || codec === "aptx_hd")
        return "aptX HD";
      if (codec === "aptx")
        return "aptX";
      if (codec === "lc3")
        return "LC3";
      if (codec === "msbc" || codec === "m_sbc")
        return "mSBC";
      if (codec === "cvsd")
        return "CVSD";
      return codec.toUpperCase();
    }

    if (p.indexOf("ldac") !== -1)
      return "LDAC";
    if (p.indexOf("aptx_hd") !== -1 || p.indexOf("aptx-hd") !== -1)
      return "aptX HD";
    if (p.indexOf("aptx") !== -1)
      return "aptX";
    if (p.indexOf("aac") !== -1)
      return "AAC";
    if (p.indexOf("sbc") !== -1)
      return "SBC";
    if (p.indexOf("lc3") !== -1)
      return "LC3";
    if (p.indexOf("msbc") !== -1 || p.indexOf("m_sbc") !== -1)
      return "mSBC";
    if (p.indexOf("cvsd") !== -1)
      return "CVSD";
    return String(profileKey || "").replace(/[_-]/g, " ");
  }

  function _parseCodecQueryOutput(text) {
    var lines = String(text || "").split(/\r?\n/);
    var active = "";
    var profiles = [];
    var seen = ({});
    var profileIndexMap = ({});
    var backend = "";
    var target = "";

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (!line)
        continue;
      if (line.indexOf("ACTIVE=") === 0) {
        active = line.slice(7).trim();
        continue;
      }
      if (line.indexOf("BACKEND=") === 0) {
        backend = line.slice(8).trim();
        continue;
      }
      if (line.indexOf("TARGET=") === 0) {
        target = line.slice(7).trim();
        continue;
      }
      if (line.indexOf("PROFILE_IDX=") === 0) {
        var payload = line.slice(12);
        var parts = payload.split("|");
        if (parts.length >= 2) {
          var idx = Number(parts[0]);
          var pkey = parts[1];
          if (!isNaN(idx) && pkey) {
            profileIndexMap[pkey] = idx;
          }
        }
        continue;
      }
      if (line.indexOf("PROFILE=") !== 0)
        continue;
      var p = line.slice(8).trim();
      if (!p || seen[p])
        continue;
      seen[p] = true;
      if (p === "off")
        continue;
      var lower = p.toLowerCase();
      var isBtAudioProfile = lower.indexOf("a2dp") !== -1 || lower.indexOf("headset") !== -1 || lower.indexOf("handsfree") !== -1 || lower.indexOf("hfp") !== -1 || lower.indexOf("hsp") !== -1;
      if (!isBtAudioProfile)
        continue;
      profiles.push({
                      "key": p,
                      "name": _profileLabel(p, "")
                    });
    }

    // Apply description-derived labels when PROFILE_IDX lines provided richer metadata.
    for (var k = 0; k < lines.length; k++) {
      var l = lines[k].trim();
      if (l.indexOf("PROFILE_IDX=") !== 0)
        continue;
      var payload2 = l.slice(12);
      var parts2 = payload2.split("|");
      if (parts2.length < 3)
        continue;
      var pkey2 = parts2[1];
      var pdesc2 = parts2.slice(2).join("|");
      for (var q = 0; q < profiles.length; q++) {
        if (profiles[q].key === pkey2) {
          profiles[q].name = _profileLabel(pkey2, pdesc2);
          break;
        }
      }
    }

    return {
      "active": active,
      "options": profiles,
      "profileIndexMap": profileIndexMap,
      "backend": backend,
      "target": target
    };
  }

  function _bluezCardToken(address) {
    return String(address || "").trim().toUpperCase().replace(/[:-]/g, "_");
  }

  function _runNextCodecQuery() {
    if (codecQueryProcess.running || _codecQueryQueue.length === 0) {
      return;
    }

    var addr = _codecQueryQueue.shift();
    var pending = Object.assign({}, _codecQueryPending);
    pending[addr] = true;
    _codecQueryPending = pending;
    _codecQueryCurrentAddr = addr;

    var cardToken = _bluezCardToken(addr);
    var script = "CARD_TOKEN='" + cardToken + "'; "
           + "ADDR='" + addr + "'; "
           + "if command -v pactl >/dev/null 2>&1; then "
           + "  CARD_NAME=$(pactl list cards short 2>/dev/null | awk -v tok=\"$CARD_TOKEN\" '$2 ~ \"bluez_card\\.\" tok {print $2; exit}'); "
           + "  if [ -n \"$CARD_NAME\" ]; then "
           + "    echo BACKEND=pactl; "
           + "    echo TARGET=$CARD_NAME; "
           + "    pactl list cards 2>/dev/null | awk -v card=\"$CARD_NAME\" '"
           + "$1==\"Name:\" {in_card=($2==card); in_profiles=0} "
           + "in_card && $1==\"Active\" && $2==\"Profile:\" {print \"ACTIVE=\" $3} "
           + "in_card && /^\\s*Profiles:/ {in_profiles=1; next} "
           + "in_card && in_profiles && /^\\s*Active Profile:/ {in_profiles=0} "
           + "in_card && in_profiles { if (match($0,/^[[:space:]]*([^:[:space:]]+):/,m)) { print \"PROFILE=\" m[1]; } }'; "
           + "    exit 0; "
           + "  fi; "
           + "fi; "
           + "command -v wpctl >/dev/null 2>&1 || exit 10; "
           + "command -v pw-cli >/dev/null 2>&1 || exit 10; "
               + "DEVICE_ID=$(pw-cli ls Device 2>/dev/null | awk -v tok=\"$CARD_TOKEN\" '/^[[:space:]]*id [0-9]+,/{id=$2; gsub(/,/,\"\",id)} /device.name = \"bluez_card\\./{ if (index($0, tok)>0) { print id; exit } }'); "
           + "[ -n \"$DEVICE_ID\" ] || exit 11; "
           + "echo BACKEND=wpctl; "
           + "echo TARGET=$DEVICE_ID; "
           + "ACTIVE=$(pw-cli enum-params \"$DEVICE_ID\" Profile 2>/dev/null | sed -n 's/.*String \"\\([^\"\\]*\\)\"/\\1/p' | head -n1); "
           + "[ -n \"$ACTIVE\" ] && echo ACTIVE=$ACTIVE; "
           + "pw-cli enum-params \"$DEVICE_ID\" EnumProfile 2>/dev/null | awk '"
           + "/Profile:index/ {need_idx=1; next} "
           + "need_idx && /Int / {idx=$2; need_idx=0; next} "
           + "/Profile:name/ {need_name=1; next} "
           + "need_name && /String / {name=$2; gsub(/\"/,\"\",name); need_name=0; next} "
           + "/Profile:description/ {need_desc=1; next} "
           + "need_desc && /String / {desc=$0; sub(/^.*String \"/,\"\",desc); sub(/\"$/,\"\",desc); need_desc=0; next} "
           + "/ParamAvailability:yes/ { if (name != \"\" && name != \"off\") { print \"PROFILE=\" name; print \"PROFILE_IDX=\" idx \"|\" name \"|\" desc; } idx=\"\"; name=\"\"; desc=\"\"; }'";

    codecQueryProcess.command = ["sh", "-c", script];
    codecQueryProcess.running = true;
  }

  function ensureCodecOptions(device) {
    if (!device || !device.connected || !isAudioDevice(device)) {
      return;
    }
    var addr = BluetoothUtils.macFromDevice(device);
    if (!addr) {
      return;
    }
    if (_deviceCodecOptions[addr] && _deviceCodecOptions[addr].length > 0) {
      return;
    }
    if (_codecQueryPending[addr]) {
      return;
    }
    if (_codecQueryQueue.indexOf(addr) === -1) {
      _codecQueryQueue = _codecQueryQueue.concat([addr]);
    }
    _runNextCodecQuery();
  }

  function isAudioDevice(device) {
    if (!device) {
      return false;
    }
    var iconName = String(device.icon || "").toLowerCase();
    var name = String(device.name || device.deviceName || "").toLowerCase();
    return iconName.indexOf("audio") !== -1 || iconName.indexOf("head") !== -1 || iconName.indexOf("speaker") !== -1 || iconName.indexOf("headset") !== -1 || iconName.indexOf("handsfree") !== -1 || name.indexOf("head") !== -1 || name.indexOf("speaker") !== -1 || name.indexOf("earbud") !== -1;
  }

  function getSelectedCodecKey(device) {
    if (!device) {
      return "";
    }
    var addr = BluetoothUtils.macFromDevice(device);
    if (!addr) {
      return "";
    }

    var pendingUntil = _codecSetPendingUntil[addr] || 0;
    if (pendingUntil > Date.now() && _codecSetRequestedKey[addr]) {
      return _codecSetRequestedKey[addr];
    }

    if (_deviceActiveCodecProfile[addr]) {
      return _deviceActiveCodecProfile[addr];
    }
    if (!_deviceCodecSelections[addr]) {
      return "";
    }
    return _deviceCodecSelections[addr];
  }

  function isCodecSwitchBusy(device) {
    if (!device) {
      return false;
    }
    var addr = BluetoothUtils.macFromDevice(device);
    if (!addr) {
      return false;
    }
    if (codecSetProcess.running && _codecSetCurrentAddr === addr) {
      return true;
    }
    var pendingUntil = _codecSetPendingUntil[addr] || 0;
    return pendingUntil > Date.now();
  }

  function setCodecForDevice(device, key) {
    if (!device) {
      return;
    }

    var valid = false;
    var opts = codecOptions(device);
    for (var i = 0; i < opts.length; i++) {
      if (opts[i].key === key) {
        valid = true;
        break;
      }
    }
    if (!valid) {
      return;
    }

    var addr = BluetoothUtils.macFromDevice(device);
    if (!addr) {
      return;
    }
    if (codecSetProcess.running && _codecSetCurrentAddr === addr) {
      return;
    }
    if (getSelectedCodecKey(device) === key) {
      return;
    }
    if (addr) {
      var selections = Object.assign({}, _deviceCodecSelections);
      selections[addr] = key;
      _deviceCodecSelections = selections;

      // Optimistic update keeps the combo selection stable until backend confirms.
      var activeMap = Object.assign({}, _deviceActiveCodecProfile);
      activeMap[addr] = key;
      _deviceActiveCodecProfile = activeMap;

      var requestedMap = Object.assign({}, _codecSetRequestedKey);
      requestedMap[addr] = key;
      _codecSetRequestedKey = requestedMap;

      var pendingMap = Object.assign({}, _codecSetPendingUntil);
      pendingMap[addr] = Date.now() + 7000;
      _codecSetPendingUntil = pendingMap;
    }

    var backendMeta = _deviceCodecBackendMeta[addr] || ({});
    var backend = backendMeta.backend || "";
    var target = backendMeta.target || "";
    var idxMap = _deviceCodecProfileIndices[addr] || ({});

    if (backend === "wpctl") {
      var profileIndex = idxMap[key];
      if (profileIndex === undefined || profileIndex === null) {
        ToastService.showWarning(I18n.tr("common.bluetooth"), I18n.tr("toast.bluetooth.codec-apply-failed"));
        return;
      }
      codecSetProcess.command = ["wpctl", "set-profile", String(target), String(profileIndex)];
    } else if (backend === "pactl") {
      codecSetProcess.command = ["pactl", "set-card-profile", String(target), String(key)];
    } else {
      ToastService.showWarning(I18n.tr("common.bluetooth"), I18n.tr("toast.bluetooth.codec-selector-unavailable"));
      return;
    }

    _codecSetCurrentAddr = addr;
    codecSetProcess.running = true;
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

  Process {
    id: codecQueryProcess
    running: false

    onExited: function (code) {
      var addr = root._codecQueryCurrentAddr;
      root._codecQueryCurrentAddr = "";

      var pending = Object.assign({}, root._codecQueryPending);
      delete pending[addr];
      root._codecQueryPending = pending;

      if (code === 0 && addr) {
        var parsed = root._parseCodecQueryOutput(stdout.text);

        var optionsMap = Object.assign({}, root._deviceCodecOptions);
        optionsMap[addr] = parsed.options;
        root._deviceCodecOptions = optionsMap;

        var profileIndexMaps = Object.assign({}, root._deviceCodecProfileIndices);
        profileIndexMaps[addr] = parsed.profileIndexMap;
        root._deviceCodecProfileIndices = profileIndexMaps;

        var requested = root._codecSetRequestedKey[addr] || "";
        var pendingUntilNow = root._codecSetPendingUntil[addr] || 0;
        var stillPending = pendingUntilNow > Date.now();
        if (!stillPending || !requested || parsed.active === requested) {
          var activeMap = Object.assign({}, root._deviceActiveCodecProfile);
          activeMap[addr] = parsed.active;
          root._deviceActiveCodecProfile = activeMap;
        }

        if (requested && parsed.active === requested) {
          var pendingMap2 = Object.assign({}, root._codecSetPendingUntil);
          delete pendingMap2[addr];
          root._codecSetPendingUntil = pendingMap2;

          var requestedMap2 = Object.assign({}, root._codecSetRequestedKey);
          delete requestedMap2[addr];
          root._codecSetRequestedKey = requestedMap2;
        }

        var backendMetaMap = Object.assign({}, root._deviceCodecBackendMeta);
        backendMetaMap[addr] = {
          "backend": parsed.backend,
          "target": parsed.target
        };
        root._deviceCodecBackendMeta = backendMetaMap;

        root._codecBackendAvailable = true;
      } else if (code === 10) {
        root._codecBackendAvailable = false;
      }

      root._runNextCodecQuery();
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  Process {
    id: codecSetProcess
    running: false

    onExited: function (code) {
      var addr = root._codecSetCurrentAddr;
      root._codecSetCurrentAddr = "";

      if (code !== 0) {
        if (addr) {
          var pendingMap = Object.assign({}, root._codecSetPendingUntil);
          delete pendingMap[addr];
          root._codecSetPendingUntil = pendingMap;

          var requestedMap = Object.assign({}, root._codecSetRequestedKey);
          delete requestedMap[addr];
          root._codecSetRequestedKey = requestedMap;
        }
        if (code === 10) {
          root._codecBackendAvailable = false;
        }
        ToastService.showWarning(I18n.tr("common.bluetooth"), I18n.tr("toast.bluetooth.codec-apply-failed"));
        return;
      }
      root._codecBackendAvailable = true;
      // Re-query after profile change so active codec and available list remain accurate.
      if (addr && root._codecQueryQueue.indexOf(addr) === -1) {
        root._codecQueryQueue = root._codecQueryQueue.concat([addr]);
      }
      root._runNextCodecQuery();
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
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
