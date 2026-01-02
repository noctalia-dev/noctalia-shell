pragma Singleton

import QtQuick
import Quickshell

Singleton {
  id: root

  // Simple signal-based notification system
  // actionLabel: optional label for clickable action link
  // actionCallback: optional function to call when action is clicked
  signal notify(string title, string description, string icon, string type, int duration, string actionLabel, var actionCallback)

  // Convenience methods
  function showNotice(title, description = "", icon = "", duration = 3000, actionLabel = "", actionCallback = null) {
    notify(title, description, icon, "notice", duration, actionLabel, actionCallback);
  }

  function showWarning(title, description = "", duration = 4000, actionLabel = "", actionCallback = null) {
    notify(title, description, "", "warning", duration, actionLabel, actionCallback);
  }

  function showError(title, description = "", duration = 6000, actionLabel = "", actionCallback = null) {
    notify(title, description, "", "error", duration, actionLabel, actionCallback);
  }
}
