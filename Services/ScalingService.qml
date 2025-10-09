pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  // Cache for current scales - updated via signals
  property var currentScales: ({})

  // Signal emitted when scale changes
  signal scaleChanged(string screenName, real scale)

  Component.onCompleted: {
    Logger.log("Scaling", "Service started")
    // Initialize cache from Settings once they are loaded on startup
    var monitors = Settings.data.ui.monitorsScaling || []
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].name && monitors[i].scale !== undefined) {
        currentScales[monitors[i].name] = monitors[i].scale
        root.scaleChanged(monitors[i].name, monitors[i].scale)
        Logger.log("Scaling", "Caching scaling for", monitors[i].name, ":", monitors[i].scale)
      }
    }
  }

  // -------------------------------------------
  // Manual scaling via Settings
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
  function setScreenScale(aScreen, scale) {
    try {
      if (aScreen !== undefined && aScreen.name !== undefined) {
        return setScreenScaleByName(aScreen.name, scale)
      }
    } catch (e) {

      //Logger.warn(e)
    }
  }

  // -------------------------------------------
  function setScreenScaleByName(aScreenName, scale) {
    try {
      // Check if scale actually changed
      var oldScale = currentScales[aScreenName] || 1.0
      if (oldScale === scale) {
        return
        // No change needed
      }

      // Update cache directly
      currentScales[aScreenName] = scale

      // Update Settings with immutable update for proper persistence
      var monitors = Settings.data.ui.monitorsScaling || []
      var found = false

      var newMonitors = monitors.map(function (monitor) {
        if (monitor.name === aScreenName) {
          found = true
          return {
            "name": aScreenName,
            "scale": scale
          }
        }
        return monitor
      })

      if (!found) {
        newMonitors.push({
                           "name": aScreenName,
                           "scale": scale
                         })
      }

      // Use slice() to ensure Settings detects the change
      Settings.data.ui.monitorsScaling = newMonitors.slice()

      // Emit signal for components to react
      root.scaleChanged(aScreenName, scale)

      Logger.log("Scaling", "Scale changed for", aScreenName, "to", scale)
    } catch (e) {
      Logger.warn("Scaling", "Error setting scale:", e)
    }
  }

  // -------------------------------------------
  // Dynamic scaling based on resolution
  // Design reference resolution (for scale = 1.0)
  readonly property int designScreenWidth: 2560
  readonly property int designScreenHeight: 1440
  function dynamicScale(aScreen) {
    return 1.0
    // if (aScreen != null) {
    //   var ratioW = aScreen.width / designScreenWidth
    //   var ratioH = aScreen.height / designScreenHeight
    //   return Math.min(ratioW, ratioH)
    // }
    // return 1.0
  }
}
