pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons

/**
 * ProjectMService — manages preset selection and rotation for all ProjectMItem
 * instances (desktop backgrounds + lock screen).
 *
 * Instead of each ProjectMItem running its own preset timer and MPRIS handler,
 * this singleton broadcasts the current preset path via `currentPreset`.
 * Instances set `autoPresets: false` and call `requestPreset()` on changes.
 */
Singleton {
  id: root

  // Presets dir is symlinked by the home-module into XDG_DATA_HOME.
  readonly property string presetsDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/waylivepaper/presets"

  // Currently active preset path — bind ProjectMItem.requestPreset() to this.
  property string currentPreset: ""

  // Preset rotation interval in seconds.
  readonly property int presetInterval: 120

  // -------------------------------------------------------
  function init() {
    Logger.i("ProjectMService", "Service started");
    if (Settings.data.wallpaper.livePaperEnabled) {
      _scanPresets();
    }
  }

  // -------------------------------------------------------
  function _scanPresets() {
    _presets = [];
    presetScanner.running = true;
  }

  function _advancePreset() {
    if (_presets.length === 0) return;
    var idx = Math.floor(Math.random() * _presets.length);
    currentPreset = _presets[idx];
    Logger.d("ProjectMService", "Preset:", currentPreset);
  }

  property var _presets: []

  // -------------------------------------------------------
  Connections {
    target: Settings.data.wallpaper
    function onLivePaperEnabledChanged() {
      if (Settings.data.wallpaper.livePaperEnabled) {
        if (root._presets.length === 0) {
          root._scanPresets();
        } else {
          root._advancePreset();
          presetTimer.start();
        }
      } else {
        presetTimer.stop();
      }
    }
  }

  // -------------------------------------------------------
  // MPRIS: advance preset on track change.
  property var mprisPlayer: (Mpris.players && Mpris.players.values && Mpris.players.values.length > 0)
    ? Mpris.players.values[0] : null

  property string currentMprisTrack: mprisPlayer ? (mprisPlayer.trackTitle ?? "") : ""
  property string _lastMprisTrack: ""

  onCurrentMprisTrackChanged: {
    if (currentMprisTrack !== "" && currentMprisTrack !== _lastMprisTrack) {
      _lastMprisTrack = currentMprisTrack
      Logger.d("ProjectMService", "MPRIS track changed → advancing preset")
      _advancePreset()
      presetTimer.restart()
    }
  }

  // -------------------------------------------------------
  // Scan presets directory via `find`.
  Process {
    id: presetScanner
    running: false
    command: ["find", "-L", root.presetsDir, "-type", "f",
              "(", "-name", "*.milk", "-o", "-name", "*.prjm", ")"]

    stdout: SplitParser {
      onRead: (line) => {
        var trimmed = line.trim()
        if (trimmed !== "")
          root._presets.push(trimmed)
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {}
    }

    onExited: (code, status) => {
      if (root._presets.length === 0) {
        Logger.w("ProjectMService", "No presets found in", root.presetsDir);
        return;
      }
      // Fisher-Yates shuffle for random rotation
      var arr = root._presets
      for (var i = arr.length - 1; i > 0; i--) {
        var j = Math.floor(Math.random() * (i + 1))
        var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp
      }
      root._presets = arr
      Logger.i("ProjectMService", "Scanned", root._presets.length, "presets");
      root._advancePreset()
      if (Settings.data.wallpaper.livePaperEnabled) {
        presetTimer.start()
      }
    }
  }

  // -------------------------------------------------------
  Timer {
    id: presetTimer
    interval: root.presetInterval * 1000
    repeat: true
    running: false
    onTriggered: root._advancePreset()
  }
}
