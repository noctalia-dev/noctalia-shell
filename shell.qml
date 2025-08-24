
/*
 * Noctalia – made by https://github.com/noctalia-dev
 * Licensed under the MIT License.
 * Forks and modifications are allowed under the MIT License,
 * but proper credit must be given to the original author.
*/

// Disable reload popup add this as a new row:  //pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import qs.Commons
import qs.Modules.Launcher
import qs.Modules.Background
import qs.Modules.Bar
import qs.Modules.BluetoothPanel
import qs.Modules.Calendar
import qs.Modules.Dock
import qs.Modules.IPC
import qs.Modules.LockScreen
import qs.Modules.Notification
import qs.Modules.SettingsPanel
import qs.Modules.PowerPanel
import qs.Modules.SidePanel
import qs.Modules.Toast
import qs.Modules.WiFiPanel
import qs.Modules.ArchUpdaterPanel
import qs.Services
import qs.Widgets

ShellRoot {
  id: shellRoot

  Background {}
  Overview {}
  ScreenCorners {}
  Bar {}
  Dock {}

  Launcher {
    id: launcherPanel
  }

  SidePanel {
    id: sidePanel
  }

  Calendar {
    id: calendarPanel
  }

  SettingsPanel {
    id: settingsPanel
  }

  Notification {
    id: notification
  }

  NotificationHistoryPanel {
    id: notificationHistoryPanel
  }

  LockScreen {
    id: lockScreen
  }

  PowerPanel {
    id: powerPanel
  }

  WiFiPanel {
    id: wifiPanel
  }

  BluetoothPanel {
    id: bluetoothPanel
  }

  ArchUpdaterPanel {
    id: updatePanel
  }

  ToastManager {}

  IPCManager {}

  Component.onCompleted: {
    // Save a ref. to our sidePanel so we can access it from services
    PanelService.sidePanel = sidePanel

    // Save a ref. to our lockScreen so we can access it from services
    PanelService.lockScreen = lockScreen

    // Save a ref. to our updatePanel so we can access it from services
    PanelService.updatePanel = updatePanel

    // Ensure our singleton is created as soon as possible so we start fetching weather asap
    LocationService.init()
  }
}
