import QtQuick
import Quickshell
import Quickshell.Io
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

  readonly property string pamConfigDirectory: "/etc/pam.d"
  property string pamConfig: Quickshell.env("NOCTALIA_PAM_SERVICE") || "login"
  property bool pamReady: false

  Component.onCompleted: {
    if (Quickshell.env("NOCTALIA_PAM_SERVICE")) {
      Logger.i("LockContext", "NOCTALIA_PAM_SERVICE is set, using system PAM config: /etc/pam.d/" + pamConfig);
      pamReady = true;
    } else {
      Logger.i("LockContext", "Probing for best PAM service...");
      detectPamServiceProc.running = true;
    }
  }

  Process {
    id: detectPamServiceProc
    command: ["sh", "-c", "
      if [ -f /etc/pam.d/login ]; then echo 'login'; exit 0; fi;
      if [ -f /etc/pam.d/system-auth ]; then echo 'system-auth'; exit 0; fi;
      if [ -f /etc/pam.d/common-auth ]; then echo 'common-auth'; exit 0; fi;
      echo 'login';
    "]
    stdout: StdioCollector {
      onStreamFinished: {
        const service = String(text || "").trim();
        if (service.length > 0) {
          root.pamConfig = service;
          Logger.i("LockContext", "Detected PAM service: " + service);
        } else {
          Logger.w("LockContext", "Failed to detect PAM service, defaulting to login");
        }
        root.pamReady = true;
      }
    }
    stderr: StdioCollector {}
  }

  onPamReadyChanged: {
    if (pamReady) {
      if (Settings.data.general.autoStartAuth && currentText === "") {
        pam.start();
      }
    }
  }

  onShowInfoChanged: {
    if (showInfo) {
      showFailure = false;
    }
  }

  onShowFailureChanged: {
    if (showFailure) {
      showInfo = false;
    }
  }

  onCurrentTextChanged: {
    if (currentText !== "") {
      showInfo = false;
      showFailure = false;
      if (!waitingForPassword) {
        pam.abort();
      }
      if (Settings.data.general.allowPasswordWithFprintd) {
        occupyFingerprintSensorProc.running = true;
      }
    } else {
      occupyFingerprintSensorProc.running = false;
      if (pamReady && Settings.data.general.autoStartAuth) {
        pam.start();
      }
    }
  }

  function tryUnlock() {
    if (!pamReady) {
      Logger.w("LockContext", "PAM not ready yet, ignoring unlock attempt");
      return;
    }

    if (waitingForPassword) {
      pam.respond(currentText);
      unlockInProgress = true;
      waitingForPassword = false;
      showInfo = false;
      return;
    }

    Logger.i("LockContext", "Starting PAM authentication for user:", pam.user);
    pam.start();
  }

  Process {
    id: occupyFingerprintSensorProc
    command: ["fprintd-verify"]
  }

  PamContext {
    id: pam
    configDirectory: root.pamConfigDirectory
    config: root.pamConfig
    user: HostService.username

    onPamMessage: {
      Logger.i("LockContext", "PAM message:", message, "isError:", messageIsError, "responseRequired:", responseRequired);

      if (this.responseRequired) {
        Logger.i("LockContext", "Responding to PAM with password");
        if (root.currentText !== "") {
          this.respond(root.currentText);
          unlockInProgress = true;
        } else {
          root.waitingForPassword = true;
          infoMessage = I18n.tr("lock-screen.password");
          showInfo = true;
        }
      } else if (messageIsError) {
        errorMessage = message;
        showFailure = true;
      } else {
        infoMessage = message;
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
