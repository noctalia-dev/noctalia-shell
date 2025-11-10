pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  property bool isInhibited: false
  property string reason: I18n.tr("system.user-requested")
  property var activeInhibitors: []

  // Different inhibitor strategies
  property string strategy: "systemd" // "systemd", "wayland", or "auto"

  function init() {
    Logger.i("IdleInhibitor", "Service started")
    detectStrategy()
  }

  // Auto-detect the best strategy
  function detectStrategy() {
    if (strategy === "auto") {
      // Check if systemd-inhibit is available
      try {
        var systemdResult = Quickshell.execDetached(["which", "systemd-inhibit"])
        strategy = "systemd"
        Logger.d("IdleInhibitor", "Using systemd-inhibit strategy")
        return
      } catch (e) {

        // systemd-inhibit not found, try Wayland tools
      }

      try {
        var waylandResult = Quickshell.execDetached(["which", "wayhibitor"])
        strategy = "wayland"
        Logger.d("IdleInhibitor", "Using wayhibitor strategy")
        return
      } catch (e) {

        // wayhibitor not found
      }

      Logger.w("IdleInhibitor", "No suitable inhibitor found - will try systemd as fallback")
      strategy = "systemd" // Fallback to systemd even if not detected
    }
  }

  // Add an inhibitor
  function addInhibitor(id, reason = "Application request") {
    if (activeInhibitors.includes(id)) {
      Logger.w("IdleInhibitor", "Inhibitor already active:", id)
      return false
    }

    activeInhibitors.push(id)
    updateInhibition(reason)
    Logger.d("IdleInhibitor", "Added inhibitor:", id)
    return true
  }

  // Remove an inhibitor
  function removeInhibitor(id) {
    const index = activeInhibitors.indexOf(id)
    if (index === -1) {
      Logger.w("IdleInhibitor", "Inhibitor not found:", id)
      return false
    }

    activeInhibitors.splice(index, 1)
    updateInhibition()
    Logger.d("IdleInhibitor", "Removed inhibitor:", id)
    return true
  }

  // Update the actual system inhibition
  function updateInhibition(newReason = reason) {
    const shouldInhibit = activeInhibitors.length > 0

    if (shouldInhibit === isInhibited) {
      return
      // No change needed
    }

    if (shouldInhibit) {
      startInhibition(newReason)
    } else {
      stopInhibition()
    }
  }

  // Start system inhibition
  function startInhibition(newReason) {
    reason = newReason

    if (strategy === "systemd") {
      startSystemdInhibition()
    } else if (strategy === "wayland") {
      startWaylandInhibition()
    } else {
      Logger.w("IdleInhibitor", "No inhibition strategy available")
      return
    }

    isInhibited = true
    Logger.i("IdleInhibitor", "Started inhibition:", reason)
  }

  // Stop system inhibition
  function stopInhibition() {
    if (!isInhibited)
      return

    if (inhibitorProcess.running) {
      inhibitorProcess.signal(15) // SIGTERM
    }

    isInhibited = false
    Logger.i("IdleInhibitor", "Stopped inhibition")
  }

  // Systemd inhibition using systemd-inhibit
  function startSystemdInhibition() {
    inhibitorProcess.command = ["systemd-inhibit", "--what=idle", "--why=" + reason, "--mode=block", "sleep", "infinity"]
    inhibitorProcess.running = true
  }

  // Wayland inhibition using wayhibitor or similar
  function startWaylandInhibition() {
    inhibitorProcess.command = ["wayhibitor"]
    inhibitorProcess.running = true
  }

  // Process for maintaining the inhibition
  Process {
    id: inhibitorProcess
    running: false

    onExited: function (exitCode, exitStatus) {
      if (isInhibited) {
        Logger.w("IdleInhibitor", "Inhibitor process exited unexpectedly:", exitCode)
        isInhibited = false
      }
    }

    onStarted: function () {
      Logger.d("IdleInhibitor", "Inhibitor process started successfully")
    }
  }

  // Manual toggle for user control
  function manualToggle() {
    if (activeInhibitors.includes("manual")) {
      removeInhibitor("manual")
      ToastService.showNotice(I18n.tr("tooltips.keep-awake"), I18n.tr("toast.keep-awake.disabled"), "keep-awake-off")
      Logger.i("IdleInhibitor", "Manual inhibition disabled")
      return false
    } else {
      addInhibitor("manual", "Manually activated by user")
      ToastService.showNotice(I18n.tr("tooltips.keep-awake"), I18n.tr("toast.keep-awake.enabled"), "keep-awake-on")
      Logger.i("IdleInhibitor", "Manual inhibition enabled (will reset on next session)")
      return true
    }
  }

  // Clean up on shutdown
  Component.onDestruction: {
    stopInhibition()
  }
}
