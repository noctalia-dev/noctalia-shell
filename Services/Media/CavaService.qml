pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  // Register a component that needs audio data, call this when a visualizer becomes active.
  // Pass a unique identifier (e.g., "lockscreen", "controlcenter:screen1", "plugin:fancy-audiovisualizer")
  function registerComponent(componentId) {
    root.registeredComponents[componentId] = true;
    root.registeredComponents = Object.assign({}, root.registeredComponents);
    Logger.d("Cava", "Component registered:", componentId, "- total:", root.registeredCount);
  }

  // Unregister a component when it no longer needs audio data.
  function unregisterComponent(componentId) {
    delete root.registeredComponents[componentId];
    root.registeredComponents = Object.assign({}, root.registeredComponents);
    Logger.d("Cava", "Component unregistered:", componentId, "- total:", root.registeredCount);
  }

  // Check if a component is registered
  function isRegistered(componentId) {
    return root.registeredComponents[componentId] === true;
  }

  // Component registration - any component needing audio data registers here
  property var registeredComponents: ({})
  readonly property int registeredCount: Object.keys(registeredComponents).length
  property bool shouldRun: registeredCount > 0

  property var values: []
  property int barsCount: 32

  // Idle detection to reduce GPU usage when there's no audio
  property bool isIdle: true
  property int idleFrameCount: 0
  readonly property int idleThreshold: 30 // Frames of silence before considered idle (0.5s at 60fps)

  // Crash tracking for auto-restart
  property int _crashCount: 0
  property int _maxCrashes: 5

  // Pre-allocated array for quick parsing
  property var _parseBuffer: new Array(barsCount)

  // Simple config
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

  // Manage process lifecycle imperatively to avoid broken bindings.
  // A declarative `running: shouldRun` binding would be destroyed when
  // the restart timer or the Process itself sets `running` imperatively,
  // causing cava to keep running after all components unregister.
  onShouldRunChanged: {
    if (shouldRun && !process.running) {
      process.running = true;
    } else if (!shouldRun && process.running) {
      process.running = false;
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    repeat: false
    onTriggered: {
      if (root.shouldRun && !process.running) {
        Logger.w("Cava", "Restarting after crash...");
        process.running = true;
      }
    }
  }

  Process {
    id: process
    stdinEnabled: true
    command: ["cava", "-p", "/dev/stdin"]
    onRunningChanged: {
      Logger.d("Cava", "Process running:", running);
    }
    onExited: {
      stdinEnabled = true;
      values = Array(barsCount).fill(0);
      if (root.shouldRun) {
        root._crashCount++;
        if (root._crashCount <= root._maxCrashes) {
          Logger.w("Cava", "Process exited unexpectedly, restarting in 2s... (attempt " + root._crashCount + "/" + root._maxCrashes + ")");
          restartTimer.start();
        } else {
          Logger.e("Cava", "Process crashed too many times (" + root._maxCrashes + "), giving up");
        }
      } else {
        Logger.d("Cava", "Process exited (no longer needed)");
        root._crashCount = 0;
      }
    }
    onStarted: {
      Logger.d("Cava", "Process started");
      for (const k in config) {
        if (typeof config[k] !== "object") {
          write(k + "=" + config[k] + "\n");
          continue;
        }
        write("[" + k + "]\n");
        const obj = config[k];
        for (const k2 in obj) {
          write(k2 + "=" + obj[k2] + "\n");
        }
      }
      stdinEnabled = false;
      values = Array(barsCount).fill(0);
    }
    stdout: SplitParser {
      onRead: data => {
        if (root._crashCount > 0)
        root._crashCount = 0;

        // Optimized parsing directly into pre-allocated buffer
        const buffer = root._parseBuffer;
        let idx = 0;
        let num = 0;
        let allZero = true;

        for (let i = 0, len = data.length - 1; i < len; i++) {
          const c = data.charCodeAt(i);
          if (c === 59) {
            // semicolon
            const val = num * 0.01;
            buffer[idx++] = val;
            if (val >= 0.01) {
              allZero = false;
            }
            num = 0;
          } else if (c >= 48 && c <= 57) {
            // digit 0-9
            num = num * 10 + (c - 48);
          }
        }
        // Handle last value if no trailing semicolon
        if (num > 0 || idx < root.barsCount) {
          const val = num * 0.01;
          buffer[idx++] = val;
          if (val >= 0.01) {
            allZero = false;
          }
        }

        if (allZero) {
          root.idleFrameCount++;
          if (root.idleFrameCount >= root.idleThreshold) {
            // We're idle - stop updating values to save GPU
            if (!root.isIdle) {
              root.isIdle = true;
              // Set all values to 0 one final time
              root.values = Array(root.barsCount).fill(0);
              Logger.d("Cava", "Idle detected - stopped rendering");
            }
            // Don't update values while idle
            return;
          }
        } else {
          // Audio detected - resume updates
          root.idleFrameCount = 0;
          if (root.isIdle) {
            root.isIdle = false;
            Logger.d("Cava", "Audio detected - resumed rendering");
          }
        }

        // Update values only if not idle - copy buffer to trigger binding updates
        if (!root.isIdle) {
          root.values = buffer.slice(0, idx);
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.w("Cava", "Error", text);
        }
      }
    }
  }
}
