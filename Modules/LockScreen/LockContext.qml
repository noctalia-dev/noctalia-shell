import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.Commons
import qs.Services.System

Scope {
  id: root
  signal unlocked
  signal failed

  property string currentText: ""
  property bool waitingForPassword: false
  property bool unlockInProgress: false
  property bool showFailure: false
  property bool showInfo: false
  property string errorMessage: ""
  property string infoMessage: ""
  property bool pamAvailable: typeof PamContext !== "undefined"

  // Determine PAM config based on OS
  // On NixOS: use /etc/pam.d/login
  // Otherwise: use generated config in configDir
  readonly property string pamConfigDirectory: {
    if (HostService.isReady && HostService.isNixOS) {
      return "/etc/pam.d";
    }
    return Settings.configDir + "pam";
  }
  readonly property string pamConfig: {
    if (HostService.isReady && HostService.isNixOS) {
      return "login";
    }
    return "password.conf";
  }

  Component.onCompleted: {
    if (HostService.isReady) {
      if (HostService.isNixOS) {
        Logger.i("LockContext", "NixOS detected, using system PAM config: /etc/pam.d/login");
      } else {
        Logger.i("LockContext", "Using generated PAM config:", pamConfigDirectory + "/" + pamConfig);
      }
    } else {
      // Wait for HostService to be ready
      HostService.isReadyChanged.connect(function () {
        if (HostService.isNixOS) {
          Logger.i("LockContext", "NixOS detected, using system PAM config: /etc/pam.d/login");
        } else {
          Logger.i("LockContext", "Using generated PAM config:", pamConfigDirectory + "/" + pamConfig);
        }
      });
    }
  }

  onCurrentTextChanged: {
    if (currentText !== "") {
      showInfo = false;
      infoMessage = "";
      showFailure = false;
      errorMessage = "";
    }
  }

  function tryUnlock() {
    if (!pamAvailable) {
      errorMessage = "PAM not available";
      showFailure = true;
      return;
    }

    if (waitingForPassword) {
      pam.respond(currentText);
      waitingForPassword = false;
      showInfo = false;
      return;
    }

    if (root.unlockInProgress) {
      Logger.i("LockContext", "Unlock already in progress, ignoring duplicate attempt");
      return;
    }

    root.unlockInProgress = true;
    errorMessage = "";
    showFailure = false;

    Logger.i("LockContext", "Starting PAM authentication for user:", pam.user);
    pam.start();
  }

  PamContext {
    id: pam
    // Use custom PAM config to ensure predictable password-only authentication
    // On NixOS: uses /etc/pam.d/login
    // Otherwise: uses config created in Settings.qml and stored in configDir/pam/
    configDirectory: root.pamConfigDirectory
    config: root.pamConfig
    user: HostService.username

    onPamMessage: {
      Logger.i("LockContext", "PAM message:", message, "isError:", messageIsError, "responseRequired:", responseRequired);

      if (messageIsError) {
        errorMessage = message;
      } else {
        infoMessage = message;
      }

      if (this.responseRequired) {
        Logger.i("LockContext", "Responding to PAM with password");
        if (root.currentText !== "") {
          this.respond(root.currentText);
        } else {
          root.waitingForPassword = true;
          showFailure = false;
          infoMessage = I18n.tr("lock-screen.password");
          showInfo = true;
        }
      } else if (messageIsError) {
        showInfo = false;
        showFailure = true;
      } else {
        showFailure = false;
        showInfo = true;
      }
    }

    onCompleted: result => {
                   Logger.i("LockContext", "PAM completed with result:", result);
                   if (result === PamResult.Success) {
                     Logger.i("LockContext", "Authentication successful");
                     root.unlocked();
                   } else {
                     Logger.i("LockContext", "Authentication failed");
                     root.currentText = "";
                     errorMessage = I18n.tr("authentication.failed");
                     showFailure = true;
                     root.failed();
                   }
                   root.unlockInProgress = false;
                 }

    onError: {
      Logger.i("LockContext", "PAM error:", error, "message:", message);
      errorMessage = message || "Authentication error";
      showFailure = true;
      root.unlockInProgress = false;
      root.failed();
    }
  }
}
