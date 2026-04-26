pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  property bool _lockingForSleep: false
  property string _lastMember: ""

  function init() {
    Logger.i("LockService", "Service started");
    sleepInhibitor.running = true;
    lockMonitor.running = true;
  }

  //Delay inhibitor
  Process {
    id: sleepInhibitor
    command: [
      "systemd-inhibit",
        "--what=sleep",
        "--why=Locking screen before sleep",
        "--mode=delay",
      "sleep", "infinity"
    ]
    running: false

    onExited: function(code, status) {
      Logger.d("LockService", "Sleep inhibitor released");
      reacquireTimer.start();
    }
  }

  //D-Bus signal monitor (System bus)
  Process {
    id: lockMonitor
    command: [
      "dbus-monitor", "--system",
        "type='signal',interface='org.freedesktop.login1.Session',member='Lock'",
        "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"
    ]
    running: false

    stdout: SplitParser {
      onRead: function(line) {
        if (line.includes("member=Lock")) {
          Logger.i("LockService", "System Lock signal received - locking");
          root._triggerLock();
          return;
        }

        if (line.includes("member=PrepareForSleep")) {
          root._lastMember = "PrepareForSleep";
          return;
        }

        if (root._lastMember === "PrepareForSleep") {
          if (line.includes("boolean true")) {
            if (!root._lockingForSleep) {
              Logger.i("LockService", "PrepareForSleep(true) - locking");
              root._lockingForSleep = true;
              root._triggerLock();
              releaseTimer.start();
            }
            root._lastMember = "";
          } else if (line.includes("boolean false")) {
            Logger.i("LockService", "System resumed");
            root._lockingForSleep = false;
            root._lastMember = "";
          }
        }
      }
    }

    onExited: function(code, status) {
      Logger.w("LockService", "Monitor exited:", code, "— restarting");
      restartMonitorTimer.start();
    }
  }

  Timer {
    id: releaseTimer
    interval: 1500
    repeat: false
    onTriggered: {
      Logger.i("LockService", "Releasing sleep inhibitor");
      sleepInhibitor.running = false;
    }
  }

  Timer {
    id: reacquireTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!root._lockingForSleep) {
        sleepInhibitor.running = true;
        Logger.d("LockService", "Sleep inhibitor reacquired");
      }
    }
  }

  Timer {
    id: restartMonitorTimer
    interval: 1500
    repeat: false
    onTriggered: lockMonitor.running = true
  }

  function _triggerLock() {
    if (PanelService.lockScreen && !PanelService.lockScreen.active) {
      PanelService.lockScreen.active = true;
    }
    IdleService.lockRequested();
  }
}
