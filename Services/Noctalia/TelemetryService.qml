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

  readonly property string telemetryEndpoint: Quickshell.env("NOCTALIA_TELEMETRY_ENDPOINT") || "https://api.noctalia.dev/ping"

  function init() {
    if (initialized)
      return;

    initialized = true;

    if (!Settings.data.general.telemetryEnabled) {
      Logger.d("Telemetry", "Telemetry disabled by user");
      return;
    }

    // Get or generate instance ID from ShellState
    instanceId = ShellState.getTelemetryInstanceId();
    if (!instanceId) {
      instanceId = generateRandomId();
      ShellState.setTelemetryInstanceId(instanceId);
      Logger.d("Telemetry", "Generated new random instance ID");
    } else {
      Logger.d("Telemetry", "Using stored instance ID");
    }

    // Read RAM info, then send ping
    memInfoProcess.running = true;
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
        fontDefaultScale: Settings.data.ui.fontDefaultScale,
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
    if (CompositorService.isScroll)
      return "Scroll";
    if (CompositorService.isSway)
      return "Sway";
    if (CompositorService.isMango)
      return "MangoWC";
    if (CompositorService.isLabwc)
      return "LabWC";
    return "Unknown";
  }
}
