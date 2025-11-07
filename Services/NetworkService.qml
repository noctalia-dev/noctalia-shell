pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services

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
  property string internetConnectivity: "unknown"

  property bool ignoreScanResults: false
  property bool scanPending: false

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
      cacheAdapter.knownNetworks = ({})
      cacheAdapter.lastConnected = ""
    }
  }

  Connections {
    target: Settings.data.network
    function onWifiEnabledChanged() {
      if (Settings.data.network.wifiEnabled) {
        if (!BluetoothService.airplaneModeToggled) {
          ToastService.showNotice(I18n.tr("wifi.panel.title"), I18n.tr("toast.wifi.enabled"), "wifi")
        }
        // Perform a scan to update the UI
        delayedScanTimer.interval = 3000
        delayedScanTimer.restart()
      } else {
        if (!BluetoothService.airplaneModeToggled) {
          ToastService.showNotice(I18n.tr("wifi.panel.title"), I18n.tr("toast.wifi.disabled"), "wifi-off")
        }
        // Clear networks so the widget icon changes
        root.networks = ({})
      }
    }
  }

  Component.onCompleted: {
    Logger.i("Network", "Service started")
    syncWifiState()
    scan()
  }

  // Save cache with debounce
  Timer {
    id: saveDebounce
    interval: 1000
    onTriggered: cacheFileView.writeAdapter()
  }

  function saveCache() {
    saveDebounce.restart()
  }

  // Delayed scan timer
  Timer {
    id: delayedScanTimer
    interval: 7000
    onTriggered: scan()
  }

  // Ethernet check timer
  // Always running every 30s
  Timer {
    id: ethernetCheckTimer
    interval: 30000
    running: true
    repeat: true
    onTriggered: ethernetStateProcess.running = true
  }

  // Internet connectivity check timer
  // Always running every 10s
  Timer {
    id: connectivityCheckTimer
    interval: 10000
    running: true
    repeat: true
    onTriggered: connectivityCheckProcess.running = true
  }

  // Core functions
  function syncWifiState() {
    wifiStateProcess.running = true
  }

  function setWifiEnabled(enabled) {
    Settings.data.network.wifiEnabled = enabled
    wifiStateEnableProcess.running = true
  }

  function scan() {
    if (!Settings.data.network.wifiEnabled)
      return

    if (scanning) {
      // Mark current scan results to be ignored and schedule a new scan
      Logger.d("Network", "Scan already in progress, will ignore results and rescan")
      ignoreScanResults = true
      scanPending = true
      return
    }

    scanning = true
    lastError = ""
    ignoreScanResults = false

    // Get existing profiles first, then scan
    profileCheckProcess.running = true
    Logger.d("Network", "Wi-Fi scan in progress...")
  }

  function connect(ssid, password = "") {
    if (connecting)
      return

    connecting = true
    connectingTo = ssid
    lastError = ""

    // Check if we have a saved connection
    if (networks[ssid]?.existing || cachedNetworks[ssid]) {
      connectProcess.mode = "saved"
      connectProcess.ssid = ssid
      connectProcess.password = ""
    } else {
      connectProcess.mode = "new"
      connectProcess.ssid = ssid
      connectProcess.password = password
    }

    connectProcess.running = true
  }

  function disconnect(ssid) {
    disconnectingFrom = ssid
    disconnectProcess.ssid = ssid
    disconnectProcess.running = true
  }

  function forget(ssid) {
    forgettingNetwork = ssid

    // Remove from cache
    let known = cacheAdapter.knownNetworks
    delete known[ssid]
    cacheAdapter.knownNetworks = known

    if (cacheAdapter.lastConnected === ssid) {
      cacheAdapter.lastConnected = ""
    }

    saveCache()

    // Remove from system
    forgetProcess.ssid = ssid
    forgetProcess.running = true
  }

  // Helper function to immediately update network status
  function updateNetworkStatus(ssid, connected) {
    let nets = networks

    // Update all networks connected status
    for (let key in nets) {
      if (nets[key].connected && key !== ssid) {
        nets[key].connected = false
      }
    }

    // Update the target network if it exists
    if (nets[ssid]) {
      nets[ssid].connected = connected
      nets[ssid].existing = true
      nets[ssid].cached = true
    } else if (connected) {
      // Create a temporary entry if network doesn't exist yet
      nets[ssid] = {
        "ssid": ssid,
        "security": "--",
        "signal": 100,
        "connected": true,
        "existing": true,
        "cached": true
      }
    }

    // Trigger property change notification
    networks = ({})
    networks = nets
  }

  // Helper functions
  function signalIcon(signal, isConnected = false) {
    if (isConnected && (root.internetConnectivity === "limited" || root.internetConnectivity === "portal"))
      return "world-off"
    if (signal >= 80)
      return "wifi"
    if (signal >= 50)
      return "wifi-2"
    if (signal >= 20)
      return "wifi-1"
    return "wifi-0"
  }

  function isSecured(security) {
    return security && security !== "--" && security.trim() !== ""
  }

  // Processes
  Process {
    id: ethernetStateProcess
    running: true
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device"]

    stdout: StdioCollector {
      onStreamFinished: {
        const connected = text.split("\n").some(line => {
                                                  const parts = line.split(":")
                                                  return parts[1] === "ethernet" && parts[2] === "connected"
                                                })
        if (root.ethernetConnected !== connected) {
          root.ethernetConnected = connected
          Logger.d("Network", "Ethernet connected:", root.ethernetConnected)
        }
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
        const enabled = text.trim() === "enabled"
        Logger.d("Network", "Wi-Fi adapter was detect as enabled:", enabled)
        if (Settings.data.network.wifiEnabled !== enabled) {
          Settings.data.network.wifiEnabled = enabled
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
        Logger.i("Network", "Wi-Fi state change command executed.")
        // Re-check the state to ensure it's in sync
        syncWifiState()
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.w("Network", "Error changing Wi-Fi state: " + text)
        }
      }
    }
  }

  // Process to check the internet connectivity
  Process {
    id: connectivityCheckProcess
    running: false
    command: ["nmcli", "networking", "connectivity"]

    stdout: StdioCollector {
      onStreamFinished: {
        const result = text.trim()
        if (result && result !== root.internetConnectivity) {
          root.internetConnectivity = result
          Logger.i("Network", "Internet connectivity:", result)

          if (result === "limited" || result === "portal") {
            ToastService.showWarning(cachedLastConnected, I18n.tr("toast.internet.limited"))
          } else {
            scan()
          }
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.w("Network", "Connectivity check error: " + text)
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
        if (root.ignoreScanResults) {
          Logger.d("Network", "Ignoring profile check results (new scan requested)")
          root.scanning = false

          // Check if we need to start a new scan
          if (root.scanPending) {
            root.scanPending = false
            delayedScanTimer.interval = 100
            delayedScanTimer.restart()
          }
          return
        }

        const profiles = {}
        const lines = text.split("\n").filter(l => l.trim())
        for (const line of lines) {
          profiles[line.trim()] = true
        }
        scanProcess.existingProfiles = profiles
        scanProcess.running = true
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
          Logger.d("Network", "Ignoring scan results (new scan requested)")
          root.scanning = false

          // Check if we need to start a new scan
          if (root.scanPending) {
            root.scanPending = false
            delayedScanTimer.interval = 100
            delayedScanTimer.restart()
          }
          return
        }

        // Process the scan results as before...
        const lines = text.split("\n")
        const networksMap = {}

        for (var i = 0; i < lines.length; ++i) {
          const line = lines[i].trim()
          if (!line)
          continue

          // Parse from the end to handle SSIDs with colons
          // Format is SSID:SECURITY:SIGNAL:IN-USE
          // We know the last 3 fields, so everything else is SSID
          const lastColonIdx = line.lastIndexOf(":")
          if (lastColonIdx === -1) {
            Logger.w("Network", "Malformed nmcli output line:", line)
            continue
          }

          const inUse = line.substring(lastColonIdx + 1)
          const remainingLine = line.substring(0, lastColonIdx)

          const secondLastColonIdx = remainingLine.lastIndexOf(":")
          if (secondLastColonIdx === -1) {
            Logger.w("Network", "Malformed nmcli output line:", line)
            continue
          }

          const signal = remainingLine.substring(secondLastColonIdx + 1)
          const remainingLine2 = remainingLine.substring(0, secondLastColonIdx)

          const thirdLastColonIdx = remainingLine2.lastIndexOf(":")
          if (thirdLastColonIdx === -1) {
            Logger.w("Network", "Malformed nmcli output line:", line)
            continue
          }

          const security = remainingLine2.substring(thirdLastColonIdx + 1)
          const ssid = remainingLine2.substring(0, thirdLastColonIdx)

          if (ssid) {
            const signalInt = parseInt(signal) || 0
            const connected = inUse === "*"

            // Track connected network in cache
            if (connected && cacheAdapter.lastConnected !== ssid) {
              cacheAdapter.lastConnected = ssid
              saveCache()
            }

            if (!networksMap[ssid]) {
              networksMap[ssid] = {
                "ssid": ssid,
                "security": security || "--",
                "signal": signalInt,
                "connected": connected,
                "existing": ssid in scanProcess.existingProfiles,
                "cached": ssid in cacheAdapter.knownNetworks
              }
            } else {
              // Keep the best signal for duplicate SSIDs
              const existingNet = networksMap[ssid]
              if (connected) {
                existingNet.connected = true
              }
              if (signalInt > existingNet.signal) {
                existingNet.signal = signalInt
                existingNet.security = security || "--"
              }
            }
          }
        }

        // Logging
        const oldSSIDs = Object.keys(root.networks)
        const newSSIDs = Object.keys(networksMap)
        const newNetworks = newSSIDs.filter(ssid => !oldSSIDs.includes(ssid))
        const lostNetworks = oldSSIDs.filter(ssid => !newSSIDs.includes(ssid))

        if (newNetworks.length > 0 || lostNetworks.length > 0) {
          if (newNetworks.length > 0) {
            Logger.d("Network", "New Wi-Fi SSID discovered:", newNetworks.join(", "))
          }
          if (lostNetworks.length > 0) {
            Logger.d("Network", "Wi-Fi SSID disappeared:", lostNetworks.join(", "))
          }
          Logger.d("Network", "Total Wi-Fi SSIDs:", Object.keys(networksMap).length)
        }

        Logger.d("Network", "Wi-Fi scan completed")
        root.networks = networksMap
        root.scanning = false

        // Check if we need to start a new scan
        if (root.scanPending) {
          root.scanPending = false
          delayedScanTimer.interval = 100
          delayedScanTimer.restart()
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.scanning = false
        if (text.trim()) {
          Logger.w("Network", "Scan error: " + text)

          // If scan fails, retry
          delayedScanTimer.interval = 5000
          delayedScanTimer.restart()
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
        return ["nmcli", "connection", "up", "id", ssid]
      } else {
        const cmd = ["nmcli", "device", "wifi", "connect", ssid]
        if (password) {
          cmd.push("password", password)
        }
        return cmd
      }
    }
    environment: {
      "LC_ALL": "C"
    }

    stdout: StdioCollector {
      onStreamFinished: {
        // Check if the output actually indicates success
        // nmcli outputs "Device '...' successfully activated" or "Connection successfully activated"
        // on success. Empty output or other messages indicate failure.
        const output = text.trim()

        if (!output || (!output.includes("successfully activated") && !output.includes("Connection successfully"))) {
          // No success message - likely an error occurred
          // Don't update anything, let stderr handler deal with it
          return
        }

        // Success - update cache
        let known = cacheAdapter.knownNetworks
        known[connectProcess.ssid] = {
          "profileName": connectProcess.ssid,
          "lastConnected": Date.now()
        }
        cacheAdapter.knownNetworks = known
        cacheAdapter.lastConnected = connectProcess.ssid
        saveCache()

        // Immediately update the UI before scanning
        root.updateNetworkStatus(connectProcess.ssid, true)

        root.connecting = false
        root.connectingTo = ""
        Logger.i("Network", `Connected to network: '${connectProcess.ssid}'`)
        ToastService.showNotice(I18n.tr("wifi.panel.title"), I18n.tr("toast.wifi.connected", {
                                                                       "ssid": connectProcess.ssid
                                                                     }), "wifi")

        // Still do a scan to get accurate signal and security info
        delayedScanTimer.interval = 5000
        delayedScanTimer.restart()
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.connecting = false
        root.connectingTo = ""

        if (text.trim()) {
          // Parse common errors
          if (text.includes("Secrets were required") || text.includes("no secrets provided")) {
            root.lastError = "Incorrect password"
            forget(connectProcess.ssid)
          } else if (text.includes("No network with SSID")) {
            root.lastError = "Network not found"
          } else if (text.includes("Timeout")) {
            root.lastError = "Connection timeout"
          } else {
            root.lastError = text.split("\n")[0].trim()
          }

          Logger.w("Network", "Connect error: " + text)
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
        Logger.i("Network", `Disconnected from network: '${disconnectProcess.ssid}'`)
        ToastService.showNotice(I18n.tr("wifi.panel.title"), I18n.tr("toast.wifi.disconnected", {
                                                                       "ssid": disconnectProcess.ssid
                                                                     }), "wifi-off")

        // Immediately update UI on successful disconnect
        root.updateNetworkStatus(disconnectProcess.ssid, false)
        root.disconnectingFrom = ""

        // Do a scan to refresh the list
        delayedScanTimer.interval = 1000
        delayedScanTimer.restart()
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.disconnectingFrom = ""
        if (text.trim()) {
          Logger.w("Network", "Disconnect error: " + text)
        }
        // Still trigger a scan even on error
        delayedScanTimer.interval = 5000
        delayedScanTimer.restart()
      }
    }
  }

  Process {
    id: forgetProcess
    property string ssid: ""
    running: false

    // Try multiple common profile name patterns
    command: ["sh", "-c", `
      ssid="$1"
      deleted=false

      # Try exact SSID match first
      if nmcli connection delete id "$ssid" 2>/dev/null; then
      echo "Deleted profile: $ssid"
      deleted=true
      fi

      # Try "Auto <SSID>" pattern
      if nmcli connection delete id "Auto $ssid" 2>/dev/null; then
      echo "Deleted profile: Auto $ssid"
      deleted=true
      fi

      # Try "<SSID> 1", "<SSID> 2", etc. patterns
      for i in 1 2 3; do
      if nmcli connection delete id "$ssid $i" 2>/dev/null; then
      echo "Deleted profile: $ssid $i"
      deleted=true
      fi
      done

      if [ "$deleted" = "false" ]; then
      echo "No profiles found for SSID: $ssid"
      fi
      `, "--", ssid]

    stdout: StdioCollector {
      onStreamFinished: {
        Logger.i("Network", `Forget network: "${forgetProcess.ssid}"`)
        Logger.d("Network", text.trim().replace(/[\r\n]/g, " "))

        // Update both cached and existing status immediately
        let nets = root.networks
        if (nets[forgetProcess.ssid]) {
          nets[forgetProcess.ssid].cached = false
          nets[forgetProcess.ssid].existing = false
          // Trigger property change
          root.networks = ({})
          root.networks = nets
        }

        root.forgettingNetwork = ""

        // Scan to verify the profile is gone
        delayedScanTimer.interval = 5000
        delayedScanTimer.restart()
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.forgettingNetwork = ""
        if (text.trim() && !text.includes("No profiles found")) {
          Logger.w("Network", "Forget error: " + text)
        }
        // Still Trigger a scan even on error
        delayedScanTimer.interval = 5000
        delayedScanTimer.restart()
      }
    }
  }
}
