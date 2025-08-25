import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

Item {
  id: root

  IpcHandler {
    target: "settings"
    function toggle() {
      settingsPanel.toggle(Quickshell.screens[0])
    }
  }

  IpcHandler {
    target: "notifications"
    function toggleHistory() {
      notificationHistoryPanel.toggle(Quickshell.screens[0])
    }
    function toggleDoNotDisturb() {// TODO
    }
  }

  IpcHandler {
    target: "idleInhibitor"
    function toggle() {
      return IdleInhibitorService.manualToggle()
    }
  }

  IpcHandler {
    target: "appLauncher"
    function toggle() {
      launcherPanel.toggle(Quickshell.screens[0])
    }
    function clipboard() {
      launcherPanel.toggle(Quickshell.screens[0])
      // Use the setSearchText function to set clipboard mode
      Qt.callLater(() => {
                     launcherPanel.setSearchText(">clip ")
                   })
    }
    function calculator() {
      launcherPanel.toggle(Quickshell.screens[0])
      // Use the setSearchText function to set calculator mode
      Qt.callLater(() => {
                     launcherPanel.setSearchText(">calc ")
                   })
    }
  }

  IpcHandler {
    target: "launcher"
    function toggle() {
      launcherPanel.toggle(Quickshell.screens[0])
    }
    function clipboard() {
      launcherPanel.toggle(Quickshell.screens[0])
      // Use the setSearchText function to set clipboard mode
      Qt.callLater(() => {
                     launcherPanel.setSearchText(">clip ")
                   })
    }
    function calculator() {
      launcherPanel.toggle(Quickshell.screens[0])
      // Use the setSearchText function to set calculator mode
      Qt.callLater(() => {
                     launcherPanel.setSearchText(">calc ")
                   })
    }
  }

  IpcHandler {
    target: "lockScreen"
    function toggle() {
      // Only lock if not already locked (prevents the red screen issue)
      // Note: No unlock via IPC for security reasons
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
    target: "powerPanel"
    function toggle() {
      powerPanel.toggle(Quickshell.screens[0])
    }
  }

  IpcHandler {
    target: "sidePanel"
    function toggle() {
      sidePanel.toggle(Quickshell.screens[0])
    }
  }
}
