pragma Singleton

import QtQuick
import QtQuick.Controls

import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

import qs.Commons
import qs.Services

Singleton {
  id: root

  readonly property bool debug: Quickshell.env("NOCTALIA_GREETER_DEBUG") === "1" || Quickshell.env("NOCTALIA_GREETER_DEBUG") === "true"
  readonly property string debug_password: "debug"
  property bool debug_idle: true

  readonly property bool idle: debug ? debug_idle : Greetd.state == GreetdState.Inactive

  property string password: ""

  property bool showFailure: false
  property string errorMessage: ""

  signal unlocked

  function authenticate(username, password) {
    root.password = password

    if (debug) {
      debug_idle = false
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
        if (root.password === debug_password) {
          root.unlocked()
          Qt.quit()
        } else {
          root.showFailure = true
          root.errorMessage = "Invalid password"
        }
        debug_idle = true
      }
    }
  }
}
