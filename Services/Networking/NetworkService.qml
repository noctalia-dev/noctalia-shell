pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Commons
import qs.Services.System
import qs.Services.UI

Singleton {
  id: root
  // Shared core (read-only) properties
  readonly property bool wifiAvailable: _wifiAvailable
  readonly property bool ethernetAvailable: _ethernetAvailable
  readonly property bool internetConnectivity: _internetConnectivity
  readonly property string networkConnectivity: _networkConnectivity

  // Supported Wi-Fi security types
  readonly property var supportedSecurityTypes: [
    {
      key: "open",
      name: I18n.tr("wifi.panel.security-open")
    },
    {
      key: "wep",
      name: I18n.tr("wifi.panel.security-wep")
    },
    {
      key: "wpa-psk",
      name: I18n.tr("wifi.panel.security-wpa")
    },
    {
      key: "wpa2-psk",
      name: I18n.tr("wifi.panel.security-wpa23")
    },
    {
      key: "sae",
      name: I18n.tr("wifi.panel.security-wpa3")
    },
    {
      key: "wpa-eap",
      name: I18n.tr("wifi.panel.security-wpa-ent")
    },
    {
      key: "wpa2-eap",
      name: I18n.tr("wifi.panel.security-wpa2-ent")
    },
    {
      key: "wpa3-eap",
      name: I18n.tr("wifi.panel.security-wpa3-ent")
    }
  ]

  // Core properties
  property bool _wifiAvailable: false
  property bool _ethernetAvailable: false
  property string _networkConnectivity: "unknown"
  property bool _internetConnectivity: false
  property string lastError: ""
  property int activeDetailsTtlMs: 10000
  // Ethernet properties
  property var ethernetInterfaces: ([])
  property var activeEthernetDetails: ({})
  property bool ethernetConnected: false
  property string activeEthernetIf: ""
  property bool ethernetDetailsLoading: false
  property double activeEthernetDetailsTimestamp: 0
  // Wi-Fi properties
  readonly property bool wifiEnabled: Networking.wifiEnabled
  property var networks: ({})
  property var activeWifiDetails: ({})
  property bool wifiConnected: false
  property string activeWifiIf: ""
  property bool wifiDetailsLoading: false
  property double activeWifiDetailsTimestamp: 0
  property bool wifiInit: false
  // Wi-Fi adapter/connection properties
  property bool connecting: false
  property string connectingTo: ""
  property string disconnectingFrom: ""
  property string forgettingNetwork: ""
  property bool scanPending: false
  property bool scanningActive: false
  property var existingProfiles: ({})

  Connections {
    target: root
    function onWifiEnabledChanged() {
      if (!root.wifiInit || BluetoothService.airplaneModeToggled) {
        return;
      }
      wifiDebounce.restart();
    }
  }

  // Handle system resume to refresh state and connectivity
  Connections {
    target: Time
    function onResumed() {
      Logger.i("Network", "System resumed - forcing state poll");
      deviceStatusProcess.running = true;
      connectivityCheckProcess.running = true;
    }
  }

  // Start initial checks when nmcli becomes available
  Connections {
    target: ProgramCheckerService
    function onNmcliAvailableChanged() {
      if (ProgramCheckerService.nmcliAvailable) {
        deviceStatusProcess.running = true;
        connectivityCheckProcess.running = true;
      }
    }
  }

  Component.onCompleted: {
    Logger.i("Network", "Service started");
    wifiInitTimer.running = true;

    // Ensure initial detection if nmcli is already available at startup
    if (ProgramCheckerService.nmcliAvailable) {
      deviceStatusProcess.running = true;
      connectivityCheckProcess.running = true;
    }
  }

  // Prevent an initial "Wi-Fi enabled" toast and trigger initial scan
  Timer {
    id: wifiInitTimer
    interval: 100
    onTriggered: {
      root.wifiInit = true;
      if (root.wifiEnabled) {
        root.scan();
      }
    }
  }

  // Debounce to prevent multiple toast notifications from transient states
  Timer {
    id: wifiDebounce
    interval: 300
    onTriggered: {
      if (root.wifiEnabled) {
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("common.enabled"), "wifi");
        connectivityCheckProcess.running = true;
        deviceStatusProcess.running = true;
        root.scan();
      } else {
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("common.disabled"), "wifi-off");
        root.scanningActive = false;
        root.networks = ({});
      }
    }
  }

  // Internet connectivity check timer
  Timer {
    id: connectivityCheckTimer
    interval: 15000
    running: ProgramCheckerService.nmcliAvailable && (root.ethernetConnected || root.wifiConnected)
    repeat: true
    onTriggered: connectivityCheckProcess.running = true
  }

  // Delayed scan timer
  Timer {
    id: delayedScanTimer
    interval: 7000
    onTriggered: scan()
  }

  // Refresh details for the currently active Wi‑Fi link
  function refreshActiveWifiDetails() {
    const now = Date.now();
    if (wifiDetailsLoading || (activeWifiIf && wifiConnected && activeWifiDetails && (now - activeWifiDetailsTimestamp) < activeDetailsTtlMs)) {
      return;
    }
    if (wifiConnected && activeWifiIf) {
      wifiDetailsLoading = true;
      deviceStatusProcess.running = true;
    }
  }

  // Refresh details for the currently active Ethernet link
  function refreshActiveEthernetDetails() {
    const now = Date.now();
    if (ethernetDetailsLoading || activeEthernetIf && activeEthernetDetails && (now - activeEthernetDetailsTimestamp) < activeDetailsTtlMs) {
      return;
    }
    if (ethernetConnected && activeEthernetIf) {
      ethernetDetailsLoading = true;
      deviceStatusProcess.running = true;
    }
  }

  // Core functions
  function setWifiEnabled(enabled) {
    if (!ProgramCheckerService.nmcliAvailable) {
      return;
    }
    Logger.i("Wi-Fi", "SetWifiEnabled", enabled);
    Networking.wifiEnabled = enabled;
  }

  function scan() {
    if (!ProgramCheckerService.nmcliAvailable || !root.wifiEnabled) {
      return;
    }
    lastError = "";

    // If scanning in progress, mark as pending to trigger another scan when current when finished.
    if (profileCheckProcess.running || scanProcess.running) {
      root.scanPending = true;
      return;
    }

    // Get existing profiles first, then scan
    profileCheckProcess.running = true;
    root.scanningActive = true;
    Logger.d("Network", "Scanning Wi-Fi networks...");
  }

  function connect(ssid, password = "", isHidden = false, securityKey = "", identity = "", enterpriseConfig = {}) {
    if (!ProgramCheckerService.nmcliAvailable || connecting) {
      return;
    }

    const isSaved = (networks[ssid] && networks[ssid].existing);
    const isEnt = securityKey ? isEnterprise(securityKey) : isEnterprise(networks[ssid] ? networks[ssid].security : "");

    connecting = true;
    connectingTo = ssid;
    lastError = "";

    connectProcess.ssid = ssid;
    connectProcess.password = password;
    connectProcess.isHidden = isHidden;

    if (isSaved) {
      connectProcess.mode = "saved";
    } else if (isEnt || securityKey === "wep" || (securityKey && securityKey !== "open" && securityKey !== "wpa-psk" && securityKey !== "wpa2-psk")) {
      connectProcess.mode = "manual";
      connectProcess.securityKey = securityKey || (networks[ssid] ? networks[ssid].security : "wpa-psk");
      connectProcess.identity = identity;
      connectProcess.eap = enterpriseConfig.eap || "peap";
      connectProcess.phase2 = enterpriseConfig.phase2 || "mschapv2";
      connectProcess.anonIdentity = enterpriseConfig.anonIdentity || "";
      connectProcess.caCert = enterpriseConfig.caCert || "";
    } else {
      connectProcess.mode = "new";
    }

    connectProcess.running = true;
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
    } else if (connected) {
      // Create a temporary entry if network doesn't exist yet
      nets[ssid] = {
        "ssid": ssid,
        "security": "--",
        "signal": 100,
        "connected": true,
        "existing": true
      };
    }
    // Trigger property change notification
    networks = ({});
    networks = nets;
  }

  // Helper functions
  function getSignalInfo(signal, isConnected) {
    let icon = "";
    if (isConnected) {
      if (root._networkConnectivity === "limited") {
        icon = "wifi-exclamation";
      } else if (root._networkConnectivity === "portal" || root._networkConnectivity === "unknown") {
        icon = "wifi-question";
      }
    }
    const label = signal >= 80 ? I18n.tr("wifi.signal.excellent") : signal >= 60 ? I18n.tr("wifi.signal.good") : signal >= 35 ? I18n.tr("wifi.signal.fair") : signal >= 15 ? I18n.tr("wifi.signal.poor") : I18n.tr("wifi.signal.weak");
    if (!icon) {
      icon = signal >= 80 ? "wifi" : signal >= 60 ? "wifi-3" : signal >= 35 ? "wifi-2" : signal >= 15 ? "wifi-1" : "wifi-0";
    }
    return {
      icon,
      label
    };
  }

  function isSecured(security) {
    return security && security !== "--" && security.trim() !== "";
  }

  function isEnterprise(security) {
    if (!security) {
      return false;
    }
    const s = security.toUpperCase();
    return s.indexOf("802.1X") !== -1 || s.indexOf("EAP") !== -1 || s.indexOf("ENTERPRISE") !== -1;
  }

  function parseIpDetails(text) {
    const details = {
      connectionName: "",
      ipv4: "",
      gateway4: "",
      dns4: [],
      ipv6: [],
      gateway6: [],
      dns6: [],
      hwAddr: "",
      speed: ""
    };
    const addUnique = (arr, val) => {
      if (val && arr.indexOf(val) === -1) {
        arr.push(val);
      }
    };
    const handlers = {
      "GENERAL.CONNECTION": v => {
        details.connectionName = v;
      },
      "GENERAL.HWADDR": v => {
        details.hwAddr = v;
      },
      "CAPABILITIES.SPEED": v => {
        if (v && v !== "unknown") {
          details.speed = v;
        }
      },
      "IP4.ADDRESS": v => {
        details.ipv4 = v.split("/")[0];
      },
      "IP4.GATEWAY": v => {
        details.gateway4 = v;
      },
      "IP6.ADDRESS": v => {
        addUnique(details.ipv6, v.split("/")[0]);
      },
      "IP6.GATEWAY": v => {
        addUnique(details.gateway6, v);
      },
      "IP4.DNS": v => {
        addUnique(details.dns4, v);
      },
      "IP6.DNS": v => {
        addUnique(details.dns6, v);
      }
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
      const key = line.substring(0, idx).replace(/\[\d+\]$/, "");
      const val = line.substring(idx + 1).trim();
      if (handlers[key]) {
        handlers[key](val);
      }
    }
    return details;
  }

  // Functions used in /Modules/Panels/ControlCenter/Widgets/Network.qml & /Modules/Bar/Widgets/Network.qml
  function getStatusText(showSpeed = false) {
    // This variable can be tied to a toggle
    if (root.connecting) {
      return root.connectingTo ? I18n.tr("common.connecting") + " " + root.connectingTo : I18n.tr("common.connecting");
    }

    if (Settings.data.network.airplaneModeEnabled) {
      return I18n.tr("toast.airplane-mode.title");
    }
    if (!root.wifiEnabled) {
      return "";
    }

    // Ethernet
    if (root.ethernetConnected) {
      const eth = root.activeEthernetDetails;
      const name = eth.connectionName || (root.ethernetInterfaces.length > 0 ? root.ethernetInterfaces[0].connectionName : "") || "";
      const speed = eth.speed || "";
      return (name + (showSpeed && speed ? " - " + speed : ""));
    }

    // Wi-Fi
    if (root.wifiConnected) {
      const wl = root.activeWifiDetails;
      const speed = wl.rateShort || wl.rate || "";
      const connectedNet = Object.values(root.networks).find(net => net.connected);
      const name = connectedNet ? connectedNet.ssid : (wl.connectionName || "");
      return (name + (showSpeed && speed ? " - " + speed : ""));
    }
    return "";
  }

  function getIcon(forceEthernet = false) {
    if (Settings.data.network.airplaneModeEnabled && !forceEthernet) {
      return "plane";
    }

    // 1. Ethernet Priority: Show Ethernet icon if connected OR if specifically requested (Panel)
    if (root.ethernetConnected || forceEthernet) {
      switch (root._networkConnectivity) {
      case "limited":
        return "ethernet-exclamation";
      case "portal":
      case "unknown":
        return "ethernet-question";
      case "full":
        return "ethernet";
      default:
        return "ethernet-off";
      }
    }

    // 2. Wi-Fi Fallback
    if (root.wifiAvailable || !forceEthernet) {
      const networkCount = Object.values(root.networks).length;
      if (!root.wifiEnabled) {
        return "wifi-off";
      }
      if (root.wifiConnected) {
        let s = (root.activeWifiDetails && root.activeWifiDetails.signal !== undefined && root.activeWifiDetails.signal !== "") ? root.activeWifiDetails.signal : 0;
        return root.getSignalInfo(s, true).icon;
      }
      if (root.connecting || networkCount > 0) {
        return "wifi-question";
      }
    }
    return (root.ethernetAvailable || root.ethernetConnected) ? "ethernet-off" : root.wifiAvailable ? "wifi-0" : "wifi-off";
  }

  // Processes
  // Discover connected interface[s] and fetch details [1]
  Process {
    id: deviceStatusProcess
    running: false
    command: ["sh", "-c", "nmcli -t -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,IP6.GATEWAY,IP6.DNS,CAPABILITIES.SPEED device show; echo \"------\"; nmcli -t -f IN-USE,SIGNAL,RATE,CHAN,FREQ,BANDWIDTH device wifi list"]
    environment: ({
                    "LC_ALL": "C"
                  })

    stdout: StdioCollector {
      onStreamFinished: {
        const outputParts = text.split("------");
        const deviceText = outputParts[0];
        const wifiText = outputParts[1] || "";

        let lines = deviceText.split("\n");
        let deviceBlocks = [];
        let currentBlock = [];

        for (let i = 0; i < lines.length; i++) {
          let line = lines[i].trim();
          if (!line) {
            continue;
          }
          if (line.startsWith("GENERAL.DEVICE:")) {
            if (currentBlock.length > 0) {
              deviceBlocks.push(currentBlock);
            }
            currentBlock = [line];
          } else if (currentBlock.length > 0) {
            currentBlock.push(line);
          }
        }
        if (currentBlock.length > 0) {
          deviceBlocks.push(currentBlock);
        }

        let activeEthIf = "";
        let activeWifiIf = "";
        let wifiAvailable = false;
        let ethernetAvailable = false;
        let ethList = [];

        let newActiveWifiDetails = ({});
        let newActiveEthernetDetails = ({});

        for (let b = 0; b < deviceBlocks.length; b++) {
          let block = deviceBlocks[b];
          let blockText = block.join("\n");
          let details = root.parseIpDetails(blockText);

          let name = "";
          let type = "";
          let stateStr = "";

          for (let l = 0; l < block.length; l++) {
            let line = block[l];
            if (line.startsWith("GENERAL.DEVICE:")) {
              name = line.substring(15).trim();
            } else if (line.startsWith("GENERAL.TYPE:")) {
              type = line.substring(13).trim();
            } else if (line.startsWith("GENERAL.STATE:")) {
              stateStr = line.substring(14).trim();
            }
          }

          if (stateStr.indexOf("(unmanaged)") !== -1) {
            continue;
          }
          let isConnected = stateStr.indexOf("(connected)") !== -1;

          if (type === "ethernet") {
            ethernetAvailable = true;
            let stateName = stateStr.split(" ")[1] ? stateStr.split(" ")[1].replace(/[()]/g, "") : stateStr;
            ethList.push({
                           ifname: name,
                           state: stateName,
                           connected: isConnected,
                           connectionName: details.connectionName
                         });
            if (isConnected && !activeEthIf) {
              activeEthIf = name;
              newActiveEthernetDetails = details;
              newActiveEthernetDetails.ifname = name;
            }
          } else if (type === "wifi") {
            wifiAvailable = true;
            if (isConnected && !activeWifiIf) {
              activeWifiIf = name;
              newActiveWifiDetails = details;
              newActiveWifiDetails.ifname = name;
            }
          }
        }

        // Parse Wi-Fi details if active
        if (activeWifiIf && wifiText) {
          let rate = "";
          let freq = "";
          let channel = "";
          let width = "";
          let signal = "";

          const wifiLines = wifiText.split("\n");
          for (let i = 0; i < wifiLines.length; i++) {
            const line = wifiLines[i].trim();
            if (line.startsWith("*")) {
              const parts = line.split(":");
              if (parts.length >= 6) {
                signal = parts[1];
                rate = parts[2];
                channel = parts[3];
                freq = parts[4].replace(" MHz", "");
                width = parts[5];
              }
              break;
            }
          }

          let band = "";
          if (freq) {
            const f = +freq;
            if (f) {
              switch (true) {
                case (f >= 5925 && f < 7125):
                band = "6 GHz";
                break;
                case (f >= 5150 && f < 5925):
                band = "5 GHz";
                break;
                case (f >= 2400 && f < 2500):
                band = "2.4 GHz";
                break;
                default:
                band = `${f} MHz`;
              }
            }
          }

          let rateShort = "";
          if (rate) {
            var rparts = rate.trim().split(" ");
            var compact = [];
            for (var i = 0; i < rparts.length; i++) {
              if (rparts[i]) {
                compact.push(rparts[i]);
              }
            }
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
              var parsed = parseFloat(num);
              if (!isNaN(parsed)) {
                rateShort = parsed + " Mbit/s";
              }
            }
            if (!rateShort) {
              rateShort = compact.slice(0, 2).join(" ");
            }
          }

          let enhancedBand = band;
          if (channel && width) {
            enhancedBand = `${band} / ${channel} (${width})`;
          } else if (channel) {
            enhancedBand = `${band} / ${channel}`;
          }

          if (newActiveWifiDetails.speed) {
            newActiveWifiDetails.rate = newActiveWifiDetails.speed.replace(/Mb\/s/i, "Mbit/s");
            newActiveWifiDetails.rateShort = newActiveWifiDetails.rate;
          } else {
            newActiveWifiDetails.rate = rate;
            newActiveWifiDetails.rateShort = rateShort;
          }
          newActiveWifiDetails.band = enhancedBand;
          newActiveWifiDetails.channel = channel;
          newActiveWifiDetails.width = width;
          newActiveWifiDetails.signal = signal;
        }

        root._wifiAvailable = wifiAvailable;
        root._ethernetAvailable = ethernetAvailable;
        root.ethernetConnected = (activeEthIf !== "");
        root.wifiConnected = (activeWifiIf !== "");

        Logger.d("Network", "Device sync: wifiAvailable: " + wifiAvailable + ", ethAvailable: " + ethernetAvailable + ", wifiConnected: " + root.wifiConnected + " (" + activeWifiIf + "), ethConnected: " + root.ethernetConnected + " (" + activeEthIf + ")");

        ethList.sort((a, b) => (a.connected !== b.connected) ? (a.connected ? -1 : 1) : a.ifname.localeCompare(b.ifname));
        root.ethernetInterfaces = ethList;

        root.activeEthernetIf = activeEthIf;
        root.activeEthernetDetails = newActiveEthernetDetails;
        root.activeEthernetDetailsTimestamp = Date.now();
        root.ethernetDetailsLoading = false;

        root.activeWifiIf = activeWifiIf;
        root.activeWifiDetails = newActiveWifiDetails;
        root.activeWifiDetailsTimestamp = Date.now();
        root.wifiDetailsLoading = false;
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Network", "nmcli device show stderr:", text.trim());
        }
        root.ethernetDetailsLoading = false;
        root.wifiDetailsLoading = false;
      }
    }
  }

  // Process to check the internet connectivity of the connected network
  Process {
    id: connectivityCheckProcess
    running: false
    command: ["nmcli", "networking", "connectivity", "check"]
    stdout: StdioCollector {
      onStreamFinished: {
        const r = text.trim();
        if (!r) {
          return;
        }
        root._networkConnectivity = (r === "none") ? "unknown" : r;
        root._internetConnectivity = (r === "full");
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

  // Helper process to get existing profiles
  Process {
    id: profileCheckProcess
    running: false
    command: ["nmcli", "-t", "-f", "NAME", "connection", "show"]

    stdout: StdioCollector {
      onStreamFinished: {
        var profiles = {};
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
          var l = lines[i];
          if (l && l.trim()) {
            profiles[l.trim()] = true;
          }
        }
        root.existingProfiles = profiles;
        scanProcess.running = true;
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim()) {
          Logger.w("Network", "Profile check stderr:", text.trim());
          if (root.scanningActive) {
            if (root.scanPending) {
              root.scanPending = false;
              delayedScanTimer.interval = 3000;
            } else {
              delayedScanTimer.interval = 5000;
            }
            delayedScanTimer.restart();
          }
        }
      }
    }
  }

  // Scan for Wi-Fi networks
  Process {
    id: scanProcess
    running: false
    command: ["nmcli", "-t", "-f", "SSID,SECURITY,SIGNAL,IN-USE", "device", "wifi", "list", "--rescan", "yes"]

    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n");
        const networksMap = {};

        for (let i = 0; i < lines.length; i++) {
          const line = lines[i].trim();
          if (!line) {
            continue;
          }

          // Parse SSID:SECURITY:SIGNAL:IN-USE
          const parts = line.split(":");
          if (parts.length < 4) {
            continue;
          }

          const inUse = parts[parts.length - 1];
          const signal = parseInt(parts[parts.length - 2]) || 0;
          let security = parts[parts.length - 3];
          if (security) {
            security = security.replace("WPA2 WPA3", "WPA2/WPA3").replace("WPA1 WPA2", "WPA1/WPA2");
          }
          const ssid = parts.slice(0, parts.length - 3).join(":");

          if (ssid) {
            const isConnected = (inUse === "*");
            if (!networksMap[ssid]) {
              networksMap[ssid] = {
                "ssid": ssid,
                "security": security || "--",
                "signal": signal,
                "connected": isConnected,
                "existing": !!root.existingProfiles[ssid]
              };
            } else {
              if (isConnected) {
                networksMap[ssid].connected = true;
                networksMap[ssid].signal = signal;
                connectivityCheckProcess.running = true;
              } else if (!networksMap[ssid].connected && signal > networksMap[ssid].signal) {
                networksMap[ssid].signal = signal;
              }
            }
          }
        }

        // Logging & Diffing
        const oldSSIDs = Object.keys(root.networks);
        const newSSIDs = Object.keys(networksMap);
        const newNetworks = newSSIDs.filter(s => oldSSIDs.indexOf(s) === -1);
        const lostNetworks = oldSSIDs.filter(s => newSSIDs.indexOf(s) === -1);

        // Always update networks, this makes more reflective of state/signal.
        root.networks = networksMap;

        if (newNetworks.length > 0 || lostNetworks.length > 0) {
          if (newNetworks.length > 0) {
            Logger.d("Network", "New Wi-Fi network appeared:", newNetworks.join(", "));
          }
          if (lostNetworks.length > 0) {
            Logger.d("Network", "Wi-Fi network disappeared:", lostNetworks.join(", "));
          }
          Logger.d("Network", "Total Wi-Fi networks:", Object.keys(networksMap).length);
        }

        if (Object.values(networksMap).some(n => n.connected)) {
          root.refreshActiveWifiDetails();
        }

        if (root.scanPending) {
          root.scanPending = false;
          delayedScanTimer.interval = 100;
          delayedScanTimer.restart();
        }
        root.scanningActive = false;
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.w("Network", "Scan error: " + text);

          // Even on error, if a scan was pending, try again
          if (root.scanPending) {
            root.scanPending = false;
            delayedScanTimer.interval = 3000;
          } else if (root.scanningActive) {
            delayedScanTimer.interval = 10000;
          }
          delayedScanTimer.restart();
        }
        root.scanningActive = false;
      }
    }
  }

  // Connect to Wi-Fi network
  Process {
    id: connectProcess
    property string mode: "new" // "saved", "new", or "manual"
    property string ssid: ""
    property string password: ""
    property bool isHidden: false
    // Manual properties
    property string securityKey: ""
    property string identity: ""
    property string eap: "peap"
    property string phase2: "mschapv2"
    property string anonIdentity: ""
    property string caCert: ""
    running: false

    command: {
      if (mode === "saved") {
        return ["nmcli", "-t", "connection", "up", "id", ssid];
      } else if (mode === "manual") {
        const nmArgs = ["connection", "add", "type", "wifi", "con-name", ssid, "ssid", ssid, "--", "802-11-wireless.hidden", isHidden ? "yes" : "no"];

        if (securityKey === "wpa-psk" || securityKey === "wpa2-psk") {
          nmArgs.push("wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.psk", password);
        } else if (securityKey === "sae") {
          nmArgs.push("wifi-sec.key-mgmt", "sae", "wifi-sec.psk", password);
        } else if (securityKey === "wep") {
          nmArgs.push("wifi-sec.key-mgmt", "none", "wifi-sec.wep-key0", password);
        } else if (securityKey && securityKey.indexOf("-eap") !== -1) {
          nmArgs.push("wifi-sec.key-mgmt", "wpa-eap", "802-1x.eap", eap, "802-1x.phase2-auth", phase2, "802-1x.identity", identity, "802-1x.password", password);
          if (anonIdentity) {
            nmArgs.push("802-1x.anonymous-identity", anonIdentity);
          }
          if (caCert) {
            nmArgs.push("802-1x.ca-cert", caCert);
          }
        }

        const script = `
        SSID="$1"
        shift
        # Find existing profile by Name and Type
        UUID=$(nmcli -t -f NAME,UUID,TYPE connection show | awk -F: -v target="$SSID" '$1 == target && $3 == "802-11-wireless" { print $2; exit }')

        if [ -n "$UUID" ]; then
            echo "Using existing profile: $UUID"
            nmcli connection delete uuid "$UUID" 2>/dev/null || true
        else
            echo "Creating new profile for $SSID"
        fi
        nmcli "$@"
        nmcli connection up id "$SSID"
      `;

        return ["sh", "-c", script, "--", ssid].concat(nmArgs);
      } else {
        var cmd = ["nmcli", "-t", "device", "wifi", "connect", ssid];
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
        const output = text.trim();
        if (!output || (output.indexOf("successfully activated") === -1 && output.indexOf("Connection successfully") === -1)) {
          return;
        }

        root.wifiConnected = true;
        root.updateNetworkStatus(connectProcess.ssid, true);
        root.refreshActiveWifiDetails(); // This needs wifiConnected true.

        root.connecting = false;
        root.connectingTo = "";
        Logger.i("Network", "Connected to network: '" + connectProcess.ssid + "' (" + connectProcess.mode + ")");
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.wifi.connected", {
                                                                  "ssid": connectProcess.ssid
                                                                }), root.getIcon(false));

        delayedScanTimer.interval = 5000;
        delayedScanTimer.restart();
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          root.connecting = false;
          root.connectingTo = "";

          if (text.indexOf("Secrets were required") !== -1 || text.indexOf("no secrets provided") !== -1) {
            root.lastError = I18n.tr("toast.wifi.incorrect-password");
            forget(connectProcess.ssid);
          } else if (text.indexOf("No network with SSID") !== -1) {
            root.lastError = I18n.tr("toast.wifi.network-not-found");
          } else if (text.indexOf("Timeout") !== -1) {
            root.lastError = I18n.tr("toast.wifi.connection-timeout");
          } else {
            root.lastError = I18n.tr("toast.wifi.connection-failed");
          }

          Logger.w("Network", "Connect error (" + connectProcess.mode + "): " + text);
          ToastService.showWarning(I18n.tr("common.wifi"), root.lastError || I18n.tr("toast.wifi.connection-failed"), "wifi-exclamation");
          wifiConnected = false;
        }
      }
    }
  }

  // Disconnect from Wi-Fi network
  Process {
    id: disconnectProcess
    property string ssid: ""
    running: false
    command: ["nmcli", "connection", "down", "id", ssid]

    stdout: StdioCollector {
      onStreamFinished: {
        Logger.i("Network", "Disconnected from network: '" + disconnectProcess.ssid + "'");
        root.wifiConnected = false;
        ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.wifi.disconnected", {
                                                                  "ssid": disconnectProcess.ssid
                                                                }), "wifi-off");

        // Immediately update UI on successful disconnect
        root.updateNetworkStatus(disconnectProcess.ssid, false);
        root.disconnectingFrom = "";

        // Do a scan to refresh the list
        delayedScanTimer.interval = 3000;
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

  // Forget given Wi-Fi network
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

        # Find existing profile by Name and Type
        UUID=$(nmcli -t -f NAME,UUID,TYPE connection show | awk -F: -v target="$ssid" '$1 == target && $3 == "802-11-wireless" { print $2; exit }')

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

        // Update existing status immediately
        let nets = root.networks;
        if (nets[forgetProcess.ssid]) {
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

  // Listen to NetworkManager events in real-time (roaming, auto-connect)  -- ~9mb Memory usage.
  Process {
    id: networkMonitorProcess
    running: ProgramCheckerService.nmcliAvailable
    command: ["nmcli", "-t", "monitor"]
    environment: ({
                    "LC_ALL": "C"
                  })
    stdout: SplitParser {
      onRead: data => {
        if (data.endsWith(": connected") || data.endsWith(": disconnected")) {
          Logger.d("Network", "State changed: " + data);
          deviceStatusProcess.running = true;
        }
      }
    }
  }
}
