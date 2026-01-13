pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.Noctalia
import qs.Services.System

Singleton {
  id: root

  property bool initialized: false
  property bool isSending: false
  property int totalRamGb: 0
  property string instanceId: ""

  readonly property string telemetryEndpoint: Quickshell.env("NOCTALIA_TELEMETRY_ENDPOINT") || "https://noctalia.dev:7777/ping"
  readonly property string instanceIdSalt: "noctalia-telemetry-2025"

  function init() {
    if (initialized)
      return;

    initialized = true;

    if (!Settings.data.general.telemetryEnabled) {
      Logger.d("Telemetry", "Telemetry disabled by user");
      return;
    }

    // Read machine-id to generate instance ID, then read RAM, then send ping
    machineIdProcess.running = true;
  }

  Process {
    id: machineIdProcess
    command: ["cat", "/etc/machine-id"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        const machineId = text.trim();
        if (machineId && machineId.length > 0) {
          root.instanceId = root.hashString(machineId + root.instanceIdSalt);
          Logger.d("Telemetry", "Generated instance ID from machine-id");
        } else {
          root.instanceId = root.generateRandomId();
          Logger.d("Telemetry", "Using random instance ID (machine-id unavailable)");
        }
        memInfoProcess.running = true;
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.instanceId = root.generateRandomId();
        Logger.d("Telemetry", "Using random instance ID (machine-id read failed)");
        memInfoProcess.running = true;
      }
    }
  }

  function hashString(str) {
    // Simple hash function that produces a UUID-like string
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const c = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + c;
      hash = hash & hash;
    }
    // Convert to hex and pad to create UUID-like format
    const hex = Math.abs(hash).toString(16).padStart(8, '0');
    const hex2 = Math.abs(hash * 31).toString(16).padStart(8, '0');
    const hex3 = Math.abs(hash * 37).toString(16).padStart(8, '0');
    const hex4 = Math.abs(hash * 41).toString(16).padStart(8, '0');
    return `${hex.slice(0, 8)}-${hex2.slice(0, 4)}-${hex2.slice(4, 8)}-${hex3.slice(0, 4)}-${hex3.slice(4, 8)}${hex4.slice(0, 4)}`;
  }

  function generateRandomId() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      const r = Math.random() * 16 | 0;
      const v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }

  function getInstanceId() {
    return instanceId;
  }

  Process {
    id: memInfoProcess
    command: ["sh", "-c", "grep MemTotal /proc/meminfo | awk '{print int($2/1048576)}'"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        const ramGb = parseInt(text.trim()) || 0;
        root.totalRamGb = ramGb;
        root.sendPing();
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        // Still send ping even if RAM detection fails
        root.sendPing();
      }
    }
  }

  function sendPing() {
    if (isSending)
      return;

    isSending = true;

    const payload = {
      instanceId: instanceId,
      version: UpdateService.currentVersion,
      compositor: getCompositorType(),
      os: HostService.osPretty || "Unknown",
      ramGb: totalRamGb,
      monitors: getMonitorInfo(),
      ui: {
        scaleRatio: Settings.data.general.scaleRatio,
        fontDefault: Settings.data.ui.fontDefault || "default",
        fontDefaultScale: Settings.data.ui.fontDefaultScale,
        fontFixed: Settings.data.ui.fontFixed || "default",
        fontFixedScale: Settings.data.ui.fontFixedScale
      }
    };

    Logger.d("Telemetry", "Sending anonymous ping:", JSON.stringify(payload));

    const request = new XMLHttpRequest();
    request.onreadystatechange = function () {
      if (request.readyState === XMLHttpRequest.DONE) {
        if (request.status >= 200 && request.status < 300) {
          Logger.d("Telemetry", "Ping sent successfully");
        } else {
          Logger.d("Telemetry", "Ping failed with status:", request.status);
        }
        isSending = false;
      }
    };

    request.open("POST", telemetryEndpoint);
    request.setRequestHeader("Content-Type", "application/json");
    request.send(JSON.stringify(payload));
  }

  function getMonitorInfo() {
    const monitors = [];
    const screens = Quickshell.screens || [];
    const scales = CompositorService.displayScales || {};

    for (let i = 0; i < screens.length; i++) {
      const screen = screens[i];
      const name = screen.name || "Unknown";
      const scaleData = scales[name];
      // Extract just the numeric scale value
      const scaleValue = (typeof scaleData === "object" && scaleData !== null) ? (scaleData.scale || 1.0) : (scaleData || 1.0);
      monitors.push({
                      width: screen.width || 0,
                      height: screen.height || 0,
                      scale: scaleValue
                    });
    }

    return monitors;
  }

  function getCompositorType() {
    if (CompositorService.isHyprland)
      return "Hyprland";
    if (CompositorService.isNiri)
      return "Niri";
    if (CompositorService.isSway)
      return "Sway";
    if (CompositorService.isMango)
      return "MangoWC";
    if (CompositorService.isLabwc)
      return "LabWC";
    return "Unknown";
  }
}
