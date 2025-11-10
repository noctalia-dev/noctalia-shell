pragma Singleton

import QtQuick
import Quickshell

Singleton {
  id: root

  // Simple signal-based notification system
  signal notify(string message, string description, string icon, string type, int duration)

  // Convenience methods
  function showNotice(message, description = "", icon = "", duration = 3000) {
    notify(message, description, icon, "notice", duration)
  }

  function showWarning(message, description = "", duration = 4000) {
    notify(message, description, "", "warning", duration)
  }

  function showError(message, description = "", duration = 6000) {
    notify(message, description, "", "error", duration)
  }
}
