pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  // Public properties
  property string baseVersion: "3.1.0"
  property bool isDevelopment: false

  property string currentVersion: `v${!isDevelopment ? baseVersion : baseVersion + "-dev"}`

  // Internal helpers
  function getVersion() {
    return root.currentVersion
  }

  function checkForUpdates() {
    // TODO: Implement update checking logic
    Logger.i("UpdateService", "Checking for updates...")
  }

  function init() {
    // Ensure the singleton is created
    Logger.i("UpdateService", "Version:", root.currentVersion)
  }
}
