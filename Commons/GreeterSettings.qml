pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Minimal settings singleton for noctalia-greet
Singleton {
  id: root
  readonly property alias data: adapter

  signal settingsLoaded

  // Ensure cache dir exists
  Item {
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", Settings.cacheDir])
  }

  // Debounced save
  Timer {
    id: saveTimer
    interval: 400
    repeat: false
    onTriggered: settingsFileView.writeAdapter()
  }

  // Persisted data (greet-specific cache)
  FileView {
    id: settingsFileView
    path: Settings.cacheDir + "greeter.json"
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: saveTimer.start()
    Component.onCompleted: reload()

    onLoaded: {
      root.settingsLoaded()
    }

    JsonAdapter {
      id: adapter

      // niri, gnome
      property string lastSessionIdentifier: ""
    }
  }
}
