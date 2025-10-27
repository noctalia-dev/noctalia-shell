pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Minimal settings singleton for noctalia-greet
Singleton {
  id: root

  // App dirs
  property string appName: "noctalia-greet"
  property string cacheDir: Quickshell.env("NOCTALIA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/" + appName + "/"
  property string settingsFile: cacheDir + "cache.json"

  // Noctalia main config path
  property string noctaliaConfigDir: Quickshell.env("NOCTALIA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/noctalia/"
  property string noctaliaSettingsFile: noctaliaConfigDir + "settings.json"

  // Noctalia configuration properties
  property string noctaliaWallpaper: ""
  property string noctaliaAvatarImage: ""
  property bool noctaliaConfigLoaded: false

  signal noctaliaConfigUpdated

  // Debounced save
  Timer {
    id: saveTimer
    interval: 400
    repeat: false
    onTriggered: settingsFileView.writeAdapter()
  }

  // Ensure cache dir exists
  Item {
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.cacheDir])
  }

  // Load noctalia settings
  FileView {
    id: noctaliaSettingsLoader
    path: root.noctaliaSettingsFile
    watchChanges: true

    JsonAdapter {
      id: noctaliaSettings
      property JsonObject general: JsonObject {
        property string avatarImage: ""
      }
      property JsonObject wallpaper: JsonObject {
        property bool enabled: true
        property string directory: ""
        property bool setWallpaperOnAllMonitors: true
        property list<var> monitors: []
      }
    }

    onLoaded: {
      console.log("[INFO] Loaded noctalia settings from:", root.noctaliaSettingsFile)
      updateFromNoctaliaConfig()
    }

    onLoadFailed: function (error) {
      console.log("[WARN] Failed to load noctalia settings:", error)
      console.log("[INFO] Using fallback configuration")
      root.noctaliaConfigLoaded = false
    }

    Component.onCompleted: reload()
  }

  function updateFromNoctaliaConfig() {
    // Update avatar image
    if (noctaliaSettings.general.avatarImage) {
      root.noctaliaAvatarImage = noctaliaSettings.general.avatarImage
      console.log("[INFO] Using noctalia avatar:", root.noctaliaAvatarImage)
    }

    // Update wallpaper
    if (noctaliaSettings.wallpaper.enabled) {
      updateWallpaperFromNoctaliaConfig()
    } else {
      console.log("[INFO] Wallpaper disabled in noctalia config")
    }

    root.noctaliaConfigLoaded = true
    root.noctaliaConfigUpdated()
  }

  function updateWallpaperFromNoctaliaConfig() {
    // Get current monitor name (first available screen)
    let currentMonitorName = ""
    if (Quickshell.screens.length > 0) {
      currentMonitorName = Quickshell.screens[0].name
    }

    // Look for monitor-specific wallpaper
    const monitors = noctaliaSettings.wallpaper.monitors
    let foundWallpaper = ""

    if (monitors && monitors.length > 0) {
      for (var i = 0; i < monitors.length; i++) {
        const monitor = monitors[i]
        if (monitor && monitor.name === currentMonitorName && monitor.wallpaper) {
          foundWallpaper = monitor.wallpaper
          console.log("[INFO] Found monitor-specific wallpaper for", currentMonitorName + ":", foundWallpaper)
          break
        }
      }
    }

    // Fallback to first monitor's wallpaper if available
    if (!foundWallpaper && monitors && monitors.length > 0) {
      const firstMonitor = monitors[0]
      if (firstMonitor && firstMonitor.wallpaper) {
        foundWallpaper = firstMonitor.wallpaper
        console.log("[INFO] Using first monitor's wallpaper:", foundWallpaper)
      }
    }

    if (foundWallpaper) {
      root.noctaliaWallpaper = foundWallpaper
      console.log("[INFO] Using noctalia wallpaper:", foundWallpaper)
    } else {
      console.log("[INFO] No wallpaper found in noctalia config")
    }
  }

  // Persisted data (greet-specific cache)
  FileView {
    id: settingsFileView
    path: root.settingsFile
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: saveTimer.start()
    Component.onCompleted: reload()
    JsonAdapter {
      id: adapter
      // Remember last selected compositor/session id (e.g. hyprland, sway)
      property string lastSessionId: ""
    }
  }

  // Public alias to persisted fields
  readonly property alias data: adapter

  // Convenience getters/setters
  property string lastSessionId: adapter.lastSessionId
  function setLastSessionId(id) {
    adapter.lastSessionId = id || ""
    saveTimer.restart()
  }

  function save() {
    saveTimer.restart()
  }
}
