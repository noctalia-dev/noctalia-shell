import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services

Item {
  id: root

  IpcHandler {
    target: "bar"
    function toggle() {
      BarService.isVisible = !BarService.isVisible
    }
  }

  IpcHandler {
    target: "screenRecorder"
    function toggle() {
      if (ScreenRecorderService.isAvailable) {
        ScreenRecorderService.toggleRecording()
      }
    }
  }

  IpcHandler {
    target: "settings"
    function toggle() {
      settingsPanel.toggle()
    }
  }

  IpcHandler {
    target: "notifications"
    function toggleHistory() {
      // Will attempt to open the panel next to the bar button if any.
      notificationHistoryPanel.toggle(null, "NotificationHistory")
    }
    function toggleDND() {
      Settings.data.notifications.doNotDisturb = !Settings.data.notifications.doNotDisturb
    }
    function clear() {
      NotificationService.clearHistory()
    }

    function dismissOldest() {
      NotificationService.dismissOldestActive()
    }

    function dismissAll() {
      NotificationService.dismissAllActive()
    }
  }

  IpcHandler {
    target: "idleInhibitor"
    function toggle() {
      return IdleInhibitorService.manualToggle()
    }
  }

  IpcHandler {
    target: "launcher"
    function toggle() {
      launcherPanel.toggle()
    }
    function clipboard() {
      launcherPanel.setSearchText(">clip ")
      launcherPanel.toggle()
    }
    function calculator() {
      launcherPanel.setSearchText(">calc ")
      launcherPanel.toggle()
    }
  }

  IpcHandler {
    target: "lockScreen"

    // New preferred method - lock the screen
    function lock() {
      // Only lock if not already locked (prevents the red screen issue)
      // Note: No unlock via IPC for security reasons
      if (!lockScreen.active) {
        lockScreen.triggeredViaDeprecatedCall = false
        lockScreen.active = true
      }
    }

    // Deprecated: Use 'lockScreen lock' instead
    function toggle() {
      // Mark as triggered via deprecated call - warning will show in lock screen
      lockScreen.triggeredViaDeprecatedCall = true

      // Log deprecation warning for users checking logs
      Logger.w("IPC", "The 'lockScreen toggle' IPC call is deprecated. Use 'lockScreen lock' instead.")

      // Still functional for backward compatibility
      if (!lockScreen.active) {
        lockScreen.active = true
      }
    }
  }

  IpcHandler {
    target: "brightness"
    function increase() {
      BrightnessService.increaseBrightness()
    }
    function decrease() {
      BrightnessService.decreaseBrightness()
    }
  }

  IpcHandler {
    target: "darkMode"
    function toggle() {
      Settings.data.colorSchemes.darkMode = !Settings.data.colorSchemes.darkMode
    }
    function setDark() {
      Settings.data.colorSchemes.darkMode = true
    }
    function setLight() {
      Settings.data.colorSchemes.darkMode = false
    }
  }

  IpcHandler {
    target: "colorScheme"
    function set(schemeName: string) {
      ColorSchemeService.setPredefinedScheme(schemeName)
    }
  }

  IpcHandler {
    target: "volume"
    function increase() {
      AudioService.increaseVolume()
    }
    function decrease() {
      AudioService.decreaseVolume()
    }
    function muteOutput() {
      AudioService.setOutputMuted(!AudioService.muted)
    }
    function increaseInput() {
      AudioService.increaseInputVolume()
    }
    function decreaseInput() {
      AudioService.decreaseInputVolume()
    }
    function muteInput() {
      AudioService.setInputMuted(!AudioService.inputMuted)
    }
  }

  IpcHandler {
    target: "sessionMenu"
    function toggle() {
      sessionMenuPanel.toggle()
    }

    function lockAndSuspend() {
      CompositorService.lockAndSuspend()
    }
  }

  IpcHandler {
    target: "controlCenter"
    function toggle() {
      // Will attempt to open the panel next to the bar button if any.
      controlCenterPanel.toggle(null, "ControlCenter")
    }
  }

  // Wallpaper IPC: trigger a new random wallpaper
  IpcHandler {
    target: "wallpaper"
    function toggle() {
      if (Settings.data.wallpaper.enabled) {
        wallpaperPanel.toggle()
      }
    }

    function random() {
      if (Settings.data.wallpaper.enabled) {
        WallpaperService.setRandomWallpaper()
      }
    }

    function set(path: string, screen: string) {
      if (screen === "all" || screen === "") {
        screen = undefined
      }
      WallpaperService.changeWallpaper(path, screen)
    }

    function toggleAutomation() {
      Settings.data.wallpaper.randomEnabled = !Settings.data.wallpaper.randomEnabled
    }
    function disableAutomation() {
      Settings.data.wallpaper.randomEnabled = false
    }
    function enableAutomation() {
      Settings.data.wallpaper.randomEnabled = true
    }
  }

  IpcHandler {
    target: "batteryManager"

    function cycle() {
      BatteryService.cycleModes()
    }

    function set(mode: string) {
      switch (mode) {
      case "full":
        BatteryService.setChargingMode(BatteryService.ChargingMode.Full)
        break
      case "balanced":
        BatteryService.setChargingMode(BatteryService.ChargingMode.Balanced)
        break
      case "lifespan":
        BatteryService.setChargingMode(BatteryService.ChargingMode.Lifespan)
        break
      }
    }
  }
  IpcHandler {
    target: "powerProfile"
    function cycle() {
      PowerProfileService.cycleProfile()
    }

    function set(mode: string) {
      switch (mode) {
      case "performance":
        PowerProfileService.setProfile(2)
        break
      case "balanced":
        PowerProfileService.setProfile(1)
        break
      case "powersaver":
        PowerProfileService.setProfile(0)
        break
      }
    }
  }
  IpcHandler {
    target: "media"
    function playPause() {
      MediaService.playPause()
    }

    function play() {
      MediaService.play()
    }

    function stop() {
      MediaService.stop()
    }

    function pause() {
      MediaService.pause()
    }

    function next() {
      MediaService.next()
    }

    function previous() {
      MediaService.previous()
    }

    function seekRelative(offset: string) {
      var offsetVal = parseFloat(position)
      if (Number.isNaN(offsetVal)) {
        Logger.w("Media", "Argument to ipc call 'media seekRelative' must be a number")
        return
      }
      MediaService.seekRelative(offsetVal)
    }

    function seekByRatio(position: string) {
      var positionVal = parseFloat(position)
      if (Number.isNaN(positionVal)) {
        Logger.w("Media", "Argument to ipc call 'media seekByRatio' must be a number")
        return
      }
      MediaService.seekByRatio(positionVal)
    }
  }
}
