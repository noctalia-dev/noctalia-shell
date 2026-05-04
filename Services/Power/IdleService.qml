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
* Timeouts come from Settings.data.idle (in seconds). 0 = disabled.
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
  property var _customMonitors: ({})
  property var _queuedStages: []
  property bool _screenOffActive: false

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
      root._executeAction(action);
      overlayCleanupTimer.start();
    }
  }

  Timer {
    id: overlayCleanupTimer
    interval: 500
    repeat: false
    onTriggered: {
      root.fadePending = "";
      root._runNextQueuedStage();
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
    if (fadePending === "") {
      _queuedStages = [];
      _restoreMonitors();
      return;
    }
    Logger.i("IdleService", "Fade cancelled for:", fadePending);
    fadePending = "";
    _queuedStages = [];
    graceTimer.stop();
    overlayCleanupTimer.stop();
    _restoreMonitors();
  }

  function _restoreMonitors() {
    if (!_screenOffActive)
      return;
    _screenOffActive = false;
    Logger.i("IdleService", "Restoring monitors (DPMS on)");
    CompositorService.turnOnMonitors();

    if (Settings.data.idle.resumeScreenOffCommand) {
      Logger.i("IdleService", "Executing screen-off resume command");
      Quickshell.execDetached(["sh", "-c", Settings.data.idle.resumeScreenOffCommand]);
    }
  }

  function _queueStage(stage) {
    if (!_isValidStage(stage)) {
      Logger.w("IdleService", "Ignoring unknown queued stage:", stage);
      return;
    }
    if (stage === fadePending)
      return;
    if (_queuedStages.indexOf(stage) !== -1)
      return;
    _queuedStages.push(stage);
    Logger.d("IdleService", "Queued idle stage while fade is active:", stage);
  }

  function _isValidStage(stage) {
    return stage === "screenOff" || stage === "lock" || stage === "suspend";
  }

  function _isStageEnabled(stage) {
    const idle = Settings.data.idle;
    if (stage === "screenOff")
      return idle.screenOffTimeout > 0;
    if (stage === "lock")
      return idle.lockTimeout > 0;
    if (stage === "suspend")
      return idle.suspendTimeout > 0;
    return false;
  }

  function _runNextQueuedStage() {
    if (fadePending !== "")
      return;
    if (idleSeconds <= 0) {
      _queuedStages = [];
      return;
    }

    while (_queuedStages.length > 0) {
      const nextStage = _queuedStages.shift();
      if (!_isValidStage(nextStage)) {
        Logger.w("IdleService", "Dropping queued unknown stage:", nextStage);
        continue;
      }
      if (!_isStageEnabled(nextStage)) {
        Logger.d("IdleService", "Dropping queued disabled stage:", nextStage);
        continue;
      }

      Logger.i("IdleService", "Running queued idle stage:", nextStage);
      _onIdle(nextStage);
      return;
    }
  }

  function _onIdle(stage) {
    if (!_isValidStage(stage)) {
      Logger.w("IdleService", "Idle fired with unknown stage:", stage);
      return;
    }
    if (!_isStageEnabled(stage)) {
      Logger.d("IdleService", "Ignoring idle stage because it is disabled:", stage);
      return;
    }

    if (fadePending !== "") {
      _queueStage(stage);
      return;
    }
    Logger.i("IdleService", "Idle fired:", stage);
    fadePending = stage;
    graceTimer.restart();
  }

  function _executeAction(stage) {
    Logger.i("IdleService", "Executing action:", stage);
    if (stage === "screenOff") {
      if (Settings.data.idle.screenOffCommand)
        Quickshell.execDetached(["sh", "-c", Settings.data.idle.screenOffCommand]);
      CompositorService.turnOffMonitors();
      root._screenOffActive = true;
      root.screenOffRequested();
    } else if (stage === "lock") {
      if (Settings.data.idle.lockCommand)
        Quickshell.execDetached(["sh", "-c", Settings.data.idle.lockCommand]);
      if (PanelService.lockScreen && !PanelService.lockScreen.active) {
        PanelService.lockScreen.active = true;
      }
      root.lockRequested();
    } else if (stage === "suspend") {
      if (Settings.data.idle.suspendCommand)
        Quickshell.execDetached(["sh", "-c", Settings.data.idle.suspendCommand]);
      if (Settings.data.general.lockOnSuspend) {
        CompositorService.lockAndSuspend();
      } else {
        CompositorService.suspend();
      }
      root.suspendRequested();
    } else {
      Logger.w("IdleService", "Unknown idle stage action:", stage);
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
    function onCustomCommandsChanged() {
      root._applyCustomMonitors();
    }
  }

  function _applyTimeouts() {
    const idle = Settings.data.idle;
    const globalEnabled = idle.enabled;

    _setMonitor("screenOff", globalEnabled ? idle.screenOffTimeout : 0);
    _setMonitor("lock", globalEnabled ? idle.lockTimeout : 0);
    _setMonitor("suspend", globalEnabled ? idle.suspendTimeout : 0);
    _ensureHeartbeat();
    _applyCustomMonitors();
  }

  function _applyCustomMonitors() {
    // Destroy all existing custom monitors
    for (var key in _customMonitors) {
      if (_customMonitors[key]) {
        _customMonitors[key].destroy();
      }
    }
    root._customMonitors = {};

    const idle = Settings.data.idle;
    if (!idle.enabled)
      return;

    var entries = [];
    try {
      entries = JSON.parse(idle.customCommands);
    } catch (e) {
      Logger.w("IdleService", "Failed to parse customCommands:", e);
      return;
    }

    var newMonitors = {};
    for (var i = 0; i < entries.length; i++) {
      const entry = entries[i];
      const timeoutSec = parseInt(entry.timeout);
      const cmd = entry.command;
      const resumeCmd = entry.resumeCommand || "";
      if (!cmd && !resumeCmd || timeoutSec <= 0)
        continue;
      try {
        const qml = `
          import Quickshell.Wayland
          IdleMonitor { timeout: ${timeoutSec} }
        `;

        const monitor = Qt.createQmlObject(qml, root, "IdleMonitor_custom_" + i);
        const capturedCmd = cmd;
        const capturedResumeCmd = resumeCmd;
        monitor.isIdleChanged.connect(function () {
          if (monitor.isIdle) {
            if (capturedCmd)
              root._executeCustomCommand(capturedCmd);
          } else {
            if (capturedResumeCmd)
              root._executeCustomCommand(capturedResumeCmd);
          }
        });
        newMonitors[i] = monitor;
        root._monitorsCreated = true;
        Logger.i("IdleService", "Custom monitor " + i + " created, timeout", timeoutSec, "s");
      } catch (e) {
        Logger.w("IdleService", "Failed to create custom monitor " + i + ":", e);
      }
    }
    root._customMonitors = newMonitors;
  }

  function _executeCustomCommand(cmd) {
    Logger.i("IdleService", "Executing custom command:", cmd);
    Quickshell.execDetached(["sh", "-c", cmd]);
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
          root.idleSeconds = 1;
          idleCounter.start();
        } else {
          idleCounter.stop();
          root.idleSeconds = 0;
          if (root.fadePending === "lock" && Settings.data.idle.resumeLockCommand) {
            Logger.i("IdleService", "Executing lock resume command");
            Quickshell.execDetached(["sh", "-c", Settings.data.idle.resumeLockCommand]);
          } else if (root.fadePending === "suspend" && Settings.data.idle.resumeSuspendCommand) {
            Logger.i("IdleService", "Executing suspend resume command");
            Quickshell.execDetached(["sh", "-c", Settings.data.idle.resumeSuspendCommand]);
          }
          root.cancelFade();
          overlayCleanupTimer.stop();
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
