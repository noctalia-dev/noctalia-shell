pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.System

Singleton {
  id: root

  // Detection state
  property bool available: false // fprintd command available
  property bool hasDevice: false // physical sensor present
  property bool hasEnrolledFingers: false // user has fingerprints enrolled
  readonly property bool ready: hasDevice && hasEnrolledFingers

  // Re-check detection (e.g., after user enrolls fingerprints)
  function refresh() {
    detectProc.retryCount = 0;
    detectProc.running = true;
  }

  Component.onCompleted: {
    Logger.i("Fingerprint", "Service starting, detecting fingerprint reader...");
    detectProc.running = true;
  }

  // Retry timer for transient failures
  Timer {
    id: retryTimer
    interval: 1000 // 1 second between retries
    repeat: false
    onTriggered: detectProc.running = true
  }

  // Detection via fprintd-list
  // Output format:
  //   "found 1 device" -> hasDevice = true
  //   "Device at /net/reactivated/Fprint/Device/0" (device path)
  //   "Fingerprints for user <username>:" followed by finger names -> hasEnrolledFingers = true
  //   "no fingerprints enrolled" -> hasEnrolledFingers = false
  //   Command fails or "No devices available" -> hasDevice = false
  Process {
    id: detectProc
    command: ["fprintd-list", HostService.username]

    property int retryCount: 0
    property int maxRetries: 3

    stdout: StdioCollector {
      onStreamFinished: {
        var output = text.trim();
        if (output.length > 10000) {
          Logger.w("Fingerprint", "fprintd-list output unexpectedly large, truncating");
          output = output.substring(0, 10000);
        }
        Logger.d("Fingerprint", "fprintd-list output:", output);

        // Check for device
        root.hasDevice = output.includes("found") && output.includes("device");

        if (!root.hasDevice) {
          Logger.i("Fingerprint", "No fingerprint device found");
          root.available = false;
          root.hasEnrolledFingers = false;
          return;
        }

        root.available = true;
        detectProc.retryCount = 0; // Reset on success

        // Check for enrolled fingerprints - more flexible pattern
        // Look for finger entries like "- #0:" which indicates enrolled fingers
        var hasFingers = output.includes("Fingerprints for user") &&
                         !output.includes("no fingerprints enrolled") &&
                         /- #\d+:/.test(output);

        root.hasEnrolledFingers = hasFingers;

        if (root.hasEnrolledFingers) {
          Logger.i("Fingerprint", "Device found with enrolled fingerprints - fingerprint auth ready");
        } else {
          Logger.i("Fingerprint", "Device found but no fingerprints enrolled");
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim() !== "") {
          Logger.w("Fingerprint", "fprintd-list stderr:", text.trim());
        }
      }
    }

    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) {
        if (retryCount < maxRetries) {
          retryCount++;
          Logger.i("Fingerprint", "fprintd-list failed, retry", retryCount, "of", maxRetries);
          retryTimer.start();
        } else {
          Logger.i("Fingerprint", "fprintd-list failed after", maxRetries, "retries - fingerprint auth unavailable");
          root.available = false;
          root.hasDevice = false;
          root.hasEnrolledFingers = false;
        }
      }
    }
  }
}
