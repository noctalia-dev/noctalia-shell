pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Minimal settings singleton for noctalia-greet
Singleton {
  id: root

  // App dirs
  property string appName: "noctalia-greet"
  property string cacheDir: Quickshell.env("NOCTALIA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/" + appName + "/"
  property string settingsFile: cacheDir + "cache.json"

  // Debounced save
  Timer {
    id: saveTimer
    interval: 400
    repeat: false
    onTriggered: settingsFileView.writeAdapter()
  }

  // Ensure cache dir exists
  Item {
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.cacheDir])
  }

  // Persisted data (greet-specific cache)
  FileView {
    id: settingsFileView
    path: root.settingsFile
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: saveTimer.start()
    Component.onCompleted: reload()
    JsonAdapter {
      id: adapter
      // Remember last selected compositor/session id (e.g. hyprland, sway)
      property string lastSessionId: ""
    }
  }

  // Public alias to persisted fields
  readonly property alias data: adapter

  // Convenience getters/setters
  property string lastSessionId: adapter.lastSessionId
  function setLastSessionId(id) {
    adapter.lastSessionId = id || ""
    saveTimer.restart()
  }

  function save() {
    saveTimer.restart()
  }
}
