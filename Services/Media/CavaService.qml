pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root


  /**
   * Cava runs if:
   *   - Bar has an audio visualizer
   *   - LockScreen is opened
   *   - A control center is open
   */
  property bool shouldRun: BarService.hasAudioVisualizer || PanelService.lockScreen?.active || (PanelService.openedPanel && PanelService.openedPanel.objectName.startsWith("controlCenterPanel"))

  property var values: Array(barsCount).fill(0)
  property int barsCount: 32

  // Idle detection to reduce GPU usage when there's no audio
  property bool isIdle: true
  property int idleFrameCount: 0
  readonly property int idleThreshold: 30 // Frames of silence before considered idle (0.5s at 60fps)

  // Frame skipping for GPU optimization - skip every Nth frame when playing
  property int frameCounter: 0
  readonly property int frameSkip: 1 // Update every N frames (1 = no skip, 2 = every other frame, etc)

  // Change detection - only update if values changed significantly
  property var lastValues: Array(barsCount).fill(0)
  readonly property real changeThreshold: 0.005 // Minimum change (1%) to trigger update
  property var config: ({
                          "general": {
                            "bars": barsCount,
                            "framerate": Settings.data.audio.cavaFrameRate,
                            "autosens": 1,
                            "sensitivity": 100,
                            "lower_cutoff_freq": 50,
                            "higher_cutoff_freq": 12000
                          },
                          "smoothing": {
                            "monstercat": 1,
                            "noise_reduction"// Enable monstercat smoothing for less jittery animation
                            : 77
                          },
                          "output": {
                            "method": "raw",
                            "data_format": "ascii",
                            "ascii_max_range": 100,
                            "bit_format": "8bit",
                            "channels": "mono",
                            "mono_option": "average"
                          }
                        })

  Process {
    id: process
    stdinEnabled: true
    running: root.shouldRun
    command: ["cava", "-p", "/dev/stdin"]
    onRunningChanged: {
      Logger.d("Cava", "Process running:", running)
    }
    onExited: {
      Logger.i("Cava", "Process exited")
      stdinEnabled = true
      values = Array(barsCount).fill(0)
    }
    onStarted: {
      Logger.i("Cava", "Process started")
      for (const k in config) {
        if (typeof config[k] !== "object") {
          write(k + "=" + config[k] + "\n")
          continue
        }
        write("[" + k + "]\n")
        const obj = config[k]
        for (const k2 in obj) {
          write(k2 + "=" + obj[k2] + "\n")
        }
      }
      stdinEnabled = false
      values = Array(barsCount).fill(0)
    }
    stdout: SplitParser {
      onRead: data => {
        const newValues = data.slice(0, -1).split(";").map(v => parseInt(v, 10) / 100)

        // Check if all values are effectively zero (< 0.01)
        const allZero = newValues.every(v => v < 0.01)

        if (allZero) {
          root.idleFrameCount++
          if (root.idleFrameCount >= root.idleThreshold) {
            // We're idle - stop updating values to save GPU
            if (!root.isIdle) {
              root.isIdle = true
              // Set all values to 0 one final time
              root.values = Array(root.barsCount).fill(0)
              root.lastValues = Array(root.barsCount).fill(0)
              Logger.d("Cava", "Idle detected - stopped rendering")
            }
            // Don't update values while idle
            return
          }
        } else {
          // Audio detected - resume updates
          root.idleFrameCount = 0
          if (root.isIdle) {
            root.isIdle = false
            Logger.d("Cava", "Audio detected - resumed rendering")
          }
        }

        // Frame skipping optimization - skip frames to reduce GPU load
        root.frameCounter++
        if (root.frameSkip > 1 && root.frameCounter % root.frameSkip !== 0) {
          // Skip this frame
          return
        }

        // Change detection - only update if values changed significantly
        let hasSignificantChange = false
        for (var i = 0; i < newValues.length; i++) {
          const delta = Math.abs(newValues[i] - root.lastValues[i])
          if (delta > root.changeThreshold) {
            hasSignificantChange = true
            break
          }
        }

        // Update values only if there's a significant change
        if (hasSignificantChange) {
          root.lastValues = newValues.slice() // Copy array
          root.values = newValues
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.w("Cava", "Error", text)
        }
      }
    }
  }
}
