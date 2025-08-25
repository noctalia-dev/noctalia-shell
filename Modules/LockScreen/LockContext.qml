import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.Commons

Scope {
  id: root
  signal unlocked
  signal failed

  property string currentText: ""
  property bool unlockInProgress: false
  property bool showFailure: false
  property string errorMessage: ""
  property bool pamAvailable: typeof PamContext !== "undefined"

  onCurrentTextChanged: {
    if (currentText !== "") {
      showFailure = false
      errorMessage = ""
    }
  }

  function tryUnlock() {
    if (!pamAvailable) {
      errorMessage = "PAM not available"
      showFailure = true
      return
    }

    if (currentText === "") {
      errorMessage = "Password required"
      showFailure = true
      return
    }

    root.unlockInProgress = true
    errorMessage = ""
    showFailure = false

    Logger.log("LockContext", "Starting PAM authentication for user:", pam.user)
    pam.start()
  }

  PamContext {
    id: pam
    config: "login"
    user: Quickshell.env("USER")

    onPamMessage: {
      Logger.log("LockContext", "PAM message:", message, "isError:", messageIsError, "responseRequired:",
                 responseRequired)

      if (messageIsError) {
        errorMessage = message
      }

      if (responseRequired) {
        Logger.log("LockContext", "Responding to PAM with password")
        respond(root.currentText)
      }
    }

    onResponseRequiredChanged: {
      Logger.log("LockContext", "Response required changed:", responseRequired)
      if (responseRequired && root.unlockInProgress) {
        Logger.log("LockContext", "Automatically responding to PAM")
        respond(root.currentText)
      }
    }

    onCompleted: result => {
                   Logger.log("LockContext", "PAM completed with result:", result)
                   if (result === PamResult.Success) {
                     Logger.log("LockContext", "Authentication successful")
                     root.unlocked()
                   } else {
                     Logger.log("LockContext", "Authentication failed")
                     errorMessage = "Authentication failed"
                     showFailure = true
                     root.failed()
                   }
                   root.unlockInProgress = false
                 }

    onError: {
      Logger.log("LockContext", "PAM error:", error, "message:", message)
      errorMessage = message || "Authentication error"
      showFailure = true
      root.unlockInProgress = false
      root.failed()
    }
  }
}
