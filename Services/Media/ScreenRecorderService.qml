pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.System
import qs.Services.UI

Singleton {
  id: root

  readonly property var settings: Settings.data.screenRecorder
  property bool isRecording: false
  property bool isPending: false
  // True only if the recorder actually started capturing at least once
  property bool hasActiveRecording: false
  property string outputPath: ""
  property bool isAvailable: ProgramCheckerService.gpuScreenRecorderAvailable

  // Update availability when ProgramCheckerService completes its checks
  Connections {
    target: ProgramCheckerService
    function onChecksCompleted() {// Availability is now automatically updated via property binding
    }
  }

  // Start or Stop recording
  function toggleRecording() {
    (isRecording || isPending) ? stopRecording() : startRecording();
  }

  // Start screen recording using Quickshell.execDetached
  function startRecording() {
    if (!isAvailable) {
      return;
    }
    if (isRecording || isPending) {
      return;
    }
    isPending = true;
    hasActiveRecording = false;

    // Close any opened panel
    if ((PanelService.openedPanel !== null) && !PanelService.openedPanel.isClosing) {
      PanelService.openedPanel.close();
    }

    // First, ensure xdg-desktop-portal and a compositor portal are running
    portalCheckProcess.exec({
                              "command": ["sh", "-c" // require core portal AND one of the backends
                                , "pidof xdg-desktop-portal >/dev/null 2>&1 && (pidof xdg-desktop-portal-wlr >/dev/null 2>&1 || pidof xdg-desktop-portal-hyprland >/dev/null 2>&1 || pidof xdg-desktop-portal-gnome >/dev/null 2>&1 || pidof xdg-desktop-portal-kde >/dev/null 2>&1)"]
                            });
  }

  function launchRecorder() {
    var filename = Time.getFormattedTimestamp() + ".mp4";
    var videoDir = Settings.preprocessPath(settings.directory);
    if (videoDir && !videoDir.endsWith("/")) {
      videoDir += "/";
    }
    outputPath = videoDir + filename;

    var audioArg = (settings.audioSource === "both") ? `-a "default_output|default_input"` : `-a ${settings.audioSource}`;

    var flags = `-w ${settings.videoSource} -f ${settings.frameRate} -ac ${settings.audioCodec} -k ${settings.videoCodec} ${audioArg} -q ${settings.quality} -cursor ${settings.showCursor ? "yes" : "no"} -cr ${settings.colorRange} -o "${outputPath}"`;
    var command = `
    _gpuscreenrecorder_flatpak_installed() {
    flatpak list --app | grep -q "com.dec05eba.gpu_screen_recorder"
    }
    if command -v gpu-screen-recorder >/dev/null 2>&1; then
    gpu-screen-recorder ${flags}
    elif command -v flatpak >/dev/null 2>&1 && _gpuscreenrecorder_flatpak_installed; then
    flatpak run --command=gpu-screen-recorder --file-forwarding com.dec05eba.gpu_screen_recorder ${flags}
    else
    echo "GPU_SCREEN_RECORDER_NOT_INSTALLED"
    fi`;

    // Use Process instead of execDetached so we can monitor it and read stderr
    recorderProcess.exec({
                           "command": ["sh", "-c", command]
                         });

    // Start monitoring - if process ends quickly, it was likely cancelled
    pendingTimer.running = true;
  }

  // Stop recording using Quickshell.execDetached
  function stopRecording() {
    if (!isRecording && !isPending) {
      return;
    }

    ToastService.showNotice(I18n.tr("toast.recording.stopping"), outputPath, "settings-screen-recorder");

    Quickshell.execDetached(["sh", "-c", "pkill -SIGINT -f 'gpu-screen-recorder' || pkill -SIGINT -f 'com.dec05eba.gpu_screen_recorder'"]);

    isRecording = false;
    isPending = false;
    pendingTimer.running = false;
    monitorTimer.running = false;
    hasActiveRecording = false;

    // Just in case, force kill after 3 seconds
    killTimer.running = true;
  }

  // Helper function to check if output indicates user cancellation
  function isCancelledByUser(stdoutText, stderrText) {
    const stdout = String(stdoutText || "").toLowerCase();
    const stderr = String(stderrText || "").toLowerCase();
    const combined = stdout + " " + stderr;
    // Check for various forms of cancellation messages (case-insensitive)
    return combined.includes("canceled by") || combined.includes("cancelled by") || combined.includes("canceled by user") || combined.includes("cancelled by user") || combined.includes("canceled by the user") || combined.includes("cancelled by the user");
  }

  // Process to run and monitor gpu-screen-recorder
  Process {
    id: recorderProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function (exitCode, exitStatus) {
      const stdout = String(recorderProcess.stdout.text || "").trim();
      const stderr = String(recorderProcess.stderr.text || "").trim();
      const wasCancelled = isCancelledByUser(stdout, stderr);

      if (isPending) {
        // Process ended while we were pending - likely cancelled or error
        isPending = false;
        pendingTimer.running = false;

        // Check if gpu-screen-recorder is not installed
        if (stdout === "GPU_SCREEN_RECORDER_NOT_INSTALLED") {
          ToastService.showError(I18n.tr("toast.recording.not-installed"), I18n.tr("toast.recording.not-installed-desc"));
          return;
        }

        // If it failed to start, show a clear error toast with stderr
        // But don't show error if user intentionally cancelled via portal
        if (exitCode !== 0) {
          if (stderr.length > 0 && !wasCancelled) {
            ToastService.showError(I18n.tr("toast.recording.failed-start"), stderr);
            Logger.e(stderr);
          }
          // If user cancelled, silently return without error toast
        }
      } else if (isRecording) {
        // Process ended normally while recording
        isRecording = false;
        monitorTimer.running = false;
        // Consider successful save if exitCode == 0
        if (exitCode === 0) {
          ToastService.showNotice(I18n.tr("toast.recording.saved"), outputPath, "settings-screen-recorder");
        } else {
          // Don't show error if user intentionally cancelled
          if (!wasCancelled) {
            if (stderr.length > 0) {
              ToastService.showError(I18n.tr("toast.recording.failed-start"), stderr);
              Logger.e(stderr);
            } else {
              ToastService.showError(I18n.tr("toast.recording.failed-start"), I18n.tr("toast.recording.failed-general"));
            }
          }
        }
      }
    }
  }

  // Pre-flight check for xdg-desktop-portal
  Process {
    id: portalCheckProcess
    onExited: function (exitCode, exitStatus) {
      if (exitCode === 0) {
        // Portals available, proceed to launch
        launchRecorder();
      } else {
        isPending = false;
        hasActiveRecording = false;
        ToastService.showError(I18n.tr("toast.recording.no-portals"), I18n.tr("toast.recording.no-portals-desc"));
      }
    }
  }

  Timer {
    id: pendingTimer
    interval: 2000 // Wait 2 seconds to see if process stays alive
    running: false
    repeat: false
    onTriggered: {
      if (isPending && recorderProcess.running) {
        // Process is still running after 2 seconds - assume recording started successfully
        isPending = false;
        isRecording = true;
        hasActiveRecording = true;
        monitorTimer.running = true;
        // Don't show a toast when recording starts to avoid having the toast in every video.
      } else if (isPending) {
        // Process not running anymore - was cancelled or failed
        isPending = false;
      }
    }
  }

  // Monitor timer to periodically check if we're still recording
  Timer {
    id: monitorTimer
    interval: 2000
    running: false
    repeat: true
    onTriggered: {
      if (!recorderProcess.running && isRecording) {
        isRecording = false;
        running = false;
      }
    }
  }

  Timer {
    id: killTimer
    interval: 3000
    running: false
    repeat: false
    onTriggered: {
      Quickshell.execDetached(["sh", "-c", "pkill -9 -f 'gpu-screen-recorder' 2>/dev/null || pkill -9 -f 'com.dec05eba.gpu_screen_recorder' 2>/dev/null || true"]);
    }
  }
}
