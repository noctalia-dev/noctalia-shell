import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.Commons
import qs.Services.System

Scope {
  id: root

  property string currentText: ""
  property bool waitingForPassword: false
  property bool unlockInProgress: false
  property bool showFailure: false
  property bool showInfo: false
  property string errorMessage: ""
  property string infoMessage: ""

  // PAM detection (from upstream)
  readonly property string pamConfigDirectory: "/etc/pam.d"
  property string pamConfig: Quickshell.env("NOCTALIA_PAM_SERVICE") || "login"
  property bool pamReady: false

  // Fingerprint retry logic (from your branch)
  property bool fprintdAvailable: false
  property int pamRetryCount: 0
  readonly property int pamMaxRetries: 20

  signal unlocked
  signal failed

  Component.onCompleted: {
    // Check if fprintd is available
    checkFprintdProc.running = true;

    // Detect PAM service
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
      if [ -f /etc/pam.d/noctalialock ]; then echo 'noctalialock'; exit 0; fi;
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
      infoMessage = "";
      showFailure = false;
      errorMessage = "";
      pamRetryCount = 0;
      pamRetryTimer.stop();
      if (!waitingForPassword)
        pam.abort();

      // Occupy fingerprint sensor when typing (if available and enabled)
      if (fprintdAvailable && Settings.data.general.allowPasswordWithFprintd)
        occupyFingerprintSensorProc.running = true;
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
    errorMessage = "";
    showFailure = false;
    Logger.i("LockContext", "Starting PAM authentication for user:", pam.user);
    pam.start();
  }

  Process {
    id: checkFprintdProc

    command: ["sh", "-c", "command -v fprintd-verify"]
    onExited: function (exitCode) {
      fprintdAvailable = (exitCode === 0);
      Logger.i("LockContext", "fprintd available:", fprintdAvailable);
    }
  }

  Process {
    id: occupyFingerprintSensorProc

    command: ["fprintd-verify"]
  }

  Timer {
    id: pamRetryTimer

    interval: 500
    repeat: false
    onTriggered: {
      if (root.currentText === "" && root.pamRetryCount < root.pamMaxRetries) {
        root.pamRetryCount++;
        Logger.i("LockContext", "Retrying PAM authentication, attempt", root.pamRetryCount, "of", root.pamMaxRetries);
        pam.start();
      }
    }
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
          // Retry if password prompt came before fingerprint (only if fprintd is available)
          if (root.fprintdAvailable && root.pamRetryCount < root.pamMaxRetries && !root.waitingForPassword) {
            Logger.i("LockContext", "Got password prompt early, aborting to retry fingerprint (attempt", root.pamRetryCount + 1, "of", root.pamMaxRetries + ")");
            showInfo = false;
            showFailure = false;
            pam.abort();
            pamRetryTimer.start();
          } else {
            root.waitingForPassword = true;
            showFailure = false;
            infoMessage = I18n.tr("lock-screen.password");
            showInfo = true;
          }
        }
      } else if (messageIsError) {
        errorMessage = message;
        showInfo = false;
        showFailure = true;
      } else {
        infoMessage = message;
        showFailure = false;
        showInfo = true;
      }
    }
    onCompleted: result => {
                   Logger.i("LockContext", "PAM completed with result:", result);
                   if (result === PamResult.Success) {
                     Logger.i("LockContext", "Authentication successful");
                     root.pamRetryCount = 0;
                     root.unlocked();
                   } else {
                     Logger.i("LockContext", "Authentication failed");
                     if (root.fprintdAvailable && root.currentText === "" && !root.waitingForPassword && root.pamRetryCount < root.pamMaxRetries) {
                       Logger.i("LockContext", "Will retry PAM (attempt", root.pamRetryCount + 1, "of", root.pamMaxRetries + ")");
                       pamRetryTimer.start();
                     } else {
                       root.currentText = "";
                       errorMessage = I18n.tr("authentication.failed");
                       showFailure = true;
                       root.failed();
                     }
                   }
                   root.unlockInProgress = false;
                 }
    onError: {
      Logger.i("LockContext", "PAM error:", error, "message:", message);
      if (root.fprintdAvailable && root.currentText === "" && !root.waitingForPassword && root.pamRetryCount < root.pamMaxRetries) {
        Logger.i("LockContext", "PAM error, will retry (attempt", root.pamRetryCount + 1, "of", root.pamMaxRetries + ")");
        pamRetryTimer.start();
      } else {
        errorMessage = message || "Authentication error";
        showFailure = true;
        root.failed();
      }
      root.unlockInProgress = false;
    }
  }
}
