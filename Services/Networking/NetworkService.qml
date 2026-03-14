pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.System
import qs.Services.UI

Singleton {
  id: root

  readonly property bool wifiAvailable: _wifiAvailable
  readonly property bool ethernetAvailable: _ethernetAvailable

  property bool _wifiAvailable: false
  property bool _ethernetAvailable: false

  // Core state
  property var networks: ({})
  property bool scanning: false
  property bool connecting: false
  property string connectingTo: ""
  property string lastError: ""
  property bool ethernetConnected: false
  // Each item: { ifname: string, state: string, connected: bool }
  property var ethernetInterfaces: ([])
  // Active Ethernet connection details
  property var activeEthernetDetails: ({})
  property string activeEthernetIf: ""
  property bool ethernetDetailsLoading: false
  property double activeEthernetDetailsTimestamp: 0
  // Keep same TTL policy for both kinds of links
  property int activeEthernetDetailsTtlMs: 5000
  property string disconnectingFrom: ""
  property string forgettingNetwork: ""
  property string networkConnectivity: "unknown"
  property bool internetConnectivity: true
  property bool ignoreScanResults: false
  property bool scanPending: false

  // Supported Wi-Fi security types
  property var supportedSecurityTypes: [
    {
      key: "open",
      name: I18n.tr("wifi.panel.security-open")
    },
    {
      key: "wep",
      name: "WEP"
    },
    {
      key: "wpa-psk",
      name: "WPA"
    },
    {
      key: "wpa2-psk",
      name: "WPA2/WPA3"
    },
    {
      key: "sae",
      name: "WPA3"
    },
    {
      key: "wpa-eap",
      name: "WPA Enterprise"
    },
    {
      key: "wpa2-eap",
      name: "WPA2 Enterprise"
    },
    {
      key: "wpa3-eap",
      name: "WPA3 Enterprise"
    }
  ]

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
          ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("common.enabled"), "wifi");
        }
        // Perform a scan to update the UI
        delayedScanTimer.interval = 3000;
        delayedScanTimer.restart();
      } else {
        if (!BluetoothService.airplaneModeToggled) {
          ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("common.disabled"), "wifi-off");
        }
        // Clear networks so the widget icon changes
        root.networks = ({});
      }
    }
  }

  // Handle system resume to refresh state and connectivity
  Connections {
    target: Time
    function onResumed() {
      Logger.i("Network", "System resumed - forcing state poll");
      ethernetStateProcess.running = true;
      root.scan();
      root.refreshActiveWifiDetails();
      root.refreshActiveEthernetDetails();
      connectivityCheckProcess.running = true;
    }
  }

  Component.onCompleted: {
    Logger.i("Network", "Service started");
    if (ProgramCheckerService.nmcliAvailable) {
      detectNetworkCapabilities();
      syncWifiState();
      scan();
      // Prime ethernet state immediately so UI can reflect wired status on startup
      ethernetStateProcess.running = true;
      refreshActiveWifiDetails();
      refreshActiveEthernetDetails();
    }
  }

  // Start initial checks when nmcli becomes available
  Connections {
    target: ProgramCheckerService
    function onNmcliAvailableChanged() {
      if (ProgramCheckerService.nmcliAvailable) {
        detectNetworkCapabilities();
        syncWifiState();
        scan();
        // Refresh ethernet status as soon as nmcli becomes available
        ethernetStateProcess.running = true;
        // Also refresh details so panels get info without waiting for timers
        refreshActiveWifiDetails();
        refreshActiveEthernetDetails();
      }
    }
  }

  // Function to detect host's networking capabilities eg has WiFi/Ethernet.
  function detectNetworkCapabilities() {
    if (ProgramCheckerService.nmcliAvailable) {
      Logger.d("Network", "Refreshing network status and capabilities...");
      ethernetStateProcess.running = true;
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
    if (detailsLoading) {
      return;
    }

    // Use cached details if they are fresh
    if (activeWifiIf && activeWifiDetails && (now - activeWifiDetailsTimestamp) < activeWifiDetailsTtlMs) {
      return;
    }

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

  // Refresh details for the currently active Ethernet link
  function refreshActiveEthernetDetails() {
    const now = Date.now();
    if (ethernetDetailsLoading) {
      return;
    }
    if (!root.ethernetConnected) {
      // Link is down: keep the selected interface so UI can still show its info as disconnected
      // Only clear details to avoid showing stale IP/speed/etc.
      root.activeEthernetDetails = ({});
      root.activeEthernetDetailsTimestamp = now;
      return;
    }
    // If we have fresh details for the same iface, skip
    if (activeEthernetIf && activeEthernetDetails && (now - activeEthernetDetailsTimestamp) < activeEthernetDetailsTtlMs) {
      return;
    }

    ethernetDetailsLoading = true;
    ethernetDeviceListProcess.running = true;
  }

  // Internet connectivity check timer
  Timer {
    id: connectivityCheckTimer
    interval: 15000
    running: ProgramCheckerService.nmcliAvailable
    repeat: true
    onTriggered: connectivityCheckProcess.running = true
  }

  // Core functions
  function syncWifiState() {
    if (!ProgramCheckerService.nmcliAvailable) {
      return;
    }
    wifiStateProcess.running = true;
  }

  function setWifiEnabled(enabled) {
    if (!ProgramCheckerService.nmcliAvailable) {
      return;
    }
    Logger.i("Wi-Fi", "SetWifiEnabled", enabled);
    Settings.data.network.wifiEnabled = enabled;
    wifiStateEnableProcess.running = true;
  }

  function scan() {
    if (!ProgramCheckerService.nmcliAvailable || !Settings.data.network.wifiEnabled) {
      return;
    }
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

  // Returns true if we currently have any detectable Ethernet interfaces
  function hasEthernet() {
    return root.ethernetInterfaces && root.ethernetInterfaces.length > 0;
  }

  // Refresh only Ethernet state/details
  function refreshEthernet() {
    if (!ProgramCheckerService.nmcliAvailable) {
      return;
    }
    ethernetStateProcess.running = true;
    refreshActiveEthernetDetails();
  }

  function connect(ssid, password = "", isHidden = false) {
    if (!ProgramCheckerService.nmcliAvailable || connecting) {
      return;
    }
    connecting = true;
    connectingTo = ssid;
    lastError = "";

    // Check if we have a saved connection
    if ((networks[ssid] && networks[ssid].existing) || cachedNetworks[ssid]) {
      connectProcess.mode = "saved";
      connectProcess.ssid = ssid;
      connectProcess.password = "";
      connectProcess.isHidden = false;
    } else {
      connectProcess.mode = "new";
      connectProcess.ssid = ssid;
      connectProcess.password = password;
      connectProcess.isHidden = isHidden;
    }

    connectProcess.running = true;
  }

  function connectManual(ssid, password, securityKey) {
    if (!ProgramCheckerService.nmcliAvailable || connecting) {
      return;
    }
    connecting = true;
    connectingTo = ssid;
    lastError = "";

    manualConnectProcess.ssid = ssid;
    manualConnectProcess.password = password;
    manualConnectProcess.securityKey = securityKey;
    manualConnectProcess.running = true;
  }

  function disconnect(ssid) {
    if (!ProgramCheckerService.nmcliAvailable) {
      return;
    }
    disconnectingFrom = ssid;
    disconnectProcess.ssid = ssid;
    disconnectProcess.running = true;
  }

  function forget(ssid) {
    if (!ProgramCheckerService.nmcliAvailable) {
      return;
    }
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
    if (isConnected === undefined) {
      isConnected = false;
    }
    if (isConnected && !root.internetConnectivity) {
      return "world-off";
    }
    if (signal >= 80) {
      return "wifi";
    }
    if (signal >= 50) {
      return "wifi-2";
    }
    if (signal >= 20) {
      return "wifi-1";
    }
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

  function parseIpDetails(text) {
    const details = {
      ipv4: "",
      gateway4: "",
      ipv6: "",
      gateway6: "",
      dns4: [],
      dns6: [],
      dns: "",
      connectionName: ""
    };
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) {
        continue;
      }
      const idx = line.indexOf(":");
      if (idx === -1) {
        continue;
      }
      const key = line.substring(0, idx);
      const val = line.substring(idx + 1);
      if (key === "GENERAL.CONNECTION") {
        details.connectionName = val;
      } else if (key.indexOf("IP4.ADDRESS") === 0) {
        details.ipv4 = val.split("/")[0];
      } else if (key === "IP4.GATEWAY") {
        details.gateway4 = val;
      } else if (key.indexOf("IP6.ADDRESS") === 0) {
        details.ipv6 = val.split("/")[0];
      } else if (key === "IP6.GATEWAY") {
        details.gateway6 = val;
      } else if (key.indexOf("IP4.DNS") === 0) {
        if (val && details.dns4.indexOf(val) === -1) {
          details.dns4.push(val);
        }
      } else if (key.indexOf("IP6.DNS") === 0) {
        if (val && details.dns6.indexOf(val) === -1) {
          details.dns6.push(val);
        }
      }
    }
    details.dns4 = details.dns4.join(", ");
    details.dns6 = details.dns6.join(", ");
    details.dns = [].concat(details.dns4 ? [details.dns4] : [], details.dns6 ? [details.dns6] : []).join(", ");
    return details;
  }

  // Processes
  Process {
    id: ethernetStateProcess
    running: ProgramCheckerService.nmcliAvailable
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device"]

    stdout: StdioCollector {
      onStreamFinished: {
        var connected = false;
        var wifiAvailable = false;
        var ethernetAvailable = false;
        var devIf = "";
        var lines = text.trim().split("\n");
        var ethList = [];
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split(":");
          if (parts.length >= 3) {
            var ifname = parts[0];
            var type = parts[1];
            var state = parts[2];

            if (type === "wifi") {
              wifiAvailable = true;
            } else if (type === "ethernet" && state !== "unmanaged") {
              ethernetAvailable = true;
              var isConn = state === "connected";
              ethList.push({
                             ifname: ifname,
                             state: state,
                             connected: isConn
                           });
              if (isConn && !connected) {
                connected = true;
                devIf = ifname;
              }
            }
          }
        }
        
        // Update capabilities
        root._wifiAvailable = wifiAvailable;
        root._ethernetAvailable = ethernetAvailable;

        // Sort interfaces: connected first, then by name
        ethList.sort(function (a, b) {
          if (a.connected !== b.connected) {
            return a.connected ? -1 : 1;
          }
          return a.ifname.localeCompare(b.ifname);
        });
        root.ethernetInterfaces = ethList;

        if (root.ethernetConnected !== connected) {
          root.ethernetConnected = connected;
          Logger.d("Network", "Ethernet connected:", root.ethernetConnected);
        }
        if (connected) {
          if (root.activeEthernetIf !== devIf) {
            root.activeEthernetIf = devIf;
            // refresh details for the new interface
            root.activeEthernetDetailsTimestamp = 0;
          }
          root.refreshActiveEthernetDetails();
        } else {
          // Preserve the selected interface; just clear details so UI shows a disconnected state
          root.activeEthernetDetails = ({});
          root.activeEthernetDetailsTimestamp = Date.now();
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

  // Discover connected Ethernet interface and fetch details
  Process {
    id: ethernetDeviceListProcess
    running: false
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device"]

    stdout: StdioCollector {
      onStreamFinished: {
        let ifname = "";
        const lines = text.split("\n");
        const ethList = [];
        for (let i = 0; i < lines.length; i++) {
          const parts = lines[i].trim().split(":");
          if (parts.length >= 3) {
            const dev = parts[0];
            const type = parts[1];
            const state = parts[2];
            if (state === "unmanaged") {
              continue;
            }
            if (type === "ethernet" && state === "connected") {
              ifname = dev;
            }
            if (type === "ethernet") {
              ethList.push({
                             ifname: dev,
                             state: state,
                             connected: state === "connected"
                           });
            }
          }
        }
        ethList.sort(function (a, b) {
          if (a.connected !== b.connected) {
            return a.connected ? -1 : 1;
          }
          return a.ifname.localeCompare(b.ifname);
        });
        root.ethernetInterfaces = ethList;
        if (ifname) {
          if (root.activeEthernetIf !== ifname) {
            root.activeEthernetIf = ifname;
          }
          ethernetDeviceShowProcess.ifname = ifname;
          ethernetDeviceShowProcess.running = true;
        } else {
          root.activeEthernetDetailsTimestamp = Date.now();
          root.ethernetDetailsLoading = false;
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Network", "nmcli device list (eth) stderr:", text.trim());
        }
        if (!root.activeEthernetIf) {
          root.activeEthernetDetailsTimestamp = Date.now();
          root.ethernetDetailsLoading = false;
        }
      }
    }
  }

  // Fetch IPv4/Gateway/DNS and Connection Name for Ethernet iface
  Process {
    id: ethernetDeviceShowProcess
    property string ifname: ""
    running: false
    // Speed is resolved via ethtool fallback below to avoid stderr warnings
    command: ["nmcli", "-t", "-f", "GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show", ifname]

    stdout: StdioCollector {
      onStreamFinished: {
        const details = root.activeEthernetDetails || ({});
        const parsed = root.parseIpDetails(text);

        details.ifname = ethernetDeviceShowProcess.ifname;
        details.connectionName = parsed.connectionName;
        // No speed from nmcli: keep empty so ethtool fallback below fills it
        details.speed = details.speed && details.speed.length > 0 ? details.speed : "";
        details.ipv4 = parsed.ipv4;
        details.gateway4 = parsed.gateway4;
        details.ipv6 = parsed.ipv6;
        details.gateway6 = parsed.gateway6;
        details.dns4 = parsed.dns4;
        details.dns6 = parsed.dns6;
        details.dns = parsed.dns;

        root.activeEthernetDetails = details;
        // If speed missing, try sysfs first, then fallback to ethtool
        if (!details.speed || details.speed.length === 0) {
          ethernetSysfsSpeedProcess.ifname = ethernetDeviceShowProcess.ifname;
          ethernetSysfsSpeedProcess.running = true;
        } else {
          root.activeEthernetDetailsTimestamp = Date.now();
          root.ethernetDetailsLoading = false;
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Network", "nmcli device show (eth) stderr:", text.trim());
        }
        root.activeEthernetDetailsTimestamp = Date.now();
        root.ethernetDetailsLoading = false;
      }
    }
  }

  // Try to read Ethernet speed from sysfs first: /sys/class/net/<if>/speed (numeric Mbit/s)
  Process {
    id: ethernetSysfsSpeedProcess
    property string ifname: ""
    running: false
    command: ["sh", "-c", "cat '/sys/class/net/" + ifname + "/speed' 2>/dev/null || true"]

    stdout: StdioCollector {
      onStreamFinished: {
        const details = root.activeEthernetDetails || ({});
        let speedText = "";
        const v = text.trim();
        // Expect a number like 1000
        const num = parseFloat(v);
        if (!isNaN(num) && num > 0) {
          details.speed = Math.round(num) + " Mbit/s";
          details.speedMbit = num;
          root.activeEthernetDetails = details;
          root.activeEthernetDetailsTimestamp = Date.now();
          root.ethernetDetailsLoading = false;
        } else {
          // Fallback to ethtool if sysfs unreadable or invalid
          ethernetEthtoolProcess.ifname = ethernetSysfsSpeedProcess.ifname;
          ethernetEthtoolProcess.running = true;
        }
      }
    }
    stderr: StdioCollector {}
  }

  // Optional: query Ethernet speed via ethtool as a fallback
  Process {
    id: ethernetEthtoolProcess
    property string ifname: ""
    running: false
    command: ["sh", "-c", "ethtool '" + ifname + "' 2>/dev/null || true"]

    stdout: StdioCollector {
      onStreamFinished: {
        const details = root.activeEthernetDetails || ({});
        let speedText = "";
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i].trim();
          if (line.toLowerCase().indexOf("speed:") === 0) {
            // Example: "Speed: 1000Mb/s"
            const v = line.substring(6).trim();
            if (v) {
              // Normalize to "1000 Mbit/s"
              const normalized = v.replace(/mb\/?s/i, "Mbit/s").replace(/\s+/g, " ");
              speedText = normalized;
            }
            break;
          }
        }
        if (speedText && speedText.length > 0) {
          details.speed = speedText;
          // Try to derive numeric value
          const m = speedText.match(/([0-9]+(?:\.[0-9]+)?)\s*Mbit\/s/i);
          if (m) {
            details.speedMbit = parseFloat(m[1]);
          }
          root.activeEthernetDetails = details;
        }
        root.activeEthernetDetailsTimestamp = Date.now();
        root.ethernetDetailsLoading = false;
      }
    }
    stderr: StdioCollector {}
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
            if (state === "unmanaged") {
              continue;
            }
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

  // Fetch IP info for the interface
  Process {
    id: wifiDeviceShowProcess
    property string ifname: ""
    running: false
    command: ["nmcli", "-t", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,IP6.GATEWAY,IP6.DNS", "device", "show", ifname]

    stdout: StdioCollector {
      onStreamFinished: {
        const details = root.activeWifiDetails || ({});
        const parsed = root.parseIpDetails(text);

        details.ipv4 = parsed.ipv4;
        details.gateway4 = parsed.gateway4;
        details.ipv6 = parsed.ipv6;
        details.gateway6 = parsed.gateway6;
        details.dns4 = parsed.dns4;
        details.dns6 = parsed.dns6;
        details.dns = parsed.dns;
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

  // Optional: query Wi‑Fi bitrate and link info via iw if available
  Process {
    id: wifiIwLinkProcess
    property string ifname: ""
    running: false
    command: ["sh", "-c", "iw dev '" + ifname + "' link 2>/dev/null; iw dev '" + ifname + "' info 2>/dev/null || true"]

    stdout: StdioCollector {
      onStreamFinished: {
        const details = root.activeWifiDetails || ({});
        let rate = "";
        let freq = "";
        let iwChannel = "";
        let iwWidth = "";
        const lines = text.split("\n");
        for (var k = 0; k < lines.length; k++) {
          var line2 = lines[k].trim();
          var low = line2.toLowerCase();
          if (low.indexOf("tx bitrate:") === 0) {
            rate = line2.substring(11).trim();
          } else if (low.indexOf("freq:") === 0) {
            freq = line2.substring(5).trim();
          } else if (low.indexOf("channel") === 0) {
            // Parse "channel 9 (2452 MHz), width: 20 MHz, center1: 2452 MHz"
            var chanMatch = line2.match(/channel\s+(\d+)/i);
            if (chanMatch) {
              iwChannel = chanMatch[1];
            }
            var widthMatchInfo = line2.match(/width:\s+(\d+)\s+MHz/i);
            if (widthMatchInfo) {
              iwWidth = widthMatchInfo[1] + " MHz";
            }
          }
        }

        // Determine band and channel from frequency
        // https://en.wikipedia.org/wiki/List_of_WLAN_channels
        let band = "";
        let channel = iwChannel;
        if (freq) {
          const f = +freq;
          if (f) {
            switch (true) {
              // https://en.wikipedia.org/wiki/List_of_WLAN_channels#6_GHz_(802.11ax_and_802.11be)
              case (f >= 5925 && f < 7125):
              band = "6 GHz";
              if (!channel) {
                channel = Math.round((f - 5940) / 5).toString();
              }
              break;
              // https://en.wikipedia.org/wiki/List_of_WLAN_channels#5_GHz_(802.11a/h/n/ac/ax/be)
              case (f >= 5150 && f < 5925):
              band = "5 GHz";
              if (!channel) {
                channel = Math.round((f - 5000) / 5).toString();
              }
              break;
              // https://en.wikipedia.org/wiki/List_of_WLAN_channels#2.4_GHz_(802.11b/g/n/ax/be)
              case (f >= 2400 && f < 2500):
              band = "2.4 GHz";
              if (!channel) {
                if (f === 2484) {
                  channel = "14";
                } else {
                  channel = Math.round((f - 2407) / 5).toString();
                }
              }
              break;
              default:
              band = `${f} MHz`;
            }
          }
        }

        // Shorten verbose bitrate strings like: "360.0 MBit/s VHT-MCS 8 40MHz short GI"
        let rateShort = "";
        let width = iwWidth;
        if (rate) {
          // Extract width from bitrate if not already found in info (fallback)
          if (!width) {
            var widthMatchBitrate = rate.match(/(\d+)MHz/i);
            if (widthMatchBitrate) {
              width = widthMatchBitrate[1] + " MHz";
            }
          }

          var parts = rate.trim().split(" ");
          // compact consecutive spaces
          var compact = [];
          for (var i = 0; i < parts.length; i++) {
            var p = parts[i];
            if (p && p.length > 0) {
              compact.push(p);
            }
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

        // Enhance band string with channel and width: "Band / Ch Channel (Width)"
        let enhancedBand = band;
        if (channel && width) {
          enhancedBand = `${band} / Ch ${channel} (${width})`;
        } else if (channel) {
          enhancedBand = `${band} / Ch ${channel}`;
        }

        details.rate = rate;
        details.rateShort = rateShort;
        details.band = enhancedBand;
        details.channel = channel;
        details.width = width;
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
    environment: ({
                    "LC_ALL": "C"
                  })

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
        if (result === "full" || result === "none" || result === "unknown") {
          if (connectivityCheckProcess.failedChecks !== 0) {
            connectivityCheckProcess.failedChecks = 0;
          }
          if (result !== root.networkConnectivity) {
            if (result === "full") {
              root.internetConnectivity = true;
            }
            root.networkConnectivity = result;
            root.scan();
          }
          return;
        }
        if ((result === "limited" || result === "portal") && result !== root.networkConnectivity) {
          connectivityCheckProcess.failedChecks++;
          if (connectivityCheckProcess.failedChecks === 3) {
            root.networkConnectivity = result;
            pingCheckProcess.running = true;
          }
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
        ToastService.showWarning(root.cachedLastConnected, I18n.tr("toast.internet-limited"));
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
          if (!line) {
            continue;
          }

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

          let security = remainingLine2.substring(thirdLastColonIdx + 1);
          // This change will add a slash where mixed security protocols are used.
          if (security) {
            security = security.replace("WPA2 WPA3", "WPA2/WPA3").replace("WPA1 WPA2", "WPA1/WPA2");
          }

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
    property bool isHidden: false
    running: false

    command: {
      if (mode === "saved") {
        return ["nmcli", "connection", "up", "id", ssid];
      } else {
        var cmd = ["nmcli", "device", "wifi", "connect", ssid];
        if (isHidden) {
          cmd.push("hidden", "yes");
        }
        if (password) {
          cmd.push("password", password);
        }
        if (root.activeWifiIf) {
          cmd.push("ifname", root.activeWifiIf);
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
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.wifi.connected", {
                                                                  "ssid": connectProcess.ssid
                                                                }), "wifi");

        // Still do a scan to get accurate signal and security info
        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          root.connecting = false;
          root.connectingTo = "";

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
          ToastService.showWarning(I18n.tr("common.wifi"), root.lastError || I18n.tr("toast.wifi.connection-failed"));
        }
      }
    }
  }

  Process {
    id: manualConnectProcess
    property string ssid: ""
    property string password: ""
    property string securityKey: ""
    running: false

    command: {
      var script = `
      SSID="$1"
      PWD="$2"
      SEC="$3"

      UUID=$(nmcli -t -f UUID,TYPE,NAME connection show | grep ":802-11-wireless:$SSID$" | head -n1 | cut -d: -f1)
      if [ -n "$UUID" ]; then
          nmcli connection delete uuid "$UUID" 2>/dev/null || true
      fi

      case "$SEC" in
          wpa-psk|wpa2-psk)
              nmcli connection add type wifi con-name "$SSID" ssid "$SSID" -- wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PWD" 802-11-wireless.hidden yes
              ;;
          sae)
              nmcli connection add type wifi con-name "$SSID" ssid "$SSID" -- wifi-sec.key-mgmt sae wifi-sec.psk "$PWD" 802-11-wireless.hidden yes
              ;;
          wep)
              nmcli connection add type wifi con-name "$SSID" ssid "$SSID" -- wifi-sec.key-mgmt none wifi-sec.wep-key0 "$PWD" 802-11-wireless.hidden yes
              ;;
          *-eap)
              # Enterprise not fully supported in Stage 1
              echo "Enterprise networks not supported yet"
              exit 1
              ;;
          *)
              nmcli connection add type wifi con-name "$SSID" ssid "$SSID" -- 802-11-wireless.hidden yes
              ;;
      esac
      nmcli connection up id "$SSID"
    `;
      return ["sh", "-c", script, "--", ssid, password, securityKey];
    }
    environment: ({
                    "LC_ALL": "C"
                  })

    stdout: StdioCollector {
      onStreamFinished: {
        const output = text.trim();
        if (output.indexOf("successfully activated") === -1) {
          return;
        }

        // Success - update cache
        let known = cacheAdapter.knownNetworks;
        known[manualConnectProcess.ssid] = {
          "profileName": manualConnectProcess.ssid,
          "lastConnected": Date.now()
        };
        cacheAdapter.knownNetworks = known;
        cacheAdapter.lastConnected = manualConnectProcess.ssid;
        saveCache();

        root.updateNetworkStatus(manualConnectProcess.ssid, true);
        root.refreshActiveWifiDetails();

        root.connecting = false;
        root.connectingTo = "";
        Logger.i("Network", "Manually connected to hidden network: '" + manualConnectProcess.ssid + "'");
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.wifi.connected", {
                                                                  "ssid": manualConnectProcess.ssid
                                                                }), "wifi");

        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          root.connecting = false;
          root.connectingTo = "";
          root.lastError = I18n.tr("toast.wifi.connection-failed");
          Logger.w("Network", "Manual connect error: " + text);
          ToastService.showWarning(I18n.tr("common.wifi"), root.lastError);
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
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.wifi.disconnected", {
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
    environment: ({
                    "LC_ALL": "C"
                  })

    // Try multiple common profile name patterns
    command: {
      var script = `
ssid="$1"
deleted=false

# Try to find a wifi connection with this SSID and delete it
UUID=$(nmcli -t -f UUID,TYPE,NAME connection show | grep ":802-11-wireless:$ssid$" | head -n1 | cut -d: -f1)
if [ -n "$UUID" ]; then
    if nmcli connection delete uuid "$UUID" 2>/dev/null; then
        echo "Deleted profile: $ssid ($UUID)"
        deleted=true
    fi
fi

# Fallback: try common patterns if UUID lookup failed
if [ "$deleted" = "false" ]; then
    # Try "Auto $ssid" pattern
    if nmcli connection delete id "Auto $ssid" 2>/dev/null; then
        echo "Deleted profile: Auto $ssid"
        deleted=true
    fi

    # Try "$ssid 1", "$ssid 2", etc. patterns
    for i in 1 2 3; do
        if nmcli connection delete id "$ssid $i" 2>/dev/null; then
            echo "Deleted profile: $ssid $i"
            deleted=true
        fi
    done
fi

if [ "$deleted" = "false" ]; then
    echo "No profiles found for SSID: $ssid"
fi
`;
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
