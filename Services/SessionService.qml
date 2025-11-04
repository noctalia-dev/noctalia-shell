pragma Singleton

import QtQuick

import Quickshell
import Quickshell.Io

import qs.Commons

Singleton {
  id: root

  readonly property string sessionsDir: Quickshell.env("NOCTALIA_GREETER_SESSIONS_DIR")
  readonly property string preferredSessionIdentifier: Quickshell.env("NOCTALIA_GREETER_PREFERRED_SESSION")
  readonly property string defaultSessionIdentifier: preferredSessionIdentifier || GreeterSettings.data.lastSessionIdentifier

  property int currentSessionIndex: 0
  // [{identifier: string, name: string, command: string}]
  property list<var> availableSessions: []

  readonly property string currentSessionName: availableSessions[currentSessionIndex]?.name ?? "Niri"
  readonly property string currentSessionCommand: availableSessions[currentSessionIndex]?.command ?? "niri-session"

  Connections {
    target: GreeterSettings
    function onSettingsLoaded() {
      root.selectDefaultSession()
    }
  }

  function selectDefaultSession() {
    if (defaultSessionIdentifier) {
      for (var i = 0; i < availableSessions.length; i++) {
        if (availableSessions[i].identifier === defaultSessionIdentifier) {
          currentSessionIndex = i
          break
        }
      }
    }
  }

  function selectSession(index) {
    currentSessionIndex = index
    GreeterSettings.data.lastSessionIdentifier = availableSessions[index].identifier
  }

  Process {
    id: sessions

    command: [Quickshell.shellDir + "/Assets/Greeter/scripts/session.sh", root.sessionsDir || ""]
    running: true

    stderr: SplitParser {
      onRead: data => Logger.e("Sessions", "Failed to read session: " + data)
    }

    stdout: SplitParser {
      onRead: data => {
        const parsedData = data.split(",")
        const sessionIdentifier = parsedData[0]
        const sessionName = parsedData[1]
        const sessionCommand = parsedData[2]

        Logger.i("Sessions", "Found session: " + sessionName)
        root.availableSessions.push({
                                      "identifier": sessionIdentifier,
                                      "name": sessionName,
                                      "command": sessionCommand
                                    })

        if (sessionIdentifier == root.defaultSessionIdentifier) {
          Logger.i("Sessions", "'" + sessionName + "' is now the preferred session")
          const sessionIndex = root.availableSessions.length - 1
          root.currentSessionIndex = sessionIndex
        }
      }
    }
  }
}
