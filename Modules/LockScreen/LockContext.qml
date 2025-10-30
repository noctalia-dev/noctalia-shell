import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.Commons

Scope {
  id: root
  signal unlocked
  signal failed

  property string password: ""
  property bool unlockInProgress: false
  property bool showFailure: false
  property string errorMessage: ""
  property string infoMessage: ""
  property bool pamAvailable: typeof PamContext !== "undefined"

  function tryUnlock() {
    if (!pamAvailable) {
      errorMessage = "PAM not available"
      showFailure = true
      return
    }

    root.unlockInProgress = true
    errorMessage = ""
    showFailure = false

    Logger.i("LockContext", "Starting PAM authentication for user:", pam.user)
    pam.start()
  }

  PamContext {
    id: pam
    config: "login"
    user: Quickshell.env("USER")

    onPamMessage: {
      Logger.i("LockContext", "PAM message:", message, "isError:", messageIsError, "responseRequired:", responseRequired)

      if (messageIsError) {
        errorMessage = message
      } else {
        infoMessage = message
      }

      if (responseRequired) {
        Logger.i("LockContext", "Responding to PAM with password")
        respond(root.password)
      }
    }

    onResponseRequiredChanged: {
      Logger.i("LockContext", "Response required changed:", responseRequired)
      if (responseRequired && root.unlockInProgress) {
        Logger.i("LockContext", "Automatically responding to PAM")
        respond(root.password)
      }
    }

    onCompleted: result => {
                   Logger.i("LockContext", "PAM completed with result:", result)
                   if (result === PamResult.Success) {
                     Logger.i("LockContext", "Authentication successful")
                     root.unlocked()
                   } else {
                     Logger.i("LockContext", "Authentication failed")
                     errorMessage = "Authentication failed"
                     showFailure = true
                     root.failed()
                   }
                   root.unlockInProgress = false
                 }

    onError: {
      Logger.i("LockContext", "PAM error:", error, "message:", message)
      errorMessage = message || "Authentication error"
      showFailure = true
      root.unlockInProgress = false
      root.failed()
    }
  }
}
