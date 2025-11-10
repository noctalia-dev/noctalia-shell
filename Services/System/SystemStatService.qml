pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Configuration
  property int sleepDuration: 3000

  // Public values
  property real cpuUsage: 0
  property real cpuTemp: 0
  property real memGb: 0
  property real memPercent: 0
  property var diskPercents: ({})
  property real rxSpeed: 0
  property real txSpeed: 0

  // Internal state for CPU calculation
  property var prevCpuStats: null

  // Internal state for network speed calculation
  // Previous Bytes need to be stored as 'real' as they represent the total of bytes transfered
  // since the computer started, so their value will easily overlfow a 32bit int.
  property real prevRxBytes: 0
  property real prevTxBytes: 0
  property real prevTime: 0

  // Cpu temperature is the most complex
  readonly property var supportedTempCpuSensorNames: ["coretemp", "k10temp", "zenpower"]
  property string cpuTempSensorName: ""
  property string cpuTempHwmonPath: ""
  // For Intel coretemp averaging of all cores/sensors
  property var intelTempValues: []
  property int intelTempFilesChecked: 0
  property int intelTempMaxFiles: 20 // Will test up to temp20_input

  // --------------------------------------------
  Component.onCompleted: {
    Logger.i("SystemStat", "Service started with interval:", root.sleepDuration, "ms")

    // Kickoff the cpu name detection for temperature
    cpuTempNameReader.checkNext()
  }

  // --------------------------------------------
  // Timer for periodic updates
  Timer {
    id: updateTimer
    interval: root.sleepDuration
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      // Trigger all direct system files reads
      memInfoFile.reload()
      cpuStatFile.reload()
      netDevFile.reload()

      // Run df (disk free) one time
      dfProcess.running = true

      updateCpuTemperature()
    }
  }

  // --------------------------------------------
  // FileView components for reading system files
  FileView {
    id: memInfoFile
    path: "/proc/meminfo"
    onLoaded: parseMemoryInfo(text())
  }

  FileView {
    id: cpuStatFile
    path: "/proc/stat"
    onLoaded: calculateCpuUsage(text())
  }

  FileView {
    id: netDevFile
    path: "/proc/net/dev"
    onLoaded: calculateNetworkSpeed(text())
  }

  // --------------------------------------------
  // Process to fetch disk usage in percent
  // Uses 'df' aka 'disk free'
  Process {
    id: dfProcess
    command: ["df", "--output=target,pcent"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split('\n')
        const newPercents = {}
        // Start from line 1 (skip header)
        for (var i = 1; i < lines.length; i++) {
          const parts = lines[i].trim().split(/\s+/)
          if (parts.length >= 2) {
            const target = parts[0]
            const percent = parseInt(parts[1].replace(/[^0-9]/g, '')) || 0
            newPercents[target] = percent
          }
        }
        root.diskPercents = newPercents
      }
    }
  }

  // --------------------------------------------
  // --------------------------------------------
  // CPU Temperature
  // It's more complex.
  // ----
  // #1 - Find a common cpu sensor name ie: "coretemp", "k10temp", "zenpower"
  FileView {
    id: cpuTempNameReader
    property int currentIndex: 0
    printErrors: false

    function checkNext() {
      if (currentIndex >= 16) {
        // Check up to hwmon10
        Logger.w("No supported temperature sensor found")
        return
      }

      //Logger.i("SystemStat", "---- Probing: hwmon", currentIndex)
      cpuTempNameReader.path = `/sys/class/hwmon/hwmon${currentIndex}/name`
      cpuTempNameReader.reload()
    }

    onLoaded: {
      const name = text().trim()
      if (root.supportedTempCpuSensorNames.includes(name)) {
        root.cpuTempSensorName = name
        root.cpuTempHwmonPath = `/sys/class/hwmon/hwmon${currentIndex}`
        Logger.i("SystemStat", `Found ${root.cpuTempSensorName} CPU thermal sensor at ${root.cpuTempHwmonPath}`)
      } else {
        currentIndex++
        Qt.callLater(() => {
                       // Qt.callLater is mandatory
                       checkNext()
                     })
      }
    }

    onLoadFailed: function (error) {
      currentIndex++
      Qt.callLater(() => {
                     // Qt.callLater is mandatory
                     checkNext()
                   })
    }
  }

  // ----
  // #2 - Read sensor value
  FileView {
    id: cpuTempReader
    printErrors: false

    onLoaded: {
      const data = text().trim()
      if (root.cpuTempSensorName === "coretemp") {
        // For Intel, collect all temperature values
        const temp = parseInt(data) / 1000.0
        //console.log(temp, cpuTempReader.path)
        root.intelTempValues.push(temp)
        Qt.callLater(() => {
                       // Qt.callLater is mandatory
                       checkNextIntelTemp()
                     })
      } else {
        // For AMD sensors (k10temp and zenpower), directly set the temperature
        root.cpuTemp = Math.round(parseInt(data) / 1000.0)
      }
    }
    onLoadFailed: function (error) {
      Qt.callLater(() => {
                     // Qt.callLater is mandatory
                     checkNextIntelTemp()
                   })
    }
  }

  // -------------------------------------------------------
  // -------------------------------------------------------
  // Parse memory info from /proc/meminfo
  function parseMemoryInfo(text) {
    if (!text)
      return

    const lines = text.split('\n')
    let memTotal = 0
    let memAvailable = 0

    for (const line of lines) {
      if (line.startsWith('MemTotal:')) {
        memTotal = parseInt(line.split(/\s+/)[1]) || 0
      } else if (line.startsWith('MemAvailable:')) {
        memAvailable = parseInt(line.split(/\s+/)[1]) || 0
      }
    }

    if (memTotal > 0) {
      const usageKb = memTotal - memAvailable
      root.memGb = (usageKb / 1048576).toFixed(1) // 1024*1024 = 1048576
      root.memPercent = Math.round((usageKb / memTotal) * 100)
    }
  }

  // -------------------------------------------------------
  // Calculate CPU usage from /proc/stat
  function calculateCpuUsage(text) {
    if (!text)
      return

    const lines = text.split('\n')
    const cpuLine = lines[0]

    // First line is total CPU
    if (!cpuLine.startsWith('cpu '))
      return

    const parts = cpuLine.split(/\s+/)
    const stats = {
      "user": parseInt(parts[1]) || 0,
      "nice": parseInt(parts[2]) || 0,
      "system": parseInt(parts[3]) || 0,
      "idle": parseInt(parts[4]) || 0,
      "iowait": parseInt(parts[5]) || 0,
      "irq": parseInt(parts[6]) || 0,
      "softirq": parseInt(parts[7]) || 0,
      "steal": parseInt(parts[8]) || 0,
      "guest": parseInt(parts[9]) || 0,
      "guestNice": parseInt(parts[10]) || 0
    }
    const totalIdle = stats.idle + stats.iowait
    const total = Object.values(stats).reduce((sum, val) => sum + val, 0)

    if (root.prevCpuStats) {
      const prevTotalIdle = root.prevCpuStats.idle + root.prevCpuStats.iowait
      const prevTotal = Object.values(root.prevCpuStats).reduce((sum, val) => sum + val, 0)

      const diffTotal = total - prevTotal
      const diffIdle = totalIdle - prevTotalIdle

      if (diffTotal > 0) {
        root.cpuUsage = (((diffTotal - diffIdle) / diffTotal) * 100).toFixed(1)
      }
    }

    root.prevCpuStats = stats
  }

  // -------------------------------------------------------
  // Calculate RX and TX speed from /proc/net/dev
  // Average speed of all interfaces excepted 'lo'
  function calculateNetworkSpeed(text) {
    if (!text) {
      return
    }

    const currentTime = Date.now() / 1000
    const lines = text.split('\n')

    let totalRx = 0
    let totalTx = 0

    for (var i = 2; i < lines.length; i++) {
      const line = lines[i].trim()
      if (!line) {
        continue
      }

      const colonIndex = line.indexOf(':')
      if (colonIndex === -1) {
        continue
      }

      const iface = line.substring(0, colonIndex).trim()
      if (iface === 'lo') {
        continue
      }

      const statsLine = line.substring(colonIndex + 1).trim()
      const stats = statsLine.split(/\s+/)

      const rxBytes = parseInt(stats[0], 10) || 0
      const txBytes = parseInt(stats[8], 10) || 0

      totalRx += rxBytes
      totalTx += txBytes
    }

    // Compute only if we have a previous run to compare to.
    if (root.prevTime > 0) {
      const timeDiff = currentTime - root.prevTime

      // Avoid division by zero if time hasn't passed.
      if (timeDiff > 0) {
        let rxDiff = totalRx - root.prevRxBytes
        let txDiff = totalTx - root.prevTxBytes

        // Handle counter resets (e.g., WiFi reconnect), which would cause a negative value.
        if (rxDiff < 0) {
          rxDiff = 0
        }
        if (txDiff < 0) {
          txDiff = 0
        }

        root.rxSpeed = Math.round(rxDiff / timeDiff) // Speed in Bytes/s
        root.txSpeed = Math.round(txDiff / timeDiff)
      }
    }

    root.prevRxBytes = totalRx
    root.prevTxBytes = totalTx
    root.prevTime = currentTime
  }

  // -------------------------------------------------------
  // Helper function to format network speeds
  function formatSpeed(bytesPerSecond) {
    if (bytesPerSecond < 1024 * 1024) {
      const kb = bytesPerSecond / 1024
      if (kb < 10) {
        return kb.toFixed(1) + "KB"
      } else {
        return Math.round(kb) + "KB"
      }
    } else if (bytesPerSecond < 1024 * 1024 * 1024) {
      return (bytesPerSecond / (1024 * 1024)).toFixed(1) + "MB"
    } else {
      return (bytesPerSecond / (1024 * 1024 * 1024)).toFixed(1) + "GB"
    }
  }

  // -------------------------------------------------------
  // Compact speed formatter for vertical bar display
  function formatCompactSpeed(bytesPerSecond) {
    if (!bytesPerSecond || bytesPerSecond <= 0)
      return "0"
    const units = ["", "K", "M", "G"]
    let value = bytesPerSecond
    let unitIndex = 0
    while (value >= 1024 && unitIndex < units.length - 1) {
      value = value / 1024.0
      unitIndex++
    }
    // Promote at ~100 of current unit (e.g., 100k -> ~0.1M shown as 0.1M or 0M if rounded)
    if (unitIndex < units.length - 1 && value >= 100) {
      value = value / 1024.0
      unitIndex++
    }
    const display = Math.round(value).toString()
    return display + units[unitIndex]
  }

  // -------------------------------------------------------
  // Function to start fetching and computing the cpu temperature
  function updateCpuTemperature() {
    // For AMD sensors (k10temp and zenpower), only use Tctl sensor
    // temp1_input corresponds to Tctl (Temperature Control) on these sensors
    if (root.cpuTempSensorName === "k10temp" || root.cpuTempSensorName === "zenpower") {
      cpuTempReader.path = `${root.cpuTempHwmonPath}/temp1_input`
      cpuTempReader.reload()
    } // For Intel coretemp, start averaging all available sensors/cores
    else if (root.cpuTempSensorName === "coretemp") {
      root.intelTempValues = []
      root.intelTempFilesChecked = 0
      checkNextIntelTemp()
    }
  }

  // -------------------------------------------------------
  // Function to check next Intel temperature sensor
  function checkNextIntelTemp() {
    if (root.intelTempFilesChecked >= root.intelTempMaxFiles) {
      // Calculate average of all found temperatures
      if (root.intelTempValues.length > 0) {
        let sum = 0
        for (var i = 0; i < root.intelTempValues.length; i++) {
          sum += root.intelTempValues[i]
        }
        root.cpuTemp = Math.round(sum / root.intelTempValues.length)
        //Logger.i("SystemStat", `Averaged ${root.intelTempValues.length} CPU thermal sensors: ${root.cpuTemp}°C`)
      } else {
        Logger.w("SystemStat", "No temperature sensors found for coretemp")
        root.cpuTemp = 0
      }
      return
    }

    // Check next temperature file
    root.intelTempFilesChecked++
    cpuTempReader.path = `${root.cpuTempHwmonPath}/temp${root.intelTempFilesChecked}_input`
    cpuTempReader.reload()
  }
}
