pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

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
  property int barsCount: 48
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
                            "monstercat": 0,
                            "noise_reduction": 77
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
        root.values = data.slice(0, -1).split(";").map(v => parseInt(v, 10) / 100)
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
