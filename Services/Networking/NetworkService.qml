pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.System
import qs.Services.UI

Singleton {
  id: root

  // Core state
  property var networks: ({})
  property bool scanning: false
  property bool connecting: false
  property string connectingTo: ""
  property string lastError: ""
  property bool ethernetConnected: false
  property string disconnectingFrom: ""
  property string forgettingNetwork: ""
  property string networkConnectivity: "unknown"
  property bool internetConnectivity: true
  property bool ignoreScanResults: false
  property bool scanPending: false

  // Active Wi‑Fi connection details (for info panel)
  property var activeWifiDetails: ({})
  property string activeWifiIf: ""
  property bool detailsLoading: false
  property double activeWifiDetailsTimestamp: 0
  // Cache TTL to avoid spamming nmcli/iw on rapid toggles
  property int activeWifiDetailsTtlMs: 5000

  // Persistent cache
  property string cacheFile: Settings.cacheDir + "network.json"
  readonly property string cachedLastConnected: cacheAdapter.lastConnected
  readonly property var cachedNetworks: cacheAdapter.knownNetworks

  // Cache file handling
  FileView {
    id: cacheFileView
    path: root.cacheFile
    printErrors: false

    JsonAdapter {
      id: cacheAdapter
      property var knownNetworks: ({})
      property string lastConnected: ""
    }

    onLoadFailed: {
      cacheAdapter.knownNetworks = ({});
      cacheAdapter.lastConnected = "";
    }
  }

  Connections {
    target: Settings.data.network
    function onWifiEnabledChanged() {
      if (Settings.data.network.wifiEnabled) {
        if (!BluetoothService.airplaneModeToggled) {
          ToastService.showNotice(I18n.tr("wifi.panel.title"), I18n.tr("toast.wifi.enabled"), "wifi");
        }
        // Perform a scan to update the UI
        delayedScanTimer.interval = 3000;
        delayedScanTimer.restart();
      } else {
        if (!BluetoothService.airplaneModeToggled) {
          ToastService.showNotice(I18n.tr("wifi.panel.title"), I18n.tr("toast.wifi.disabled"), "wifi-off");
        }
        // Clear networks so the widget icon changes
        root.networks = ({});
      }
    }
  }

  Component.onCompleted: {
    Logger.i("Network", "Service started");
    if (ProgramCheckerService.nmcliAvailable) {
      syncWifiState();
      scan();
      refreshActiveWifiDetails();
    }
  }

  // Start initial checks when nmcli becomes available
  Connections {
    target: ProgramCheckerService
    function onNmcliAvailableChanged() {
      if (ProgramCheckerService.nmcliAvailable) {
        syncWifiState();
        scan();
      }
    }
  }

  // Save cache with debounce
  Timer {
    id: saveDebounce
    interval: 1000
    onTriggered: cacheFileView.writeAdapter()
  }

  // Refresh details for the currently active Wi‑Fi link
  function refreshActiveWifiDetails() {
    const now = Date.now();
    // If we're already fetching, don't start a new one
    if (detailsLoading)
      return;

    // Use cached details if they are fresh
    if (activeWifiIf && activeWifiDetails && (now - activeWifiDetailsTimestamp) < activeWifiDetailsTtlMs)
      return;

    detailsLoading = true;
    wifiDeviceListProcess.running = true;
  }

  function saveCache() {
    saveDebounce.restart();
  }

  // Delayed scan timer
  Timer {
    id: delayedScanTimer
    interval: 7000
    onTriggered: scan()
  }

  // Ethernet check timer
  // Runs every 30s if nmcli is available
  Timer {
    id: ethernetCheckTimer
    interval: 30000
    running: ProgramCheckerService.nmcliAvailable
    repeat: true
    onTriggered: ethernetStateProcess.running = true
  }

  // Internet connectivity check timer
  // Runs every 15s if nmcli is available
  Timer {
    id: connectivityCheckTimer
    interval: 15000
    running: ProgramCheckerService.nmcliAvailable
    repeat: true
    onTriggered: connectivityCheckProcess.running = true
  }

  // Core functions
  function syncWifiState() {
    if (!ProgramCheckerService.nmcliAvailable)
      return;
    wifiStateProcess.running = true;
  }

  function setWifiEnabled(enabled) {
    if (!ProgramCheckerService.nmcliAvailable)
      return;
    Settings.data.network.wifiEnabled = enabled;
    wifiStateEnableProcess.running = true;
  }

  function scan() {
    if (!ProgramCheckerService.nmcliAvailable || !Settings.data.network.wifiEnabled)
      return;
    if (scanning) {
      // Mark current scan results to be ignored and schedule a new scan
      Logger.d("Network", "Scan already in progress, will ignore results and rescan");
      ignoreScanResults = true;
      scanPending = true;
      return;
    }

    scanning = true;
    lastError = "";
    ignoreScanResults = false;

    // Get existing profiles first, then scan
    profileCheckProcess.running = true;
    Logger.d("Network", "Wi-Fi scan in progress...");
  }

  function connect(ssid, password = "") {
    if (!ProgramCheckerService.nmcliAvailable || connecting)
      return;
    connecting = true;
    connectingTo = ssid;
    lastError = "";

    // Check if we have a saved connection
    if ((networks[ssid] && networks[ssid].existing) || cachedNetworks[ssid]) {
      connectProcess.mode = "saved";
      connectProcess.ssid = ssid;
      connectProcess.password = "";
    } else {
      connectProcess.mode = "new";
      connectProcess.ssid = ssid;
      connectProcess.password = password;
    }

    connectProcess.running = true;
  }

  function disconnect(ssid) {
    if (!ProgramCheckerService.nmcliAvailable)
      return;
    disconnectingFrom = ssid;
    disconnectProcess.ssid = ssid;
    disconnectProcess.running = true;
  }

  function forget(ssid) {
    if (!ProgramCheckerService.nmcliAvailable)
      return;
    forgettingNetwork = ssid;

    // Remove from cache
    let known = cacheAdapter.knownNetworks;
    delete known[ssid];
    cacheAdapter.knownNetworks = known;

    if (cacheAdapter.lastConnected === ssid) {
      cacheAdapter.lastConnected = "";
    }

    saveCache();

    // Remove from system
    forgetProcess.ssid = ssid;
    forgetProcess.running = true;
  }

  // Helper function to immediately update network status
  function updateNetworkStatus(ssid, connected) {
    let nets = networks;

    // Update all networks connected status
    for (let key in nets) {
      if (nets[key].connected && key !== ssid) {
        nets[key].connected = false;
      }
    }

    // Update the target network if it exists
    if (nets[ssid]) {
      nets[ssid].connected = connected;
      nets[ssid].existing = true;
      nets[ssid].cached = true;
    } else if (connected) {
      // Create a temporary entry if network doesn't exist yet
      nets[ssid] = {
        "ssid": ssid,
        "security": "--",
        "signal": 100,
        "connected": true,
        "existing": true,
        "cached": true
      };
    }

    // Trigger property change notification
    networks = ({});
    networks = nets;
  }

  // Helper functions
  function signalIcon(signal, isConnected) {
    if (isConnected === undefined)
      isConnected = false;
    if (isConnected && !root.internetConnectivity)
      return "world-off";
    if (signal >= 80)
      return "wifi";
    if (signal >= 50)
      return "wifi-2";
    if (signal >= 20)
      return "wifi-1";
    return "wifi-0";
  }

  function isSecured(security) {
    return security && security !== "--" && security.trim() !== "";
  }

  function getSignalStrengthLabel(signal) {
    switch (true) {
    case (signal >= 80):
      return I18n.tr("wifi.signal.excellent");
    case (signal >= 50):
      return I18n.tr("wifi.signal.good");
    case (signal >= 20):
      return I18n.tr("wifi.signal.fair");
    default:
      return I18n.tr("wifi.signal.poor");
    }
  }

  // Processes
  Process {
    id: ethernetStateProcess
    running: ProgramCheckerService.nmcliAvailable
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device"]

    stdout: StdioCollector {
      onStreamFinished: {
        var connected = false;
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split(":");
          if (parts.length >= 3 && parts[1] === "ethernet" && parts[2] === "connected") {
            connected = true;
            break;
          }
        }
        if (root.ethernetConnected !== connected) {
          root.ethernetConnected = connected;
          Logger.d("Network", "Ethernet connected:", root.ethernetConnected);
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Network", "ethernetState nmcli stderr:", text.trim());
        }
      }
    }
  }

  // Discover connected Wi‑Fi interface
  Process {
    id: wifiDeviceListProcess
    running: false
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device"]

    stdout: StdioCollector {
      onStreamFinished: {
        let ifname = "";
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
          const parts = lines[i].trim().split(":");
          if (parts.length >= 3) {
            const dev = parts[0];
            const type = parts[1];
            const state = parts[2];
            if (type === "wifi" && state === "connected") {
              ifname = dev;
              break;
            }
          }
        }
        root.activeWifiIf = ifname;
        if (ifname) {
          wifiDeviceShowProcess.ifname = ifname;
          wifiDeviceShowProcess.running = true;
        } else {
          // Nothing to fetch
          root.activeWifiDetailsTimestamp = Date.now();
          root.detailsLoading = false;
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Network", "nmcli device list stderr:", text.trim());
        }
        // Fail-safe to avoid spinner
        if (!root.activeWifiIf) {
          root.activeWifiDetailsTimestamp = Date.now();
          root.detailsLoading = false;
        }
      }
    }
  }

  // Fetch IPv4 and gateway for the interface
  Process {
    id: wifiDeviceShowProcess
    property string ifname: ""
    running: false
    command: ["nmcli", "-t", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show", ifname]

    stdout: StdioCollector {
      onStreamFinished: {
        const details = root.activeWifiDetails || ({});
        let ipv4 = "";
        let gw4 = "";
        let dnsServers = [];
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i].trim();
          if (!line)
          continue;
          const idx = line.indexOf(":");
          if (idx === -1)
          continue;
          const key = line.substring(0, idx);
          const val = line.substring(idx + 1);
          if (key.indexOf("IP4.ADDRESS") === 0) {
            ipv4 = val.split("/")[0];
          } else if (key === "IP4.GATEWAY") {
            gw4 = val;
          } else if (key.indexOf("IP4.DNS") === 0) {
            if (val && dnsServers.indexOf(val) === -1) {
              dnsServers.push(val);
            }
          }
        }
        details.ipv4 = ipv4;
        details.gateway4 = gw4;
        details.dnsServers = dnsServers;
        details.dns = dnsServers.join(", ");
        root.activeWifiDetails = details;

        // Try to get link rate (best effort)
        wifiIwLinkProcess.ifname = wifiDeviceShowProcess.ifname;
        wifiIwLinkProcess.running = true;
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Network", "nmcli device show stderr:", text.trim());
        }
        // Still proceed to finalize details to avoid UI waiting forever
        root.activeWifiDetailsTimestamp = Date.now();
      }
    }
  }

  // Optional: query Wi‑Fi bitrate via iw if available
  Process {
    id: wifiIwLinkProcess
    property string ifname: ""
    running: false
    command: ["sh", "-c", "iw dev '" + ifname + "' link 2>/dev/null || true"]

    stdout: StdioCollector {
      onStreamFinished: {
        const details = root.activeWifiDetails || ({});
        let rate = "";
        let freq = "";
        const lines = text.split("\n");
        for (var k = 0; k < lines.length; k++) {
          var line2 = lines[k].trim();
          var low = line2.toLowerCase();
          if (low.indexOf("tx bitrate:") === 0) {
            rate = line2.substring(11).trim();
          } else if (low.indexOf("freq:") === 0) {
            freq = line2.substring(5).trim();
          }
        }

        // Determine band from frequency
        // https://en.wikipedia.org/wiki/List_of_WLAN_channels
        let band = "";
        if (freq) {
          const f = +freq;
          if (f) {
            switch (true) {
              // https://en.wikipedia.org/wiki/List_of_WLAN_channels#6_GHz_(802.11ax_and_802.11be)
              case (f >= 5925 && f < 7125):
              band = "6 GHz";
              break;
              // https://en.wikipedia.org/wiki/List_of_WLAN_channels#5_GHz_(802.11a/h/n/ac/ax/be)
              case (f >= 5150 && f < 5925):
              band = "5 GHz";
              break;
              // https://en.wikipedia.org/wiki/List_of_WLAN_channels#2.4_GHz_(802.11b/g/n/ax/be)
              case (f >= 2400 && f < 2500):
              band = "2.4 GHz";
              break;
              default:
              band = `${f} MHz`;
            }
          }
        }

        // Shorten verbose bitrate strings like: "360.0 MBit/s VHT-MCS 8 40MHz short GI"
        let rateShort = "";
        if (rate) {
          var parts = rate.trim().split(" ");
          // compact consecutive spaces
          var compact = [];
          for (var i = 0; i < parts.length; i++) {
            var p = parts[i];
            if (p && p.length > 0)
            compact.push(p);
          }
          // Find a token that represents Mbit/s and use the previous number
          var unitIdx = -1;
          for (var j = 0; j < compact.length; j++) {
            var token = compact[j].toLowerCase();
            if (token === "mbit/s" || token === "mb/s" || token === "mbits/s") {
              unitIdx = j;
              break;
            }
          }
          if (unitIdx > 0) {
            var num = compact[unitIdx - 1];
            // Basic numeric check
            var parsed = parseFloat(num);
            if (!isNaN(parsed)) {
              rateShort = parsed + " Mbit/s";
            }
          }
          if (!rateShort) {
            // Fallback to first two tokens
            rateShort = compact.slice(0, 2).join(" ");
          }
        }
        details.rate = rate;
        details.rateShort = rateShort;
        details.band = band;
        root.activeWifiDetails = details;
        root.activeWifiDetailsTimestamp = Date.now();
        root.detailsLoading = false;
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Network", "iw link stderr:", text.trim());
        }
        root.activeWifiDetailsTimestamp = Date.now();
        root.detailsLoading = false;
      }
    }
  }

  // Only check the state of the actual interface
  // and update our setting to be in sync.
  Process {
    id: wifiStateProcess
    running: false
    command: ["nmcli", "radio", "wifi"]

    stdout: StdioCollector {
      onStreamFinished: {
        const enabled = text.trim() === "enabled";
        Logger.d("Network", "Wi-Fi adapter was detect as enabled:", enabled);
        if (Settings.data.network.wifiEnabled !== enabled) {
          Settings.data.network.wifiEnabled = enabled;
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Network", "Wi-Fi state query stderr:", text.trim());
        }
      }
    }
  }

  // Process to enable/disable the Wi-Fi interface
  Process {
    id: wifiStateEnableProcess
    running: false
    command: ["nmcli", "radio", "wifi", Settings.data.network.wifiEnabled ? "on" : "off"]

    stdout: StdioCollector {
      onStreamFinished: {
        Logger.i("Network", "Wi-Fi state change command executed.");
        // Re-check the state to ensure it's in sync
        syncWifiState();
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.w("Network", "Error changing Wi-Fi state: " + text);
        }
      }
    }
  }

  // Process to check the internet connectivity of the connected network
  Process {
    id: connectivityCheckProcess
    running: false
    command: ["nmcli", "networking", "connectivity", "check"]

    property int failedChecks: 0

    stdout: StdioCollector {
      onStreamFinished: {
        const result = text.trim();
        if (!result) {
          return;
        }

        if (result === "none" && root.networkConnectivity !== result) {
          root.networkConnectivity = result;
          connectivityCheckProcess.failedChecks = 0;
          root.scan();
        }

        if (result === "full" && root.networkConnectivity !== result) {
          root.networkConnectivity = result;
          root.internetConnectivity = true;
          connectivityCheckProcess.failedChecks = 0;
          root.scan();
        }

        if ((result === "limited" || result === "portal") && root.networkConnectivity !== result) {
          connectivityCheckProcess.failedChecks++;
          if (connectivityCheckProcess.failedChecks === 3) {
            root.networkConnectivity = result;
            pingCheckProcess.running = true;
          }
        }

        if (result === "unknown" && root.networkConnectivity !== result) {
          root.networkConnectivity = result;
          connectivityCheckProcess.failedChecks = 0;
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.w("Network", "Connectivity check error: " + text);
        }
      }
    }
  }

  Process {
    id: pingCheckProcess
    command: ["sh", "-c", "ping -c1 -W2 ping.archlinux.org >/dev/null 2>&1 || " + "ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || " + "curl -fsI --max-time 5 https://cloudflare.com/cdn-cgi/trace >/dev/null 2>&1"]

    onExited: function (exitCode, exitStatus) {
      if (exitCode === 0) {
        connectivityCheckProcess.failedChecks = 0;
      } else {
        root.internetConnectivity = false;
        Logger.i("Network", "No internet connectivity");
        ToastService.showWarning(root.cachedLastConnected, I18n.tr("toast.internet.limited"));
        connectivityCheckProcess.failedChecks = 0;
      }
      root.scan();
    }
  }

  // Helper process to get existing profiles
  Process {
    id: profileCheckProcess
    running: false
    command: ["nmcli", "-t", "-f", "NAME", "connection", "show"]

    stdout: StdioCollector {
      onStreamFinished: {
        if (root.ignoreScanResults) {
          Logger.d("Network", "Ignoring profile check results (new scan requested)");
          root.scanning = false;

          // Check if we need to start a new scan
          if (root.scanPending) {
            root.scanPending = false;
            delayedScanTimer.interval = 100;
            delayedScanTimer.restart();
          }
          return;
        }

        var profiles = {};
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
          var l = lines[i];
          if (l && l.trim()) {
            profiles[l.trim()] = true;
          }
        }
        scanProcess.existingProfiles = profiles;
        scanProcess.running = true;
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Network", "Profile check stderr:", text.trim());
          // Fail safe - only restart scan on actual error
          if (root.scanning) {
            root.scanning = false;
            delayedScanTimer.interval = 5000;
            delayedScanTimer.restart();
          }
        }
      }
    }
  }

  Process {
    id: scanProcess
    running: false
    command: ["nmcli", "-t", "-f", "SSID,SECURITY,SIGNAL,IN-USE", "device", "wifi", "list", "--rescan", "yes"]

    property var existingProfiles: ({})

    stdout: StdioCollector {
      onStreamFinished: {
        if (root.ignoreScanResults) {
          Logger.d("Network", "Ignoring scan results (new scan requested)");
          root.scanning = false;

          // Check if we need to start a new scan
          if (root.scanPending) {
            root.scanPending = false;
            delayedScanTimer.interval = 100;
            delayedScanTimer.restart();
          }
          return;
        }

        // Process the scan results as before...
        const lines = text.split("\n");
        const networksMap = {};

        for (var i = 0; i < lines.length; ++i) {
          const line = lines[i].trim();
          if (!line)
          continue;

          // Parse from the end to handle SSIDs with colons
          // Format is SSID:SECURITY:SIGNAL:IN-USE
          // We know the last 3 fields, so everything else is SSID
          const lastColonIdx = line.lastIndexOf(":");
          if (lastColonIdx === -1) {
            Logger.w("Network", "Malformed nmcli output line:", line);
            continue;
          }

          const inUse = line.substring(lastColonIdx + 1);
          const remainingLine = line.substring(0, lastColonIdx);

          const secondLastColonIdx = remainingLine.lastIndexOf(":");
          if (secondLastColonIdx === -1) {
            Logger.w("Network", "Malformed nmcli output line:", line);
            continue;
          }

          const signal = remainingLine.substring(secondLastColonIdx + 1);
          const remainingLine2 = remainingLine.substring(0, secondLastColonIdx);

          const thirdLastColonIdx = remainingLine2.lastIndexOf(":");
          if (thirdLastColonIdx === -1) {
            Logger.w("Network", "Malformed nmcli output line:", line);
            continue;
          }

          const security = remainingLine2.substring(thirdLastColonIdx + 1);
          const ssid = remainingLine2.substring(0, thirdLastColonIdx);

          if (ssid) {
            const signalInt = parseInt(signal) || 0;
            const connected = inUse === "*";

            // Track connected network in cache
            if (connected && cacheAdapter.lastConnected !== ssid) {
              cacheAdapter.lastConnected = ssid;
              saveCache();
            }

            if (!networksMap[ssid]) {
              networksMap[ssid] = {
                "ssid": ssid,
                "security": security || "--",
                "signal": signalInt,
                "connected": connected,
                "existing": ssid in scanProcess.existingProfiles,
                "cached": ssid in cacheAdapter.knownNetworks
              };
            } else {
              // Keep the best signal for duplicate SSIDs
              const existingNet = networksMap[ssid];
              if (connected) {
                existingNet.connected = true;
              }
              if (signalInt > existingNet.signal) {
                existingNet.signal = signalInt;
                existingNet.security = security || "--";
              }
            }
          }
        }

        // Logging
        const oldSSIDs = Object.keys(root.networks);
        const newSSIDs = Object.keys(networksMap);
        const newNetworks = newSSIDs.filter(function (ssid) {
          return oldSSIDs.indexOf(ssid) === -1;
        });
        const lostNetworks = oldSSIDs.filter(function (ssid) {
          return newSSIDs.indexOf(ssid) === -1;
        });

        if (newNetworks.length > 0 || lostNetworks.length > 0) {
          if (newNetworks.length > 0) {
            Logger.d("Network", "New Wi-Fi SSID discovered:", newNetworks.join(", "));
          }
          if (lostNetworks.length > 0) {
            Logger.d("Network", "Wi-Fi SSID disappeared:", lostNetworks.join(", "));
          }
          Logger.d("Network", "Total Wi-Fi SSIDs:", Object.keys(networksMap).length);
        }

        Logger.d("Network", "Wi-Fi scan completed");
        root.networks = networksMap;
        root.scanning = false;

        // Preload active Wi‑Fi details so Info panel shows instantly when opened
        // This is lightweight and guarded by detailsLoading + TTL.
        var hasConnected = false;
        for (var ssid in networksMap) {
          if (networksMap.hasOwnProperty(ssid)) {
            var net = networksMap[ssid];
            if (net && net.connected) {
              hasConnected = true;
              break;
            }
          }
        }
        if (hasConnected) {
          root.refreshActiveWifiDetails();
        }

        // Check if we need to start a new scan
        if (root.scanPending) {
          root.scanPending = false;
          delayedScanTimer.interval = 100;
          delayedScanTimer.restart();
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.scanning = false;
        if (text.trim()) {
          Logger.w("Network", "Scan error: " + text);

          // If scan fails, retry
          delayedScanTimer.interval = 5000;
          delayedScanTimer.restart();
        }
      }
    }
  }
  Process {
    id: connectProcess
    property string mode: "new"
    property string ssid: ""
    property string password: ""
    running: false

    command: {
      if (mode === "saved") {
        return ["nmcli", "connection", "up", "id", ssid];
      } else {
        var cmd = ["nmcli", "device", "wifi", "connect", ssid];
        if (password) {
          cmd.push("password", password);
        }
        return cmd;
      }
    }
    environment: ({
                    "LC_ALL": "C"
                  })

    stdout: StdioCollector {
      onStreamFinished: {
        // Check if the output actually indicates success
        // nmcli outputs "Device '...' successfully activated" or "Connection successfully activated"
        // on success. Empty output or other messages indicate failure.
        const output = text.trim();

        if (!output || (output.indexOf("successfully activated") === -1 && output.indexOf("Connection successfully") === -1)) {
          // No success message - likely an error occurred
          // Don't update anything, let stderr handler deal with it
          return;
        }

        // Success - update cache
        let known = cacheAdapter.knownNetworks;
        known[connectProcess.ssid] = {
          "profileName": connectProcess.ssid,
          "lastConnected": Date.now()
        };
        cacheAdapter.knownNetworks = known;
        cacheAdapter.lastConnected = connectProcess.ssid;
        saveCache();

        // Immediately update the UI before scanning
        root.updateNetworkStatus(connectProcess.ssid, true);

        // Preload details immediately so Info panel has data instantly
        root.refreshActiveWifiDetails();

        root.connecting = false;
        root.connectingTo = "";
        Logger.i("Network", "Connected to network: '" + connectProcess.ssid + "'");
        ToastService.showNotice(I18n.tr("wifi.panel.title"), I18n.tr("toast.wifi.connected", {
                                                                       "ssid": connectProcess.ssid
                                                                     }), "wifi");

        // Still do a scan to get accurate signal and security info
        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.connecting = false;
        root.connectingTo = "";

        if (text.trim()) {
          // Parse common errors
          if (text.indexOf("Secrets were required") !== -1 || text.indexOf("no secrets provided") !== -1) {
            root.lastError = I18n.tr("toast.wifi.incorrect-password");
            forget(connectProcess.ssid);
          } else if (text.indexOf("No network with SSID") !== -1) {
            root.lastError = I18n.tr("toast.wifi.network-not-found");
          } else if (text.indexOf("Timeout") !== -1) {
            root.lastError = I18n.tr("toast.wifi.connection-timeout");
          } else {
            // Generic fallback
            root.lastError = I18n.tr("toast.wifi.connection-failed");
          }

          Logger.w("Network", "Connect error: " + text);
          // Notify user about the failure
          ToastService.showWarning(I18n.tr("wifi.panel.title"), root.lastError || I18n.tr("toast.wifi.connection-failed"));
        }
      }
    }
  }

  Process {
    id: disconnectProcess
    property string ssid: ""
    running: false
    command: ["nmcli", "connection", "down", "id", ssid]

    stdout: StdioCollector {
      onStreamFinished: {
        Logger.i("Network", "Disconnected from network: '" + disconnectProcess.ssid + "'");
        ToastService.showNotice(I18n.tr("wifi.panel.title"), I18n.tr("toast.wifi.disconnected", {
                                                                       "ssid": disconnectProcess.ssid
                                                                     }), "wifi-off");

        // Immediately update UI on successful disconnect
        root.updateNetworkStatus(disconnectProcess.ssid, false);
        root.disconnectingFrom = "";

        // Do a scan to refresh the list
        delayedScanTimer.interval = 1000;
        delayedScanTimer.restart();
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.disconnectingFrom = "";
        if (text.trim()) {
          Logger.w("Network", "Disconnect error: " + text);
        }
        // Still trigger a scan even on error
        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
      }
    }
  }

  Process {
    id: forgetProcess
    property string ssid: ""
    running: false

    // Try multiple common profile name patterns
    command: {
      var script = "";
      script += "ssid=\"$1\"\n";
      script += "deleted=false\n\n";
      script += "# Try exact SSID match first\n";
      script += "if nmcli connection delete id \"$ssid\" 2>/dev/null; then\n";
      script += "  echo \"Deleted profile: $ssid\"\n";
      script += "  deleted=true\n";
      script += "fi\n\n";
      script += "# Try \"Auto $ssid\" pattern\n";
      script += "if nmcli connection delete id \"Auto $ssid\" 2>/dev/null; then\n";
      script += "  echo \"Deleted profile: Auto $ssid\"\n";
      script += "  deleted=true\n";
      script += "fi\n\n";
      script += "# Try \"$ssid 1\", \"$ssid 2\", etc. patterns\n";
      script += "for i in 1 2 3; do\n";
      script += "  if nmcli connection delete id \"$ssid $i\" 2>/dev/null; then\n";
      script += "    echo \"Deleted profile: $ssid $i\"\n";
      script += "    deleted=true\n";
      script += "  fi\n";
      script += "done\n\n";
      script += "if [ \"$deleted\" = \"false\" ]; then\n";
      script += "  echo \"No profiles found for SSID: $ssid\"\n";
      script += "fi\n";
      return ["sh", "-c", script, "--", ssid];
    }

    stdout: StdioCollector {
      onStreamFinished: {
        Logger.i("Network", "Forget network: \"" + forgetProcess.ssid + "\"");
        Logger.d("Network", text.trim().replace(/[\r\n]/g, " "));

        // Update both cached and existing status immediately
        let nets = root.networks;
        if (nets[forgetProcess.ssid]) {
          nets[forgetProcess.ssid].cached = false;
          nets[forgetProcess.ssid].existing = false;
          // Trigger property change
          root.networks = ({});
          root.networks = nets;
        }

        root.forgettingNetwork = "";

        // Scan to verify the profile is gone
        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.forgettingNetwork = "";
        if (text.trim() && text.indexOf("No profiles found") === -1) {
          Logger.w("Network", "Forget error: " + text);
        }
        // Still Trigger a scan even on error
        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
      }
    }
  }
}
