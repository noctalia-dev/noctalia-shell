pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI

/**
* IdleService — native idle detection via ext-idle-notify-v1 Wayland protocol.
*
* Three configurable stages:
*   1. Screen-off (DPMS)  — dims / turns off monitors
*   2. Lock screen        — activates the session lock
*   3. Suspend            — systemctl suspend
*
* IdleMonitor instances are created with Qt.createQmlObject() so the shell does
* not crash on compositors that lack the protocol.
*
* Timeouts come from Settings.data.idle (in minutes). 0 = disabled.
*
* NOTE: IdleMonitor.timeout is in seconds.
*/
Singleton {
  id: root

  // True if ext-idle-notify-v1 is supported by the compositor
  readonly property bool nativeIdleMonitorAvailable: _monitorsCreated

  // Live idle time in seconds (updated by the 1s heartbeat monitor)
  property int idleSeconds: 0

  property bool _monitorsCreated: false
  property var _screenOffMonitor: null
  property var _lockMonitor: null
  property var _suspendMonitor: null
  property var _heartbeatMonitor: null  // 1s monitor for live idle tracking

  // Signals for external listeners (plugins, modules)
  signal screenOffRequested
  signal lockRequested
  signal suspendRequested

  // -------------------------------------------------------
  function init() {
    Logger.i("IdleService", "Service started");
    _applyTimeouts();
  }

  // Re-apply when settings change
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root._applyTimeouts();
    }
  }

  // Watch for timeout changes at runtime
  Connections {
    target: Settings.data.idle
    function onScreenOffTimeoutChanged() {
      root._applyTimeouts();
    }
    function onLockTimeoutChanged() {
      root._applyTimeouts();
    }
    function onSuspendTimeoutChanged() {
      root._applyTimeouts();
    }
    function onEnabledChanged() {
      root._applyTimeouts();
    }
  }

  // Counts up idleSeconds while the heartbeat monitor reports idle
  Timer {
    id: idleCounter
    interval: 1000
    repeat: true
    onTriggered: root.idleSeconds++
  }

  // -------------------------------------------------------
  function _applyTimeouts() {
    const idle = Settings.data.idle;
    const globalEnabled = idle.enabled;

    _setMonitor("screenOff", globalEnabled ? idle.screenOffTimeout * 60 : 0);
    _setMonitor("lock", globalEnabled ? idle.lockTimeout * 60 : 0);
    _setMonitor("suspend", globalEnabled ? idle.suspendTimeout * 60 : 0);
    _ensureHeartbeat();
  }

  /**
  * Create, update, or destroy a stage IdleMonitor.
  * timeoutSec: seconds (already converted from minutes by caller). 0 = disabled.
  */
  function _setMonitor(stage, timeoutSec) {
    const propName = "_" + stage + "Monitor";
    const existing = root[propName];

    if (timeoutSec <= 0) {
      if (existing) {
        existing.destroy();
        root[propName] = null;
        Logger.d("IdleService", stage + " monitor disabled");
      }
      return;
    }

    if (existing) {
      if (existing.timeout !== timeoutSec) {
        existing.timeout = timeoutSec;
        Logger.d("IdleService", stage + " monitor timeout updated to", timeoutSec, "s");
      }
      return;
    }

    try {
      const qml = `
        import Quickshell.Wayland
        IdleMonitor { timeout: ${timeoutSec} }
      `;

      const monitor = Qt.createQmlObject(qml, root, "IdleMonitor_" + stage);
      monitor.isIdleChanged.connect(function () {
        if (monitor.isIdle) {
          root._onIdle(stage);
        }
      });
      root[propName] = monitor;
      root._monitorsCreated = true;
      Logger.i("IdleService", stage + " monitor created, timeout", timeoutSec, "s");
    } catch (e) {
      Logger.w("IdleService", "IdleMonitor not available (compositor lacks ext-idle-notify-v1):", e);
      root._monitorsCreated = false;
    }
  }

  // 1-second heartbeat monitor for live idle time tracking.
  // Always active so the settings panel can display current idle time.
  function _ensureHeartbeat() {
    if (_heartbeatMonitor)
      return;
    try {
      const qml = `
        import Quickshell.Wayland
        IdleMonitor { timeout: 1 }
      `;

      const monitor = Qt.createQmlObject(qml, root, "IdleMonitor_heartbeat");
      monitor.isIdleChanged.connect(function () {
        if (monitor.isIdle) {
          idleCounter.start();
        } else {
          idleCounter.stop();
          root.idleSeconds = 0;
        }
      });
      _heartbeatMonitor = monitor;
      root._monitorsCreated = true;
      Logger.d("IdleService", "Heartbeat monitor created");
    } catch (e) {
      Logger.w("IdleService", "Heartbeat monitor failed:", e);
    }
  }

  function _onIdle(stage) {
    Logger.i("IdleService", "Idle fired:", stage);
    if (stage === "screenOff") {
      CompositorService.turnOffMonitors();
      root.screenOffRequested();
    } else if (stage === "lock") {
      if (PanelService.lockScreen && !PanelService.lockScreen.active) {
        PanelService.lockScreen.active = true;
      }
      root.lockRequested();
    } else if (stage === "suspend") {
      CompositorService.suspend();
      root.suspendRequested();
    }
  }
}
