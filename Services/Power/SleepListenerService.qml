pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor

Singleton {
  id: root

  function init() {
    Logger.i("SleepListener", "Service started");
  }

  // Listen for the PrepareForSleep signal from logind.
  // This signal is emitted when the system is about to suspend or hibernate.
  Process {
    id: sleepMonitor
    command: ["dbus-monitor", "--system", "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
    running: true

    stdout: StdioCollector {
      onLine: line => {
        // dbus-monitor output for the signal contains the boolean argument (true for sleep, false for wake).
        // We look for "boolean true" to trigger the lock screen.
        if (line.includes("boolean true")) {
          Logger.i("SleepListener", "System is preparing for sleep, triggering lock");
          
          // Trigger the lock screen via CompositorService.
          // CompositorService.lock() handles checking if it's already locked.
          CompositorService.lock();
        } else if (line.includes("boolean false")) {
          Logger.i("SleepListener", "System has resumed from sleep");
        }
      }
    }

    stderr: StdioCollector {
      onLine: line => Logger.w("SleepListener", "dbus-monitor error: " + line)
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
