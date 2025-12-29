import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.Commons
import qs.Services.Hardware
import qs.Services.System

Scope {
  id: root
  signal unlocked
  signal failed

  property string currentText: ""
  property bool unlockInProgress: false
  property bool showFailure: false
  property string errorMessage: ""
  property string infoMessage: ""
  property bool pamAvailable: typeof PamContext !== "undefined"

  // Fingerprint authentication properties
  readonly property bool fingerprintMode: FingerprintService.ready
  property bool waitingForPassword: false // True when PAM needs password but none entered yet
  property bool pamStarted: false // Track if PAM session started for this lock
  property bool usePasswordOnly: false // True when user typed password during fingerprint scan
  property bool abortInProgress: false // True when aborting fingerprint to switch to password

  // Computed property for fingerprint indicator visibility
  // Keep showing while typing - only hide when Enter pressed (switches to password mode)
  readonly property bool showFingerprintIndicator: fingerprintMode && unlockInProgress && !waitingForPassword && !showFailure && !usePasswordOnly

  // Determine PAM config based on OS and mode
  // Password-only mode: always use configDir (works on both NixOS and non-NixOS)
  // Normal mode on NixOS: use /etc/pam.d/login
  // Normal mode otherwise: use generated config in configDir
  readonly property string pamConfigDirectory: {
    if (usePasswordOnly) {
      return Settings.configDir + "pam";
    }
    if (HostService.isReady && HostService.isNixOS) {
      return "/etc/pam.d";
    }
    return Settings.configDir + "pam";
  }
  readonly property string pamConfig: {
    if (usePasswordOnly) {
      return "password-only.conf";
    }
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
      showFailure = false;
      errorMessage = "";
    }
  }

  // Reset state for a new lock session
  function resetForNewSession() {
    abortTimer.stop();
    pamStarted = false;
    waitingForPassword = false;
    usePasswordOnly = false;
    abortInProgress = false;
    showFailure = false;
    errorMessage = "";
    infoMessage = "";
    currentText = "";
  }

  // Timeout for PAM abort operation
  Timer {
    id: abortTimer
    interval: 500 // 500ms timeout
    repeat: false
    onTriggered: {
      if (root.abortInProgress) {
        Logger.w("LockContext", "PAM abort timeout, forcing state reset");
        root.abortInProgress = false;
        root.unlockInProgress = false;
        root.usePasswordOnly = true;
        root.pamStarted = false;
        // Retry with password-only
        root.tryUnlock();
      }
    }
  }

  // Start fingerprint authentication when lock screen becomes visible
  // Called from LockScreen.qml when surface becomes visible
  function startFingerprintAuth() {
    if (!fingerprintMode) {
      Logger.d("LockContext", "Fingerprint mode not available, skipping auto-start");
      return;
    }

    if (pamStarted || unlockInProgress) {
      Logger.d("LockContext", "PAM already started, skipping");
      return;
    }

    Logger.i("LockContext", "Starting fingerprint authentication");
    pamStarted = true;
    tryUnlock();
  }

  function tryUnlock() {
    if (!pamAvailable) {
      errorMessage = "PAM not available";
      showFailure = true;
      return;
    }

    // If we're waiting for password input and user has typed something, respond
    if (waitingForPassword && currentText !== "") {
      Logger.i("LockContext", "Responding to PAM with password");
      pam.respond(currentText);
      waitingForPassword = false;
      return;
    }

    // If fingerprint is scanning and user typed password, switch to password-only mode
    if (root.unlockInProgress && currentText !== "" && !waitingForPassword && !abortInProgress) {
      Logger.i("LockContext", "User typed password during fingerprint scan, switching to password-only mode");
      root.abortInProgress = true;
      abortTimer.start();
      pam.abort();
      // Don't continue - wait for PAM onCompleted/onError or abort timeout
      return;
    }

    if (root.unlockInProgress) {
      Logger.i("LockContext", "Unlock already in progress, ignoring duplicate attempt");
      return;
    }

    root.unlockInProgress = true;
    errorMessage = "";
    showFailure = false;

    Logger.i("LockContext", "Starting PAM authentication for user:", pam.user, "config:", pamConfig);
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
        // In fingerprint mode with auto-start, don't respond with empty password
        // Wait for user to type password instead
        if (root.currentText !== "") {
          Logger.i("LockContext", "Responding to PAM with password");
          this.respond(root.currentText);
        } else {
          // No password entered yet - set flag so user can type and submit
          Logger.i("LockContext", "Password required, waiting for user input");
          root.waitingForPassword = true;
        }
      }
    }

    onCompleted: result => {
                   Logger.i("LockContext", "PAM completed with result:", result);

                   // Handle abort completion - restart with password-only
                   if (root.abortInProgress) {
                     Logger.i("LockContext", "PAM aborted, restarting with password-only config");
                     abortTimer.stop();
                     root.abortInProgress = false;
                     root.unlockInProgress = false;
                     root.usePasswordOnly = true;
                     root.pamStarted = false;
                     root.tryUnlock();
                     return;
                   }

                   if (result === PamResult.Success) {
                     Logger.i("LockContext", "Authentication successful");
                     root.unlocked();
                   } else {
                     Logger.i("LockContext", "Authentication failed");
                     root.currentText = "";
                     errorMessage = I18n.tr("lock-screen.authentication-failed");
                     showFailure = true;
                     root.failed();
                   }
                   root.unlockInProgress = false;
                   root.waitingForPassword = false;
                   root.usePasswordOnly = false;
                   // Reset pamStarted so fingerprint can be retried on next visibility
                   root.pamStarted = false;
                 }

    onError: {
      Logger.i("LockContext", "PAM error:", error, "message:", message);

      // Handle abort completion - restart with password-only
      if (root.abortInProgress) {
        Logger.i("LockContext", "PAM abort error, restarting with password-only config");
        abortTimer.stop();
        root.abortInProgress = false;
        root.unlockInProgress = false;
        root.usePasswordOnly = true;
        root.pamStarted = false;
        root.tryUnlock();
        return;
      }

      errorMessage = message || "Authentication error";
      showFailure = true;
      root.unlockInProgress = false;
      root.waitingForPassword = false;
      root.usePasswordOnly = false;
      root.pamStarted = false;
      root.failed();
    }
  }
}
