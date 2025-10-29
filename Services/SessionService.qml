pragma Singleton

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

import qs.Commons

Singleton {
  id: root

  readonly property string sessions: Quickshell.env("NOCTALIA_GREETER_AVAILABLE_SESSIONS") || ""
  readonly property string preferred_session: Quickshell.env("NOCTALIA_GREETER_PREFERRED_SESSION")

  property int current_ses_index: 0
  property string current_session: session_execs[current_ses_index] ?? "niri-session"
  property string current_session_name: session_names[current_ses_index] ?? "Niri"
  property list<string> session_execs: []
  property list<string> session_names: []
  property bool restoredFromSettings: false

  function next() {
    current_ses_index = (current_ses_index + 1) % session_execs.length
  }

  function moveToFront(index) {
    if (index <= 0 || index >= session_execs.length)
      return
    const exec = session_execs[index]
    const name = session_names[index]
    session_execs.splice(index, 1)
    session_names.splice(index, 1)
    session_execs.unshift(exec)
    session_names.unshift(name)
    current_ses_index = 0
  }

  Component.onCompleted: {
    if (root.sessions == "") {
      console.log("[WARN] empty sessions list, defaulting to niri")
      root.current_session = "niri-session"
      root.current_session_name = "Niri"
    }

    // Initialize session from saved settings after UI load (final check occurs after sessions load too)
    const saved = GreeterSettings.lastSessionId
    if (saved && root.session_execs.length > 0) {
      for (var i = 0; i < root.session_names.length; i++) {
        if (root.session_execs[i].toLowerCase().includes(saved.toLowerCase()) || root.session_names[i].toLowerCase().includes(saved.toLowerCase())) {
          root.current_ses_index = i
          break
        }
      }
    }
  }

  Process {
    id: sessions

    command: [Qt.resolvedUrl("../scripts/session.sh"), root.sessions]
    running: true

    stderr: SplitParser {
      onRead: data => console.log("[ERR] " + data)
    }

    stdout: SplitParser {
      onRead: data => {
        const parsedData = data.split(",")
        console.log("[SESSIONS] " + parsedData[2])
        if (parsedData[0] == root.preferred_session) {
          console.log("[INFO] Found preferred session " + root.preferred_session)
          sessions.current_ses_index = root.session_names.length
        }
        root.session_names.push(parsedData[1])
        root.session_execs.push(parsedData[2])
      }
    }

    onExited: {
      // After sessions populated, prefer saved session as first entry
      if (!restoredFromSettings && GreeterSettings.lastSessionId && session_execs.length > 0) {
        const saved = GreeterSettings.lastSessionId.toLowerCase()
        let idx = -1
        for (var i = 0; i < session_execs.length; i++) {
          if (session_execs[i].toLowerCase().includes(saved) || session_names[i].toLowerCase().includes(saved)) {
            idx = i
            break
          }
        }
        if (idx >= 0) {
          moveToFront(idx)
          restoredFromSettings = true
        }
      }
    }
  }
}
