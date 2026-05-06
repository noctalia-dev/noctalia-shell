pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI

/**
* SleepListenerService — native system sleep detection via D-Bus.
*
* Listens for the PrepareForSleep signal from logind to ensure the
* session is locked before the system suspends (e.g. lid close).
*/
Singleton {
  id: root

  property int checkCount: 0

  function init() {
    Logger.i("SleepListener", "Service started");
  }

  // Use systemd-inhibit to delay sleep until we've locked the screen.
  // This process holds a 'delay' inhibitor for sleep. When logind prepares for sleep,
  // it will wait for this process to terminate (or timeout) before actually suspending.
  // We stop this process once we confirm the lock screen is active, allowing sleep to proceed.
  Process {
    id: sleepInhibitor
    command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Noctalia", "--why=Locking screen before sleep", "sleep", "infinity"]
    // Only inhibit if locking on suspend is enabled.
    running: Settings.data.general.lockOnSuspend

    stderr: SplitParser {
      splitMarker: "\n"
      onRead: line => Logger.w("SleepListener", "inhibitor error: " + line)
    }
  }

  // Listen for the PrepareForSleep signal from logind.
  // This signal is emitted when the system is about to suspend or hibernate.
  Process {
    id: sleepMonitor
    command: ["stdbuf", "-oL", "dbus-monitor", "--system", "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
    running: true

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: line => {
        Logger.d("SleepListener", "Received line: " + line);
        // dbus-monitor output for the signal contains the boolean argument (true for sleep, false for wake).
        // We look for "boolean true" to trigger the lock screen.
        if (line.includes("boolean true")) {
          if (Settings.data.general.lockOnSuspend) {
            Logger.i("SleepListener", "System is preparing for sleep, triggering lock");
            CompositorService.lock();
            // Start checking if lock is active. We must release the inhibitor 
            // only AFTER the lock screen is visually active to prevent race conditions.
            lockCheckTimer.start();
          } else {
            Logger.d("SleepListener", "System is preparing for sleep, but lockOnSuspend is disabled");
          }
        } else if (line.includes("boolean false")) {
          Logger.i("SleepListener", "System has resumed from sleep");
          // Re-enable inhibitor if locking is enabled so we're ready for the next suspend.
          if (Settings.data.general.lockOnSuspend) {
            sleepInhibitor.running = true;
          }
        }
      }
    }

    stderr: SplitParser {
      splitMarker: "\n"
      onRead: line => Logger.w("SleepListener", "dbus-monitor error: " + line)
    }

    onExited: (code, status) => {
      Logger.w("SleepListener", "dbus-monitor exited with code " + code + ". Restarting...");
      restartTimer.start();
    }
  }

  Timer {
    id: lockCheckTimer
    interval: 100
    repeat: true
    onTriggered: {
      root.checkCount++;
      // Check if lock screen is now active and its content is loaded
      if (PanelService && PanelService.lockScreen && PanelService.lockScreen.active && PanelService.lockScreen.item) {
        Logger.i("SleepListener", "Lock screen active, releasing sleep inhibitor");
        sleepInhibitor.running = false;
        stop();
        root.checkCount = 0;
      } else if (root.checkCount > 30) { // 3 seconds timeout
        Logger.w("SleepListener", "Lock screen timeout, releasing inhibitor anyway");
        sleepInhibitor.running = false;
        stop();
        root.checkCount = 0;
      }
    }
  }

  Timer {
    id: restartTimer
    interval: 1000
    onTriggered: sleepMonitor.running = true
  }

  // Cleanup on destruction
  Component.onDestruction: {
    sleepMonitor.running = false;
    sleepInhibitor.running = false;
  }
}
