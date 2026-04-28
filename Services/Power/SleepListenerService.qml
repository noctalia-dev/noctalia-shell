pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor

/**
* SleepListenerService — native system sleep detection via D-Bus.
*
* Listens for the PrepareForSleep signal from logind to ensure the
* session is locked before the system suspends (e.g. lid close).
*/
Singleton {
  id: root

  function init() {
    Logger.i("SleepListener", "Service started");
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
          } else {
            Logger.d("SleepListener", "System is preparing for sleep, but lockOnSuspend is disabled");
          }
        } else if (line.includes("boolean false")) {
          Logger.i("SleepListener", "System has resumed from sleep");
        }
      }
    }

    stderr: SplitParser {
      splitMarker: "\n"
      onRead: line => Logger.w("SleepListener", "dbus-monitor error: " + line)
    }

    onExited: (code, status) => {
      Logger.w("SleepListener", "dbus-monitor exited with code " + code + ". Restarting...");
      if (root.running) {
        restartTimer.start();
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
  }
}
