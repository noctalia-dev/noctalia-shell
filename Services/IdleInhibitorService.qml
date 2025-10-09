pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services

Singleton {
  id: root

  property bool isInhibited: false
  property string reason: I18n.tr("system.user-requested")
  property var activeInhibitors: []

  // Different inhibitor strategies
  property string strategy: "systemd" // "systemd", "wayland", or "auto"

  Component.onCompleted: {
    Logger.log("IdleInhibitor", "Service started")
    detectStrategy()

    // Restore previous state from settings
    if (Settings.data.ui.idleInhibitorEnabled) {
      addInhibitor("manual", "Restored from previous session")
      Logger.log("IdleInhibitor", "Restored previous manual inhibition state")
    }
  }

  // Auto-detect the best strategy
  function detectStrategy() {
    if (strategy === "auto") {
      // Check if systemd-inhibit is available
      try {
        var systemdResult = Quickshell.execDetached(["which", "systemd-inhibit"])
        strategy = "systemd"
        Logger.log("IdleInhibitor", "Using systemd-inhibit strategy")
        return
      } catch (e) {

        // systemd-inhibit not found, try Wayland tools
      }

      try {
        var waylandResult = Quickshell.execDetached(["which", "wayhibitor"])
        strategy = "wayland"
        Logger.log("IdleInhibitor", "Using wayhibitor strategy")
        return
      } catch (e) {

        // wayhibitor not found
      }

      Logger.warn("IdleInhibitor", "No suitable inhibitor found - will try systemd as fallback")
      strategy = "systemd" // Fallback to systemd even if not detected
    }
  }

  // Add an inhibitor
  function addInhibitor(id, reason = "Application request") {
    if (activeInhibitors.includes(id)) {
      Logger.warn("IdleInhibitor", "Inhibitor already active:", id)
      return false
    }

    activeInhibitors.push(id)
    updateInhibition(reason)
    Logger.log("IdleInhibitor", "Added inhibitor:", id)
    return true
  }

  // Remove an inhibitor
  function removeInhibitor(id) {
    const index = activeInhibitors.indexOf(id)
    if (index === -1) {
      Logger.warn("IdleInhibitor", "Inhibitor not found:", id)
      return false
    }

    activeInhibitors.splice(index, 1)
    updateInhibition()
    Logger.log("IdleInhibitor", "Removed inhibitor:", id)
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
      Logger.warn("IdleInhibitor", "No inhibition strategy available")
      return
    }

    isInhibited = true
    Logger.log("IdleInhibitor", "Started inhibition:", reason)
  }

  // Stop system inhibition
  function stopInhibition() {
    if (!isInhibited)
      return

    if (inhibitorProcess.running) {
      inhibitorProcess.signal(15) // SIGTERM
    }

    isInhibited = false
    Logger.log("IdleInhibitor", "Stopped inhibition")
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
        Logger.warn("IdleInhibitor", "Inhibitor process exited unexpectedly:", exitCode)
        isInhibited = false
      }
    }

    onStarted: function () {
      Logger.log("IdleInhibitor", "Inhibitor process started successfully")
    }
  }

  // Manual toggle for user control
  function manualToggle() {
    if (activeInhibitors.includes("manual")) {
      removeInhibitor("manual")
      Settings.data.ui.idleInhibitorEnabled = false
      ToastService.showNotice(I18n.tr("tooltips.keep-awake"), I18n.tr("toast.keep-awake.disabled"))
      Logger.log("IdleInhibitor", "Manual inhibition disabled and saved to settings")
      return false
    } else {
      addInhibitor("manual", "Manually activated by user")
      Settings.data.ui.idleInhibitorEnabled = true
      ToastService.showNotice(I18n.tr("tooltips.keep-awake"), I18n.tr("toast.keep-awake.enabled"))
      Logger.log("IdleInhibitor", "Manual inhibition enabled and saved to settings")
      return true
    }
  }

  // Clean up on shutdown
  Component.onDestruction: {
    stopInhibition()
  }
}
