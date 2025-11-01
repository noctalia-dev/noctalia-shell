pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  // Public properties
  property string baseVersion: "2.21.1"
  property bool isDevelopment: true

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
