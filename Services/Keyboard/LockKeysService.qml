pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Component registration - only poll when something needs lock key state
  function registerComponent(componentId) {
    root._registered[componentId] = true;
    root._registered = Object.assign({}, root._registered);
    Logger.d("LockKeys", "Component registered:", componentId, "- total:", root._registeredCount);
  }

  function unregisterComponent(componentId) {
    delete root._registered[componentId];
    root._registered = Object.assign({}, root._registered);
    Logger.d("LockKeys", "Component unregistered:", componentId, "- total:", root._registeredCount);
  }

  property var _registered: ({})
  readonly property int _registeredCount: Object.keys(_registered).length
  readonly property bool shouldRun: _registeredCount > 0

  property bool capsLockOn: false
  property bool numLockOn: false
  property bool scrollLockOn: false

  signal capsLockChanged(bool active)
  signal numLockChanged(bool active)
  signal scrollLockChanged(bool active)

  // Flag to track if this is the initial check to avoid OSD triggers
  property bool initialCheckDone: false

  Process {
    id: stateCheckProcess

    property string checkCommand: " \
caps=0; cat /sys/class/leds/input*::capslock/brightness 2>/dev/null | grep -q 1 && caps=1; echo \"caps:${caps}\"; \
num=0; cat /sys/class/leds/input*::numlock/brightness 2>/dev/null | grep -q 1 && num=1; echo \"num:${num}\"; \
scroll=0; cat /sys/class/leds/input*::scrolllock/brightness 2>/dev/null | grep -q 1 && scroll=1; echo \"scroll:${scroll}\"; \
"
    command: ["sh", "-c", stateCheckProcess.checkCommand]

    stdout: StdioCollector {
      onStreamFinished: {
        var lines = this.text.trim().split('\n');
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split(':');
          if (parts.length === 2) {
            var key = parts[0];
            var newState = (parts[1] === '1');

            if (key === "caps") {
              if (root.capsLockOn !== newState) {
                root.capsLockOn = newState;
                if (root.initialCheckDone) {
                  root.capsLockChanged(newState);
                }
                Logger.i("LockKeysService", "Caps Lock:", capsLockOn);
              }
            } else if (key === "num") {
              if (root.numLockOn !== newState) {
                root.numLockOn = newState;
                if (root.initialCheckDone) {
                  root.numLockChanged(newState);
                }
                Logger.i("LockKeysService", "Num Lock:", numLockOn);
              }
            } else if (key === "scroll") {
              if (root.scrollLockOn !== newState) {
                root.scrollLockOn = newState;
                if (root.initialCheckDone) {
                  root.scrollLockChanged(newState);
                }
                Logger.i("LockKeysService", "Scroll Lock:", scrollLockOn);
              }
            }
          }
        }
        // Set initialCheckDone to true after the first check is complete
        if (!root.initialCheckDone) {
          root.initialCheckDone = true;
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text.trim().length > 0)
        Logger.i("LockKeysService", "Error running state check:", this.text.trim());
      }
    }
  }

  onShouldRunChanged: {
    if (shouldRun) {
      // Reset initial check so first poll after re-enable doesn't trigger OSD
      root.initialCheckDone = false;
      stateCheckProcess.running = true;
    }
  }

  Timer {
    id: pollTimer
    interval: 200
    running: root.shouldRun
    repeat: true
    onTriggered: {
      if (!stateCheckProcess.running) {
        stateCheckProcess.running = true;
      }
    }
  }

  Component.onCompleted: {
    Logger.i("LockKeysService", "Service started (polling deferred until a consumer registers).");
  }
}
