pragma Singleton

import QtQuick

import Quickshell
import Quickshell.Services.Greetd

import qs.Services

Singleton {
  id: root

  readonly property bool debug: Quickshell.env("NOCTALIA_GREETER_DEBUG") === "1" || Quickshell.env("NOCTALIA_GREETER_DEBUG") === "true"
  readonly property string debugPassword: "debug"
  property bool debugIdle: true

  readonly property bool idle: debug ? debugIdle : Greetd.state == GreetdState.Inactive

  property string password: ""

  property bool showFailure: false
  property string errorMessage: ""

  signal unlocked

  function authenticate(username, password) {
    root.password = password

    if (debug) {
      debugIdle = false
      debugUnlock.restart()
      return
    }

    if (idle) {
      Greetd.createSession(username)
    }
  }

  Connections {
    target: Greetd

    function onAuthMessage(message, error, responseRequired, echoResponse) {
      console.log("[GREETD] msg='" + message + "' err='" + error + "' resreq=" + responseRequired + " echo=" + echoResponse)

      if (responseRequired) {
        Greetd.respond(root.password)
        return
      }

      // Finger print support
      Greetd.respond("")
    }

    function onReadyToLaunch() {
      root.unlocked()
      console.log("[GREETD EXEC] " + SessionService.currentSessionCommand)
      Greetd.launch(SessionService.currentSessionCommand.split(" "), [], true)
    }

    function onAuthFailure(message) {
      root.showFailure = true
      root.errorMessage = message
    }
  }

  Timer {
    id: debugUnlock
    interval: 1000

    onTriggered: {
      if (root.debug) {
        if (root.password === root.debugPassword) {
          root.unlocked()
          Qt.quit()
        } else {
          root.showFailure = true
          root.errorMessage = "Invalid password"
        }
        root.debugIdle = true
      }
    }
  }
}
