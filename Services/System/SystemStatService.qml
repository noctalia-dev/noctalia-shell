pragma Singleton
import Qt.labs.folderlistmodel

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Configuration
  readonly property int minimumIntervalMs: 250
  readonly property int defaultIntervalMs: 3000

  function normalizeInterval(value) {
    return Math.max(minimumIntervalMs, value || defaultIntervalMs);
  }

  // Public values
  property real cpuUsage: 0
  property real cpuTemp: 0
  property real gpuTemp: 0
  property bool gpuAvailable: false
  property string gpuType: "" // "amd", "intel", "nvidia"
  property real memGb: 0
  property real memPercent: 0
  property var diskPercents: ({})
  property var diskUsedGb: ({}) // Used space in GB per mount point
  property var diskSizeGb: ({}) // Total size in GB per mount point
  property real rxSpeed: 0
  property real txSpeed: 0
  property real zfsArcSizeKb: 0 // ZFS ARC cache size in KB
  property real zfsArcCminKb: 0 // ZFS ARC minimum (non-reclaimable) size in KB
  property real loadAvg1: 0
  property real loadAvg5: 0
  property real loadAvg15: 0
  property int nproc: 0 // Number of cpu cores

  // Network max speed tracking (learned over time, cached for 7 days)
  readonly property real rxMaxSpeed: {
    const peaks = networkStatsAdapter.rxPeaks || [];
    return peaks.length > 0 ? Math.max(...peaks.map(p => p.speed)) : 0;
  }
  readonly property real txMaxSpeed: {
    const peaks = networkStatsAdapter.txPeaks || [];
    return peaks.length > 0 ? Math.max(...peaks.map(p => p.speed)) : 0;
  }

  // Ready-to-use ratios based on learned maximums (0..1 range)
  readonly property real rxRatio: rxMaxSpeed > 0 ? Math.min(1, rxSpeed / rxMaxSpeed) : 0
  readonly property real txRatio: txMaxSpeed > 0 ? Math.min(1, txSpeed / txMaxSpeed) : 0

  // Color resolution (respects useCustomColors setting)
  readonly property color warningColor: Settings.data.systemMonitor.useCustomColors ? (Settings.data.systemMonitor.warningColor || Color.mTertiary) : Color.mTertiary
  readonly property color criticalColor: Settings.data.systemMonitor.useCustomColors ? (Settings.data.systemMonitor.criticalColor || Color.mError) : Color.mError

  // Threshold values from settings
  readonly property int cpuWarningThreshold: Settings.data.systemMonitor.cpuWarningThreshold
  readonly property int cpuCriticalThreshold: Settings.data.systemMonitor.cpuCriticalThreshold
  readonly property int tempWarningThreshold: Settings.data.systemMonitor.tempWarningThreshold
  readonly property int tempCriticalThreshold: Settings.data.systemMonitor.tempCriticalThreshold
  readonly property int gpuWarningThreshold: Settings.data.systemMonitor.gpuWarningThreshold
  readonly property int gpuCriticalThreshold: Settings.data.systemMonitor.gpuCriticalThreshold
  readonly property int memWarningThreshold: Settings.data.systemMonitor.memWarningThreshold
  readonly property int memCriticalThreshold: Settings.data.systemMonitor.memCriticalThreshold
  readonly property int diskWarningThreshold: Settings.data.systemMonitor.diskWarningThreshold
  readonly property int diskCriticalThreshold: Settings.data.systemMonitor.diskCriticalThreshold

  // Computed warning/critical states (uses >= inclusive comparison)
  readonly property bool cpuWarning: cpuUsage >= cpuWarningThreshold
  readonly property bool cpuCritical: cpuUsage >= cpuCriticalThreshold
  readonly property bool tempWarning: cpuTemp >= tempWarningThreshold
  readonly property bool tempCritical: cpuTemp >= tempCriticalThreshold
  readonly property bool gpuWarning: gpuAvailable && gpuTemp >= gpuWarningThreshold
  readonly property bool gpuCritical: gpuAvailable && gpuTemp >= gpuCriticalThreshold
  readonly property bool memWarning: memPercent >= memWarningThreshold
  readonly property bool memCritical: memPercent >= memCriticalThreshold

  // Helper functions for disk (disk path is dynamic)
  function isDiskWarning(diskPath) {
    return (diskPercents[diskPath] || 0) >= diskWarningThreshold;
  }

  function isDiskCritical(diskPath) {
    return (diskPercents[diskPath] || 0) >= diskCriticalThreshold;
  }

  // Ready-to-use stat colors (for gauges, panels, icons)
  readonly property color cpuColor: cpuCritical ? criticalColor : (cpuWarning ? warningColor : Color.mPrimary)
  readonly property color tempColor: tempCritical ? criticalColor : (tempWarning ? warningColor : Color.mPrimary)
  readonly property color gpuColor: gpuCritical ? criticalColor : (gpuWarning ? warningColor : Color.mPrimary)
  readonly property color memColor: memCritical ? criticalColor : (memWarning ? warningColor : Color.mPrimary)

  function getDiskColor(diskPath) {
    return isDiskCritical(diskPath) ? criticalColor : (isDiskWarning(diskPath) ? warningColor : Color.mPrimary);
  }

  // Helper function for color resolution based on value and thresholds
  function getStatColor(value, warningThreshold, criticalThreshold) {
    if (value >= criticalThreshold)
      return criticalColor;
    if (value >= warningThreshold)
      return warningColor;
    return Color.mPrimary;
  }

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

  // GPU temperature detection
  // On dual-GPU systems, we prioritize discrete GPUs over integrated GPUs
  // Priority: NVIDIA (opt-in) > AMD dGPU > Intel Arc > AMD iGPU
  // Note: NVIDIA requires opt-in because nvidia-smi wakes the dGPU on laptops, draining battery
  readonly property var supportedTempGpuSensorNames: ["amdgpu", "xe"]
  property string gpuTempHwmonPath: ""
  property var foundGpuSensors: [] // [{hwmonPath, type, hasDedicatedVram}]
  property int gpuVramCheckIndex: 0

  // --------------------------------------------
  // Network speed stats cache (7-day rolling window)
  property string networkStatsFile: Settings.cacheDir + "network_stats.json"

  FileView {
    id: networkStatsView
    path: root.networkStatsFile
    printErrors: false

    JsonAdapter {
      id: networkStatsAdapter
      property var rxPeaks: []
      property var txPeaks: []
    }

    onLoadFailed: {
      networkStatsAdapter.rxPeaks = [];
      networkStatsAdapter.txPeaks = [];
    }

    onLoaded: {
      root.pruneExpiredPeaks();
    }
  }

  Timer {
    id: networkStatsSaveDebounce
    interval: 1000
    onTriggered: networkStatsView.writeAdapter()
  }

  function pruneExpiredPeaks() {
    const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
    const cutoff = Date.now() - sevenDaysMs;
    const rxBefore = (networkStatsAdapter.rxPeaks || []).length;
    const txBefore = (networkStatsAdapter.txPeaks || []).length;

    networkStatsAdapter.rxPeaks = (networkStatsAdapter.rxPeaks || []).filter(p => p.timestamp > cutoff);
    networkStatsAdapter.txPeaks = (networkStatsAdapter.txPeaks || []).filter(p => p.timestamp > cutoff);

    // Save if any were pruned
    if (networkStatsAdapter.rxPeaks.length !== rxBefore || networkStatsAdapter.txPeaks.length !== txBefore) {
      networkStatsSaveDebounce.restart();
    }
  }

  // --------------------------------------------
  Component.onCompleted: {
    Logger.i("SystemStat", "Service started with custom polling intervals");

    // Kickoff the cpu name detection for temperature
    cpuTempNameReader.checkNext();

    // Kickoff the gpu sensor detection for temperature
    gpuTempNameReader.checkNext();

    // Check for ZFS ARC stats on startup
    zfsArcStatsFile.reload();

    // Get nproc on startup
    nprocProcess.running = true;

    // Get initial load average
    loadAvgFile.reload();
  }

  // Re-run GPU detection when dGPU opt-in setting changes
  Connections {
    target: Settings.data.systemMonitor
    function onEnableDgpuMonitoringChanged() {
      Logger.i("SystemStat", "dGPU monitoring opt-in setting changed, re-detecting GPUs");
      restartGpuDetection();
    }
  }

  function restartGpuDetection() {
    // Reset GPU state
    root.gpuAvailable = false;
    root.gpuType = "";
    root.gpuTempHwmonPath = "";
    root.gpuTemp = 0;
    root.foundGpuSensors = [];
    root.gpuVramCheckIndex = 0;

    // Restart GPU detection
    gpuTempNameReader.currentIndex = 0;
    gpuTempNameReader.checkNext();
  }

  // --------------------------------------------
  // Timer for CPU usage
  Timer {
    id: cpuUsageTimer
    interval: root.normalizeInterval(Settings.data.systemMonitor.cpuPollingInterval)
    repeat: true
    running: true
    triggeredOnStart: true
    onIntervalChanged: {
      if (running) {
        restart();
      }
    }
    onTriggered: cpuStatFile.reload()
  }

  // Timer for load average
  Timer {
    id: loadAvgTimer
    interval: root.normalizeInterval(Settings.data.systemMonitor.loadAvgPollingInterval)
    repeat: true
    running: true
    triggeredOnStart: true
    onIntervalChanged: {
      if (running) {
        restart();
      }
    }
    onTriggered: loadAvgFile.reload()
  }

  // Timer for CPU temperature
  Timer {
    id: cpuTempTimer
    interval: root.normalizeInterval(Settings.data.systemMonitor.tempPollingInterval)
    repeat: true
    running: true
    triggeredOnStart: true
    onIntervalChanged: {
      if (running) {
        restart();
      }
    }
    onTriggered: updateCpuTemperature()
  }

  // Timer for memory stats
  Timer {
    id: memoryTimer
    interval: root.normalizeInterval(Settings.data.systemMonitor.memPollingInterval)
    repeat: true
    running: true
    triggeredOnStart: true
    onIntervalChanged: {
      if (running) {
        restart();
      }
    }
    onTriggered: {
      memInfoFile.reload();
      zfsArcStatsFile.reload();
    }
  }

  // Timer for disk usage
  Timer {
    id: diskTimer
    interval: root.normalizeInterval(Settings.data.systemMonitor.diskPollingInterval)
    repeat: true
    running: true
    triggeredOnStart: true
    onIntervalChanged: {
      if (running) {
        restart();
      }
    }
    onTriggered: dfProcess.running = true
  }

  // Timer for network speeds
  Timer {
    id: networkTimer
    interval: root.normalizeInterval(Settings.data.systemMonitor.networkPollingInterval)
    repeat: true
    running: true
    triggeredOnStart: true
    onIntervalChanged: {
      if (running) {
        restart();
      }
    }
    onTriggered: netDevFile.reload()
  }

  // Timer for GPU temperature
  Timer {
    id: gpuTempTimer
    interval: root.normalizeInterval(Settings.data.systemMonitor.gpuPollingInterval)
    repeat: true
    running: root.gpuAvailable
    triggeredOnStart: true
    onIntervalChanged: {
      if (running) {
        restart();
      }
    }
    onTriggered: updateGpuTemperature()
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

  FileView {
    id: loadAvgFile
    path: "/proc/loadavg"
    onLoaded: parseLoadAverage(text())
  }

  // ZFS ARC stats file (only exists on ZFS systems)
  FileView {
    id: zfsArcStatsFile
    path: "/proc/spl/kstat/zfs/arcstats"
    printErrors: false
    onLoaded: parseZfsArcStats(text())
    onLoadFailed: {
      // File doesn't exist (non-ZFS system), set ARC values to 0
      root.zfsArcSizeKb = 0;
      root.zfsArcCminKb = 0;
    }
  }

  // --------------------------------------------
  // Process to fetch disk usage (percent, used, size)
  // Uses 'df' aka 'disk free'
  // "-x efivarfs' skips efivarfs mountpoints, for which the `statfs` syscall may cause system-wide stuttering
  // --block-size=1 gives us bytes for precise GB calculation
  Process {
    id: dfProcess
    command: ["df", "--output=target,pcent,used,size", "--block-size=1", "-x", "efivarfs"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split('\n');
        const newPercents = {};
        const newUsedGb = {};
        const newSizeGb = {};
        const bytesPerGb = 1024 * 1024 * 1024;
        // Start from line 1 (skip header)
        for (var i = 1; i < lines.length; i++) {
          const parts = lines[i].trim().split(/\s+/);
          if (parts.length >= 4) {
            const target = parts[0];
            const percent = parseInt(parts[1].replace(/[^0-9]/g, '')) || 0;
            const usedBytes = parseFloat(parts[2]) || 0;
            const sizeBytes = parseFloat(parts[3]) || 0;
            newPercents[target] = percent;
            newUsedGb[target] = usedBytes / bytesPerGb;
            newSizeGb[target] = sizeBytes / bytesPerGb;
          }
        }
        root.diskPercents = newPercents;
        root.diskUsedGb = newUsedGb;
        root.diskSizeGb = newSizeGb;
      }
    }
  }

  // Process to get number of processors
  Process {
    id: nprocProcess
    command: ["nproc"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.nproc = parseInt(text.trim());
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
        Logger.w("No supported temperature sensor found");
        return;
      }

      //Logger.i("SystemStat", "---- Probing: hwmon", currentIndex)
      cpuTempNameReader.path = `/sys/class/hwmon/hwmon${currentIndex}/name`;
      cpuTempNameReader.reload();
    }

    onLoaded: {
      const name = text().trim();
      if (root.supportedTempCpuSensorNames.includes(name)) {
        root.cpuTempSensorName = name;
        root.cpuTempHwmonPath = `/sys/class/hwmon/hwmon${currentIndex}`;
        Logger.i("SystemStat", `Found ${root.cpuTempSensorName} CPU thermal sensor at ${root.cpuTempHwmonPath}`);
      } else {
        currentIndex++;
        Qt.callLater(() => {
                       // Qt.callLater is mandatory
                       checkNext();
                     });
      }
    }

    onLoadFailed: function (error) {
      currentIndex++;
      Qt.callLater(() => {
                     // Qt.callLater is mandatory
                     checkNext();
                   });
    }
  }

  // ----
  // #2 - Read sensor value
  FileView {
    id: cpuTempReader
    printErrors: false

    onLoaded: {
      const data = text().trim();
      if (root.cpuTempSensorName === "coretemp") {
        // For Intel, collect all temperature values
        const temp = parseInt(data) / 1000.0;
        //console.log(temp, cpuTempReader.path)
        root.intelTempValues.push(temp);
        Qt.callLater(() => {
                       // Qt.callLater is mandatory
                       checkNextIntelTemp();
                     });
      } else {
        // For AMD sensors (k10temp and zenpower), directly set the temperature
        root.cpuTemp = Math.round(parseInt(data) / 1000.0);
      }
    }
    onLoadFailed: function (error) {
      Qt.callLater(() => {
                     // Qt.callLater is mandatory
                     checkNextIntelTemp();
                   });
    }
  }

  // --------------------------------------------
  // --------------------------------------------
  // GPU Temperature
  // On dual-GPU systems (e.g., Intel iGPU + NVIDIA dGPU, or AMD APU + AMD dGPU),
  // we scan all hwmon entries, then select the best GPU based on priority.
  // ----
  // #1 - Scan all hwmon entries to find GPU sensors
  FileView {
    id: gpuTempNameReader
    property int currentIndex: 0
    printErrors: false

    function checkNext() {
      if (currentIndex >= 16) {
        // Finished scanning all hwmon entries
        // Only check nvidia-smi if user has explicitly enabled dGPU monitoring (opt-in)
        // because nvidia-smi wakes up the dGPU on laptops, draining battery
        if (Settings.data.systemMonitor.enableDgpuMonitoring) {
          Logger.d("SystemStat", `Found ${root.foundGpuSensors.length} sysfs GPU sensor(s), checking nvidia-smi (dGPU opt-in enabled)`);
          nvidiaSmiCheck.running = true;
        } else {
          Logger.d("SystemStat", `Found ${root.foundGpuSensors.length} sysfs GPU sensor(s), skipping nvidia-smi (dGPU opt-in disabled)`);
          root.gpuVramCheckIndex = 0;
          checkNextGpuVram();
        }
        return;
      }

      gpuTempNameReader.path = `/sys/class/hwmon/hwmon${currentIndex}/name`;
      gpuTempNameReader.reload();
    }

    onLoaded: {
      const name = text().trim();
      if (root.supportedTempGpuSensorNames.includes(name)) {
        // Collect this GPU sensor, don't stop - continue scanning for more
        const hwmonPath = `/sys/class/hwmon/hwmon${currentIndex}`;
        const gpuType = name === "amdgpu" ? "amd" : "intel";
        root.foundGpuSensors.push({
                                    "hwmonPath": hwmonPath,
                                    "type": gpuType,
                                    "hasDedicatedVram": false // Will be checked later for AMD
                                  });
        Logger.d("SystemStat", `Found ${name} GPU sensor at ${hwmonPath}`);
      }
      // Continue scanning regardless of whether we found a match
      currentIndex++;
      Qt.callLater(() => {
                     checkNext();
                   });
    }

    onLoadFailed: function (error) {
      currentIndex++;
      Qt.callLater(() => {
                     checkNext();
                   });
    }
  }

  // ----
  // #2 - Read GPU sensor value (AMD/Intel via sysfs)
  FileView {
    id: gpuTempReader
    printErrors: false

    onLoaded: {
      const data = text().trim();
      root.gpuTemp = Math.round(parseInt(data) / 1000.0);
    }
  }

  // ----
  // #3 - Check if nvidia-smi is available (for NVIDIA GPUs)
  Process {
    id: nvidiaSmiCheck
    command: ["sh", "-c", "command -v nvidia-smi"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.trim().length > 0) {
          // Add NVIDIA as a GPU option (always discrete, highest priority)
          root.foundGpuSensors.push({
                                      "hwmonPath": "",
                                      "type": "nvidia",
                                      "hasDedicatedVram": true // NVIDIA is always discrete
                                    });
          Logger.d("SystemStat", "Found NVIDIA GPU (nvidia-smi available)");
        }
        // After NVIDIA check, check VRAM for AMD GPUs to distinguish dGPU from iGPU
        root.gpuVramCheckIndex = 0;
        checkNextGpuVram();
      }
    }
  }

  // ----
  // #4 - Check VRAM for AMD GPUs to distinguish dGPU from iGPU
  // dGPUs have dedicated VRAM, iGPUs don't (use system RAM)
  FileView {
    id: gpuVramChecker
    printErrors: false

    onLoaded: {
      // File exists and has content = dGPU with dedicated VRAM
      const vramSize = parseInt(text().trim());
      if (vramSize > 0) {
        root.foundGpuSensors[root.gpuVramCheckIndex].hasDedicatedVram = true;
        Logger.d("SystemStat", `GPU at ${root.foundGpuSensors[root.gpuVramCheckIndex].hwmonPath} has dedicated VRAM (dGPU)`);
      }
      root.gpuVramCheckIndex++;
      Qt.callLater(() => {
                     checkNextGpuVram();
                   });
    }

    onLoadFailed: function (error) {
      // File doesn't exist = iGPU (no dedicated VRAM)
      // hasDedicatedVram is already false by default
      root.gpuVramCheckIndex++;
      Qt.callLater(() => {
                     checkNextGpuVram();
                   });
    }
  }

  // ----
  // #4 - Read GPU temperature via nvidia-smi (NVIDIA only)
  Process {
    id: nvidiaTempProcess
    command: ["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const temp = parseInt(text.trim());
        if (!isNaN(temp)) {
          root.gpuTemp = temp;
        }
      }
    }
  }

  // -------------------------------------------------------
  // -------------------------------------------------------
  // Parse ZFS ARC stats from /proc/spl/kstat/zfs/arcstats
  function parseZfsArcStats(text) {
    if (!text)
      return;
    const lines = text.split('\n');

    // The file format is: name type data
    // We need to find the lines with "size" and "c_min" and extract the values (third column)
    let foundSize = false;
    let foundCmin = false;

    for (const line of lines) {
      const parts = line.trim().split(/\s+/);
      if (parts.length >= 3) {
        if (parts[0] === 'size') {
          // The value is in bytes, convert to KB
          const arcSizeBytes = parseInt(parts[2]) || 0;
          root.zfsArcSizeKb = Math.floor(arcSizeBytes / 1024);
          foundSize = true;
        } else if (parts[0] === 'c_min') {
          // The value is in bytes, convert to KB
          const arcCminBytes = parseInt(parts[2]) || 0;
          root.zfsArcCminKb = Math.floor(arcCminBytes / 1024);
          foundCmin = true;
        }

        // If we found both, we can return early
        if (foundSize && foundCmin) {
          return;
        }
      }
    }

    // If fields not found, set to 0
    if (!foundSize) {
      root.zfsArcSizeKb = 0;
    }
    if (!foundCmin) {
      root.zfsArcCminKb = 0;
    }
  }

  // -------------------------------------------------------
  // Parse load average from /proc/loadavg
  function parseLoadAverage(text) {
    if (!text)
      return;
    const parts = text.trim().split(/\s+/);
    if (parts.length >= 3) {
      root.loadAvg1 = parseFloat(parts[0]);
      root.loadAvg5 = parseFloat(parts[1]);
      root.loadAvg15 = parseFloat(parts[2]);
    }
  }

  // -------------------------------------------------------
  // Parse memory info from /proc/meminfo
  function parseMemoryInfo(text) {
    if (!text)
      return;
    const lines = text.split('\n');
    let memTotal = 0;
    let memAvailable = 0;

    for (const line of lines) {
      if (line.startsWith('MemTotal:')) {
        memTotal = parseInt(line.split(/\s+/)[1]) || 0;
      } else if (line.startsWith('MemAvailable:')) {
        memAvailable = parseInt(line.split(/\s+/)[1]) || 0;
      }
    }

    if (memTotal > 0) {
      // Calculate usage, adjusting for ZFS ARC cache if present
      let usageKb = memTotal - memAvailable;
      if (root.zfsArcSizeKb > 0) {
        usageKb = Math.max(0, usageKb - root.zfsArcSizeKb + root.zfsArcCminKb);
      }
      root.memGb = (usageKb / 1048576).toFixed(1); // 1024*1024 = 1048576
      root.memPercent = Math.round((usageKb / memTotal) * 100);
    }
  }

  // -------------------------------------------------------
  // Calculate CPU usage from /proc/stat
  function calculateCpuUsage(text) {
    if (!text)
      return;
    const lines = text.split('\n');
    const cpuLine = lines[0];

    // First line is total CPU
    if (!cpuLine.startsWith('cpu '))
      return;
    const parts = cpuLine.split(/\s+/);
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
    };
    const totalIdle = stats.idle + stats.iowait;
    const total = Object.values(stats).reduce((sum, val) => sum + val, 0);

    if (root.prevCpuStats) {
      const prevTotalIdle = root.prevCpuStats.idle + root.prevCpuStats.iowait;
      const prevTotal = Object.values(root.prevCpuStats).reduce((sum, val) => sum + val, 0);

      const diffTotal = total - prevTotal;
      const diffIdle = totalIdle - prevTotalIdle;

      if (diffTotal > 0) {
        root.cpuUsage = (((diffTotal - diffIdle) / diffTotal) * 100).toFixed(1);
      }
    }

    root.prevCpuStats = stats;
  }

  // -------------------------------------------------------
  // Calculate RX and TX speed from /proc/net/dev
  // Average speed of all interfaces excepted 'lo'
  function calculateNetworkSpeed(text) {
    if (!text) {
      return;
    }

    const currentTime = Date.now() / 1000;
    const lines = text.split('\n');

    let totalRx = 0;
    let totalTx = 0;

    for (var i = 2; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) {
        continue;
      }

      const colonIndex = line.indexOf(':');
      if (colonIndex === -1) {
        continue;
      }

      const iface = line.substring(0, colonIndex).trim();
      if (iface === 'lo') {
        continue;
      }

      const statsLine = line.substring(colonIndex + 1).trim();
      const stats = statsLine.split(/\s+/);

      const rxBytes = parseInt(stats[0], 10) || 0;
      const txBytes = parseInt(stats[8], 10) || 0;

      totalRx += rxBytes;
      totalTx += txBytes;
    }

    // Compute only if we have a previous run to compare to.
    if (root.prevTime > 0) {
      const timeDiff = currentTime - root.prevTime;

      // Avoid division by zero if time hasn't passed.
      if (timeDiff > 0) {
        let rxDiff = totalRx - root.prevRxBytes;
        let txDiff = totalTx - root.prevTxBytes;

        // Handle counter resets (e.g., WiFi reconnect), which would cause a negative value.
        if (rxDiff < 0) {
          rxDiff = 0;
        }
        if (txDiff < 0) {
          txDiff = 0;
        }

        root.rxSpeed = Math.round(rxDiff / timeDiff); // Speed in Bytes/s
        root.txSpeed = Math.round(txDiff / timeDiff);

        // Record new peaks if higher than current max (for adaptive ratio calculation)
        const now = Date.now();
        if (root.rxSpeed > root.rxMaxSpeed) {
          networkStatsAdapter.rxPeaks = [...(networkStatsAdapter.rxPeaks || []),
                                         {
                                           speed: root.rxSpeed,
                                           timestamp: now
                                         }
              ];
          networkStatsSaveDebounce.restart();
        }
        if (root.txSpeed > root.txMaxSpeed) {
          networkStatsAdapter.txPeaks = [...(networkStatsAdapter.txPeaks || []),
                                         {
                                           speed: root.txSpeed,
                                           timestamp: now
                                         }
              ];
          networkStatsSaveDebounce.restart();
        }
      }
    }

    root.prevRxBytes = totalRx;
    root.prevTxBytes = totalTx;
    root.prevTime = currentTime;
  }

  // -------------------------------------------------------
  // Helper function to format network speeds
  function formatSpeed(bytesPerSecond) {
    const units = ["KB", "MB", "GB"];
    let value = bytesPerSecond / 1024;
    let unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }

    const unit = units[unitIndex];
    const shortUnit = unit[0];
    const numStr = value < 10 ? value.toFixed(1) : Math.round(value).toString();

    return (numStr + unit).length > 5 ? numStr + shortUnit : numStr + unit;
  }

  // -------------------------------------------------------
  // Compact speed formatter for vertical bar display
  function formatCompactSpeed(bytesPerSecond) {
    if (!bytesPerSecond || bytesPerSecond <= 0)
      return "0";
    const units = ["", "K", "M", "G"];
    let value = bytesPerSecond;
    let unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value = value / 1024.0;
      unitIndex++;
    }
    // Promote at ~100 of current unit (e.g., 100k -> ~0.1M shown as 0.1M or 0M if rounded)
    if (unitIndex < units.length - 1 && value >= 100) {
      value = value / 1024.0;
      unitIndex++;
    }
    const display = Math.round(value).toString();
    return display + units[unitIndex];
  }

  // -------------------------------------------------------
  // Smart formatter for memory values (GB) - max 4 chars
  // Uses decimal for < 10GB, integer otherwise
  function formatMemoryGb(memGb) {
    const value = parseFloat(memGb);
    if (isNaN(value))
      return "0G";

    if (value < 10)
      return value.toFixed(1) + "G"; // "0.0G" to "9.9G"
    return Math.round(value) + "G"; // "10G" to "999G"
  }

  // -------------------------------------------------------
  // Function to start fetching and computing the cpu temperature
  function updateCpuTemperature() {
    // For AMD sensors (k10temp and zenpower), only use Tctl sensor
    // temp1_input corresponds to Tctl (Temperature Control) on these sensors
    if (root.cpuTempSensorName === "k10temp" || root.cpuTempSensorName === "zenpower") {
      cpuTempReader.path = `${root.cpuTempHwmonPath}/temp1_input`;
      cpuTempReader.reload();
    } // For Intel coretemp, start averaging all available sensors/cores
    else if (root.cpuTempSensorName === "coretemp") {
      root.intelTempValues = [];
      root.intelTempFilesChecked = 0;
      checkNextIntelTemp();
    }
  }

  // -------------------------------------------------------
  // Function to check next Intel temperature sensor
  function checkNextIntelTemp() {
    if (root.intelTempFilesChecked >= root.intelTempMaxFiles) {
      // Calculate average of all found temperatures
      if (root.intelTempValues.length > 0) {
        let sum = 0;
        for (var i = 0; i < root.intelTempValues.length; i++) {
          sum += root.intelTempValues[i];
        }
        root.cpuTemp = Math.round(sum / root.intelTempValues.length);
        //Logger.i("SystemStat", `Averaged ${root.intelTempValues.length} CPU thermal sensors: ${root.cpuTemp}°C`)
      } else {
        Logger.w("SystemStat", "No temperature sensors found for coretemp");
        root.cpuTemp = 0;
      }
      return;
    }

    // Check next temperature file
    root.intelTempFilesChecked++;
    cpuTempReader.path = `${root.cpuTempHwmonPath}/temp${root.intelTempFilesChecked}_input`;
    cpuTempReader.reload();
  }

  // -------------------------------------------------------
  // Function to check VRAM for each AMD GPU to determine if it's a dGPU
  function checkNextGpuVram() {
    // Skip non-AMD GPUs (NVIDIA and Intel Arc are always discrete)
    while (root.gpuVramCheckIndex < root.foundGpuSensors.length) {
      const gpu = root.foundGpuSensors[root.gpuVramCheckIndex];
      if (gpu.type === "amd") {
        // Check for dedicated VRAM at hwmonPath/device/mem_info_vram_total
        gpuVramChecker.path = `${gpu.hwmonPath}/device/mem_info_vram_total`;
        gpuVramChecker.reload();
        return;
      }
      // Skip non-AMD GPUs
      root.gpuVramCheckIndex++;
    }

    // All VRAM checks complete, now select the best GPU
    selectBestGpu();
  }

  // -------------------------------------------------------
  // Function to select the best GPU based on priority
  // Priority (when dGPU monitoring enabled): NVIDIA > AMD dGPU > Intel Arc > AMD iGPU
  // Priority (when dGPU monitoring disabled): AMD iGPU only (discrete GPUs skipped to preserve D3cold)
  function selectBestGpu() {
    if (root.foundGpuSensors.length === 0) {
      Logger.d("SystemStat", "No GPU temperature sensor found");
      return;
    }

    const dgpuEnabled = Settings.data.systemMonitor.enableDgpuMonitoring;
    let best = null;

    for (var i = 0; i < root.foundGpuSensors.length; i++) {
      const gpu = root.foundGpuSensors[i];

      // NVIDIA is always highest priority (always discrete) - skip if dGPU monitoring disabled
      if (gpu.type === "nvidia") {
        if (dgpuEnabled) {
          best = gpu;
          break;
        }
        continue;
      }

      // AMD dGPU is second priority - skip if dGPU monitoring disabled (preserves D3cold power state)
      if (gpu.type === "amd" && gpu.hasDedicatedVram) {
        if (dgpuEnabled) {
          best = gpu;
          break;
        }
        continue;
      }

      // Intel Arc is third priority (always discrete) - skip if dGPU monitoring disabled
      if (gpu.type === "intel" && !best) {
        if (dgpuEnabled) {
          best = gpu;
        }
        continue;
      }

      // AMD iGPU is lowest priority (fallback) - always allowed (no D3cold issue)
      if (gpu.type === "amd" && !gpu.hasDedicatedVram && !best) {
        best = gpu;
      }
    }

    if (best) {
      root.gpuTempHwmonPath = best.hwmonPath;
      root.gpuType = best.type;
      root.gpuAvailable = true;

      const gpuDesc = best.type === "nvidia" ? "NVIDIA" : (best.type === "intel" ? "Intel Arc" : (best.hasDedicatedVram ? "AMD dGPU" : "AMD iGPU"));
      Logger.i("SystemStat", `Selected ${gpuDesc} for temperature monitoring at ${best.hwmonPath || "nvidia-smi"}`);
    } else if (!dgpuEnabled) {
      Logger.d("SystemStat", "No iGPU found and dGPU monitoring is disabled");
    }
  }

  // -------------------------------------------------------
  // Function to update GPU temperature
  function updateGpuTemperature() {
    if (root.gpuType === "nvidia") {
      nvidiaTempProcess.running = true;
    } else if (root.gpuType === "amd" || root.gpuType === "intel") {
      gpuTempReader.path = `${root.gpuTempHwmonPath}/temp1_input`;
      gpuTempReader.reload();
    }
  }
}
