pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services

Singleton {
  id: root

  readonly property var settings: Settings.data.screenRecorder
  property bool isRecording: false
  property string outputPath: ""

  // Start or Stop recording
  function toggleRecording() {
    isRecording ? stopRecording() : startRecording()
  }

  // Start screen recording using Quickshell.execDetached
  function startRecording() {
    if (isRecording) {
      return
    }
    isRecording = true

    var filename = Time.getFormattedTimestamp() + ".mp4"
    var videoDir = settings.directory
    if (videoDir && !videoDir.endsWith("/")) {
      videoDir += "/"
    }
    outputPath = videoDir + filename
    var flags = `-w ${settings.videoSource} -f ${settings.frameRate} -ac ${settings.audioCodec} -k ${settings.videoCodec} -a ${settings.audioSource} -q ${settings.quality} -cursor ${settings.showCursor ? "yes" : "no"} -cr ${settings.colorRange} -o ${outputPath}`
    var command = `
    _gpuscreenrecorder_flatpak_installed() {
    flatpak list --app | grep -q "com.dec05eba.gpu_screen_recorder"
    }
    if command -v gpu-screen-recorder >/dev/null 2>&1; then
    gpu-screen-recorder ${flags}
    elif command -v flatpak >/dev/null 2>&1 && _gpuscreenrecorder_flatpak_installed; then
    flatpak run --command=gpu-screen-recorder --file-forwarding com.dec05eba.gpu_screen_recorder ${flags}
    else
    notify-send "gpu-screen-recorder not installed!" -u critical
    fi`

    //Logger.log("ScreenRecorder", command)
    Quickshell.execDetached(["sh", "-c", command])
    Logger.log("ScreenRecorder", "Started recording")
  }

  // Stop recording using Quickshell.execDetached
  function stopRecording() {
    if (!isRecording) {
      return
    }

    Quickshell.execDetached(["sh", "-c", "pkill -SIGINT -f 'gpu-screen-recorder'"])
    Logger.log("ScreenRecorder", "Finished recording:", outputPath)

    // Just in case, force kill after 3 seconds
    killTimer.running = true
    isRecording = false
  }

  Timer {
    id: killTimer
    interval: 3000
    running: false
    repeat: false
    onTriggered: {
      Quickshell.execDetached(["sh", "-c", "pkill -9 -f 'gpu-screen-recorder' 2>/dev/null || true"])
    }
  }
}
