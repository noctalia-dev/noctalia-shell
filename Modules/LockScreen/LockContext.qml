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
  signal fingerprintFailed  // Emitted on each fingerprint match failure

  property string currentText: ""
  property bool waitingForPassword: false
  property bool unlockInProgress: false
  property bool showFailure: false
  property bool showInfo: false
  property string errorMessage: ""
  property string infoMessage: ""
  property bool pamAvailable: typeof PamContext !== "undefined"

  // Fingerprint authentication properties
  readonly property bool fingerprintMode: FingerprintService.ready
  property bool pamStarted: false // Track if PAM session started for this lock
  property bool usePasswordOnly: false // True when user typed password during fingerprint scan
  property bool abortInProgress: false // True when aborting fingerprint to switch to password

  // Computed property for fingerprint indicator visibility
  // Keep showing while typing - only hide when Enter pressed (switches to password mode)
  readonly property bool showFingerprintIndicator: fingerprintMode && unlockInProgress && !waitingForPassword && !showFailure && !usePasswordOnly

  // PAM config:
  // NixOS: system config for fingerprint, custom config for password-only
  // Non-NixOS: custom configs for both
  readonly property bool isNixOS: HostService.isReady && HostService.isNixOS
  readonly property string pamConfigDirectory: {
    // Password-only always uses custom config (works on NixOS, pam_unix.so is in standard path)
    if (usePasswordOnly || !fingerprintMode) {
      return Settings.configDir + "pam";
    }
    // Fingerprint mode: NixOS uses system config, others use custom
    return isNixOS ? "/etc/pam.d" : Settings.configDir + "pam";
  }
  readonly property string pamConfig: {
    if (usePasswordOnly || !fingerprintMode) {
      return "password-only.conf";
    }
    return isNixOS ? "login" : "fingerprint-only.conf";
  }

  onCurrentTextChanged: {
    if (currentText !== "") {
      showInfo = false;
      infoMessage = "";
      showFailure = false;
      errorMessage = "";
    }
  }

  // Reset state for a new lock session
  function resetForNewSession() {
    Logger.i("LockContext", "Resetting state for new lock session");
    abortTimer.stop();
    fingerprintRestartTimer.stop();
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
    interval: 150 // 150ms timeout (reduced from 500ms for better UX)
    repeat: false
    onTriggered: {
      if (root.abortInProgress) {
        Logger.i("LockContext", "PAM abort timeout, forcing state reset");
        root.abortInProgress = false;
        root.unlockInProgress = false;
        root.usePasswordOnly = true;
        root.pamStarted = false;
        // Retry with password-only
        root.tryUnlock();
      }
    }
  }

  // Delay before restarting fingerprint auth (prevents tight loops on errors)
  Timer {
    id: fingerprintRestartTimer
    interval: 500
    repeat: false
    onTriggered: root.startFingerprintAuth()
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
    Logger.i("LockContext", "tryUnlock called - pamAvailable:", pamAvailable, "waitingForPassword:", waitingForPassword, "currentText:", currentText !== "" ? "[has text]" : "[empty]", "unlockInProgress:", unlockInProgress, "abortInProgress:", abortInProgress);

    if (!pamAvailable) {
      Logger.i("LockContext", "PAM not available, showing error");
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
    Logger.i("LockContext", "PAM started, unlockInProgress:", root.unlockInProgress);
  }

  PamContext {
    id: pam
    // Use custom PAM configs for separate fingerprint/password flows
    // fingerprint-only.conf: only pam_fprintd.so (no password fallback)
    // password-only.conf: only pam_unix.so (no fingerprint)
    configDirectory: root.pamConfigDirectory
    config: root.pamConfig
    user: HostService.username

    onPamMessage: {
      Logger.i("LockContext", "PAM message:", message, "isError:", messageIsError, "responseRequired:", responseRequired);

      if (messageIsError) {
        errorMessage = message;
        // Detect fingerprint failure and emit signal
        var msgLower = message.toLowerCase();
        if (msgLower.includes("failed") && msgLower.includes("fingerprint")) {
          Logger.i("LockContext", "Fingerprint failure detected, emitting signal");
          root.fingerprintFailed();
        }
      } else {
        infoMessage = message;
      }

      if (this.responseRequired) {
        var msgLower = message.toLowerCase();
        var isFingerprintPrompt = msgLower.includes("finger") || msgLower.includes("swipe") || msgLower.includes("touch") || msgLower.includes("scan");
        Logger.i("LockContext", "Response required, isFingerprintPrompt:", isFingerprintPrompt, "usePasswordOnly:", root.usePasswordOnly, "currentText:", root.currentText !== "" ? "[has text]" : "[empty]");

        if (root.currentText !== "") {
          // User has typed something - respond with it
          Logger.i("LockContext", "Responding to PAM with password");
          this.respond(root.currentText);
        } else if (isFingerprintPrompt) {
          // Fingerprint prompt with no password typed - don't respond, let fprintd wait for sensor
          Logger.i("LockContext", "Fingerprint prompt, waiting for finger via sensor");
        } else {
          // Password prompt with no text - wait for user input
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
                     errorMessage = I18n.tr("authentication.failed");
                     showFailure = true;
                     root.failed();
                   }
                   root.unlockInProgress = false;
                   root.waitingForPassword = false;
                   root.usePasswordOnly = false;
                   root.pamStarted = false;

                   // Auto-restart fingerprint auth after failure (with delay to prevent tight loops)
                   if (result !== PamResult.Success && root.fingerprintMode) {
                     fingerprintRestartTimer.start();
                   }
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

      // Auto-restart fingerprint auth after error (with delay to prevent tight loops)
      if (root.fingerprintMode) {
        fingerprintRestartTimer.start();
      }
    }
  }
}
