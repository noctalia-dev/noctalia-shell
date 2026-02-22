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
* Each stage shows a fade-to-black overlay for a configurable grace period
* before executing the action. Any mouse movement cancels the fade.
*
* IdleMonitor instances are created with Qt.createQmlObject() so the shell
* does not crash on compositors that lack the protocol.
*
* Timeouts come from Settings.data.idle (in minutes). 0 = disabled.
* NOTE: IdleMonitor.timeout is in seconds.
*/
Singleton {
  id: root

  // True if ext-idle-notify-v1 is supported by the compositor
  readonly property bool nativeIdleMonitorAvailable: _monitorsCreated

  // Live idle time in seconds (updated by the 1s heartbeat monitor)
  property int idleSeconds: 0

  // Fade overlay state — "" means no fade in progress
  property string fadePending: ""
  readonly property int fadeDuration: Settings.data.idle.fadeDuration

  property bool _monitorsCreated: false
  property var _screenOffMonitor: null
  property var _lockMonitor: null
  property var _suspendMonitor: null
  property var _heartbeatMonitor: null

  // Signals for external listeners (plugins, modules)
  signal screenOffRequested
  signal lockRequested
  signal suspendRequested

  // -------------------------------------------------------
  function init() {
    Logger.i("IdleService", "Service started");
    _applyTimeouts();
  }

  // Grace period timer — fires when fade completes without cancellation
  Timer {
    id: graceTimer
    interval: root.fadeDuration * 1000
    repeat: false
    onTriggered: {
      const action = root.fadePending;
      root.fadePending = "";
      root._executeAction(action);
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
  function cancelFade() {
    if (fadePending === "")
      return;
    Logger.i("IdleService", "Fade cancelled for:", fadePending);
    fadePending = "";
    graceTimer.stop();
  }

  function _onIdle(stage) {
    // Don't re-trigger if already fading something
    if (fadePending !== "")
      return;
    Logger.i("IdleService", "Idle fired:", stage);
    fadePending = stage;
    graceTimer.restart();
  }

  function _executeAction(stage) {
    Logger.i("IdleService", "Executing action:", stage);
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

  // -------------------------------------------------------
  // Re-apply when settings change
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root._applyTimeouts();
    }
  }

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

  function _applyTimeouts() {
    const idle = Settings.data.idle;
    const globalEnabled = idle.enabled;

    _setMonitor("screenOff", globalEnabled ? idle.screenOffTimeout * 60 : 0);
    _setMonitor("lock", globalEnabled ? idle.lockTimeout * 60 : 0);
    _setMonitor("suspend", globalEnabled ? idle.suspendTimeout * 60 : 0);
    _ensureHeartbeat();
  }

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
      if (existing.timeout === timeoutSec)
        return;
      // ext-idle-notify-v1 has no update-timeout request — must recreate
      existing.destroy();
      root[propName] = null;
      Logger.d("IdleService", stage + " monitor timeout changed to", timeoutSec, "s, recreating");
    }

    try {
      const qml = `
        import Quickshell.Wayland
        IdleMonitor { timeout: ${timeoutSec} }
      `;

      const monitor = Qt.createQmlObject(qml, root, "IdleMonitor_" + stage);
      monitor.isIdleChanged.connect(function () {
        if (monitor.isIdle)
          root._onIdle(stage);
        else
          root.cancelFade();
      });
      root[propName] = monitor;
      root._monitorsCreated = true;
      Logger.i("IdleService", stage + " monitor created, timeout", timeoutSec, "s");
    } catch (e) {
      Logger.w("IdleService", "IdleMonitor not available (compositor lacks ext-idle-notify-v1):", e);
      root._monitorsCreated = false;
    }
  }

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
          root.cancelFade();
        }
      });
      _heartbeatMonitor = monitor;
      root._monitorsCreated = true;
      Logger.d("IdleService", "Heartbeat monitor created");
    } catch (e) {
      Logger.w("IdleService", "Heartbeat monitor failed:", e);
    }
  }
}
