pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Cache for current scales - updated via signals
  property var currentScales: ({})

  // Compositor-reported scales (base scales)
  property var compositorScales: ({})

  // User scale adjustments (multipliers on top of compositor scales)
  property var userScaleAdjustments: ({})

  // Whether to auto-detect scales from compositor
  property bool autoDetectScale: true

  // Signal emitted when scale changes
  signal scaleChanged(string screenName, real scale)

  Component.onCompleted: {
    Logger.log("Scaling", "Service started")

    // Initialize auto-detection
    if (autoDetectScale) {
      updateCompositorScales()
    }

    // Load user adjustments from settings
    var monitors = Settings.data.ui.monitorsScaling || []
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].name) {
        // Store as user adjustment factor (1.0 = no adjustment)
        userScaleAdjustments[monitors[i].name] = monitors[i].scale || 1.0
      }
    }

    // Update final scales
    updateAllScales()

    // Re-detect scales periodically (monitors can be plugged/unplugged)
    scaleUpdateTimer.start()
  }

  Timer {
    id: scaleUpdateTimer
    interval: 5000 // Check every 5 seconds
    repeat: true
    onTriggered: {
      if (autoDetectScale) {
        updateCompositorScales()
      }
    }
  }

  // -------------------------------------------
  // Detect compositor and update scales accordingly
  function updateCompositorScales() {
    if (CompositorService.isNiri) {
      niriOutputsProcess.running = true
    } else if (CompositorService.isHyprland) {
      hyprlandMonitorsProcess.running = true
    }
  }

  // Process for reading Niri outputs
  Process {
    id: niriOutputsProcess
    running: false
    command: ["niri", "msg", "outputs"]

    onExited: function () {
      updateAllScales()
    }

    stdout: SplitParser {
      property string currentOutput: ""
      property real currentScale: 1.0

      onRead: function (line) {
        try {
          // Parse Niri output format
          if (line.includes("Output \"")) {
            // Extract output name from parentheses at the end
            var match = line.match(/\(([^)]+)\)$/)
            if (match) {
              currentOutput = match[1]
            }
          } else if (line.includes("Scale:")) {
            // Extract scale value
            var scaleMatch = line.match(/Scale:\s*([0-9.]+)/)
            if (scaleMatch) {
              currentScale = parseFloat(scaleMatch[1])
              if (currentOutput && !isNaN(currentScale)) {
                compositorScales[currentOutput] = currentScale
                // Logger.log("Scaling", "Niri output", currentOutput, "has scale", currentScale)
              }
            }
          }
        } catch (e) {
          Logger.error("Scaling", "Failed to parse Niri outputs:", e)
        }
      }
    }
  }

  // Process for reading Hyprland monitors
  Process {
    id: hyprlandMonitorsProcess
    running: false
    command: ["hyprctl", "monitors", "-j"]

    onExited: function () {
      try {
        var monitors = JSON.parse(hyprlandMonitorsProcess.stdout.accumulated)
        for (var i = 0; i < monitors.length; i++) {
          var monitor = monitors[i]
          if (monitor.name && monitor.scale !== undefined) {
            compositorScales[monitor.name] = monitor.scale
            // Logger.log("Scaling", "Hyprland monitor", monitor.name, "has scale", monitor.scale)
          }
        }
        updateAllScales()
      } catch (e) {
        Logger.error("Scaling", "Failed to parse Hyprland monitors:", e)
      }
    }

    stdout: SplitParser {
      property string accumulated: ""

      onRead: function (line) {
        accumulated += line
      }
    }
  }

  // -------------------------------------------
  // Update all scales based on compositor scales and user adjustments
  function updateAllScales() {
    var updatedScreens = []

    // For each compositor-reported monitor
    for (var screenName in compositorScales) {
      var compositorScale = compositorScales[screenName] || 1.0
      var userAdjustment = userScaleAdjustments[screenName] || 1.0

      // Final scale is compositor scale * user adjustment
      var finalScale = compositorScale * userAdjustment

      // Only update if changed
      if (currentScales[screenName] !== finalScale) {
        currentScales[screenName] = finalScale
        root.scaleChanged(screenName, finalScale)
        updatedScreens.push(screenName)
        Logger.log("Scaling", "Updated scale for", screenName, "to", finalScale,
                   "(compositor:", compositorScale, "× adjustment:", userAdjustment, ")")
      }
    }

    // Also check for monitors in user adjustments that aren't in compositor scales
    // (for manual overrides or fallback)
    for (var screenName in userScaleAdjustments) {
      if (!(screenName in compositorScales)) {
        var manualScale = userScaleAdjustments[screenName]
        if (currentScales[screenName] !== manualScale) {
          currentScales[screenName] = manualScale
          root.scaleChanged(screenName, manualScale)
          Logger.log("Scaling", "Using manual scale for", screenName, ":", manualScale)
        }
      }
    }
  }

  // -------------------------------------------
  // Get effective scale for a screen
  function getScreenScale(aScreen) {
    try {
      if (aScreen !== undefined && aScreen.name !== undefined) {
        return getScreenScaleByName(aScreen.name)
      }
    } catch (e) {

      //Logger.warn(e)
    }
    return 1.0
  }

  // -------------------------------------------
  // Get scale from cache for better performance
  function getScreenScaleByName(aScreenName) {
    try {
      var scale = currentScales[aScreenName]
      if ((scale !== undefined) && (scale != null)) {
        return scale
      }
    } catch (e) {

      //Logger.warn(e)
    }
    return 1.0
  }

  // -------------------------------------------
  // Set user adjustment for a screen
  function setScreenScale(aScreen, scale) {
    try {
      if (aScreen !== undefined && aScreen.name !== undefined) {
        return setScreenScaleByName(aScreen.name, scale)
      }
    } catch (e) {
      Logger.warn("Scaling", "Error in setScreenScale:", e)
    }
  }

  // -------------------------------------------
  // Set user adjustment factor for a screen
  function setScreenScaleByName(aScreenName, scale) {
    try {
      // If auto-detection is enabled, this becomes an adjustment factor
      var adjustment = scale
      if (autoDetectScale && compositorScales[aScreenName]) {
        adjustment = scale / compositorScales[aScreenName]
      }

      // Update user adjustment
      userScaleAdjustments[aScreenName] = adjustment

      // Update Settings with the adjustment
      var monitors = Settings.data.ui.monitorsScaling || []
      var found = false

      var newMonitors = monitors.map(function (monitor) {
        if (monitor.name === aScreenName) {
          found = true
          return {
            "name": aScreenName,
            "scale": adjustment
          }
        }
        return monitor
      })

      if (!found) {
        newMonitors.push({
                           "name": aScreenName,
                           "scale": adjustment
                         })
      }

      // Use slice() to ensure Settings detects the change
      Settings.data.ui.monitorsScaling = newMonitors.slice()

      // Update all scales to apply the new adjustment
      updateAllScales()

      Logger.log("Scaling", "User adjustment set for", aScreenName, "to", adjustment)
    } catch (e) {
      Logger.warn("Scaling", "Error setting scale:", e)
    }
  }

  // -------------------------------------------
  // Get compositor-reported scale for a screen
  function getCompositorScale(aScreenName) {
    return compositorScales[aScreenName] || 1.0
  }

  // -------------------------------------------
  // Get user adjustment factor for a screen
  function getUserAdjustment(aScreenName) {
    return userScaleAdjustments[aScreenName] || 1.0
  }

  // -------------------------------------------
  // Dynamic scaling based on resolution
  // Design reference resolution (for scale = 1.0)
  readonly property int designScreenWidth: 2560
  readonly property int designScreenHeight: 1440
  function dynamicScale(aScreen) {
    if (aScreen != null) {
      var ratioW = aScreen.width / designScreenWidth
      var ratioH = aScreen.height / designScreenHeight
      return Math.min(ratioW, ratioH)
    }
    return 1.0
  }
}
