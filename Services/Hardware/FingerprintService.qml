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

  // Continuous detection mode - keeps polling until ready or stopped
  // Rationale: After suspend/resume, fprintd may need time to reinitialize
  // Rather than fixed delays, we continuously poll until fprintd responds
  // Lock screen reacts automatically when FingerprintService.ready becomes true
  property bool continuousMode: false

  // Start continuous detection (for lock screen activation / resume)
  function startContinuousDetection() {
    Logger.i("Fingerprint", "Starting continuous detection mode");
    continuousMode = true;
    detectProc.retryCount = 0;
    if (!detectProc.running) {
      Logger.d("Fingerprint", "Starting detection process");
      detectProc.running = true;
    } else {
      Logger.d("Fingerprint", "Detection process already running");
    }
  }

  // Stop continuous detection (when unlocked)
  function stopContinuousDetection() {
    Logger.i("Fingerprint", "Stopping continuous detection mode");
    continuousMode = false;
    retryTimer.stop();
  }

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
        // In continuous mode, keep retrying until stopped or ready
        if (root.continuousMode || retryCount < maxRetries) {
          retryCount++;
          if (root.continuousMode) {
            Logger.d("Fingerprint", "fprintd-list failed, continuous retry", retryCount);
          } else {
            Logger.i("Fingerprint", "fprintd-list failed, retry", retryCount, "of", maxRetries);
          }
          retryTimer.start();
        } else {
          Logger.i("Fingerprint", "fprintd-list failed after", maxRetries, "retries - fingerprint auth unavailable");
          root.available = false;
          root.hasDevice = false;
          root.hasEnrolledFingers = false;
        }
      } else if (root.ready) {
        // Detection succeeded and ready - stop continuous mode
        root.continuousMode = false;
      }
    }
  }
}
