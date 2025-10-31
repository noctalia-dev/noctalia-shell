
/*
 * Noctalia – made by https://github.com/noctalia-dev
 * Licensed under the MIT License.
 * Forks and modifications are allowed under the MIT License,
 * but proper credit must be given to the original author.
*/

// Qt & Quickshell Core
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Widgets

// Commons & Services
import qs.Commons
import qs.Services
import qs.Widgets

// Core Modules
import qs.Modules.Background
import qs.Modules.Dock
import qs.Modules.LockScreen
import qs.Modules.SessionMenu

// Bar & Bar Components
import qs.Modules.Bar
import qs.Modules.Bar.Extras
import qs.Modules.Bar.Audio
import qs.Modules.Bar.Bluetooth
import qs.Modules.Bar.Battery
import qs.Modules.Bar.Calendar
import qs.Modules.Bar.WiFi

// Panels & UI Components
import qs.Modules.ControlCenter
import qs.Modules.Launcher
import qs.Modules.Notification
import qs.Modules.OSD
import qs.Modules.Settings
import qs.Modules.Toast
import qs.Modules.Wallpaper
import qs.Modules.SetupWizard

ShellRoot {
  id: shellRoot

  property bool i18nLoaded: false
  property bool settingsLoaded: false

  Component.onCompleted: {
    Logger.i("Shell", "---------------------------")
    Logger.i("Shell", "Noctalia Hello!")
  }

  Connections {
    target: Quickshell
    function onReloadCompleted() {
      Quickshell.inhibitReloadPopup()
    }
  }

  Connections {
    target: I18n ? I18n : null
    function onTranslationsLoaded() {
      i18nLoaded = true
    }
  }

  Connections {
    target: Settings ? Settings : null
    function onSettingsLoaded() {
      settingsLoaded = true
    }
  }

  Loader {
    active: i18nLoaded && settingsLoaded

    sourceComponent: Item {
      Component.onCompleted: {
        Logger.i("Shell", "---------------------------")
        WallpaperService.init()
        AppThemeService.init()
        ColorSchemeService.init()
        BarWidgetRegistry.init()
        LocationService.init()
        NightLightService.apply()
        DarkModeService.init()
        FontService.init()
        HooksService.init()
        BluetoothService.init()
        BatteryService.init()
        IdleInhibitorService.init()
        PowerProfileService.init()
        DistroService.init()
      }

      Background {}
      Overview {}
      ScreenCorners {}
      Bar {}
      Dock {}

      Notification {
        id: notification
      }

      LockScreen {
        id: lockScreen
        Component.onCompleted: {
          // Save a ref. to our lockScreen so we can access it  easily
          PanelService.lockScreen = lockScreen
        }
      }

      ToastOverlay {}
      OSD {}

      // IPCService is treated as a service
      // but it's actually an Item that needs to exists in the shell.
      IPCService {}

      // ------------------------------
      // All the NPanels
      Launcher {
        id: launcherPanel
        objectName: "launcherPanel"
      }

      ControlCenterPanel {
        id: controlCenterPanel
        objectName: "controlCenterPanel"
      }

      CalendarPanel {
        id: calendarPanel
        objectName: "calendarPanel"
      }

      SettingsPanel {
        id: settingsPanel
        objectName: "settingsPanel"
      }

      DirectWidgetSettingsPanel {
        id: directWidgetSettingsPanel
        objectName: "directWidgetSettingsPanel"
      }

      NotificationHistoryPanel {
        id: notificationHistoryPanel
        objectName: "notificationHistoryPanel"
      }

      SessionMenu {
        id: sessionMenuPanel
        objectName: "sessionMenuPanel"
      }

      WiFiPanel {
        id: wifiPanel
        objectName: "wifiPanel"
      }

      BluetoothPanel {
        id: bluetoothPanel
        objectName: "bluetoothPanel"
      }

      AudioPanel {
        id: audioPanel
        objectName: "audioPanel"
      }

      WallpaperPanel {
        id: wallpaperPanel
        objectName: "wallpaperPanel"
      }

      BatteryPanel {
        id: batteryPanel
        objectName: "batteryPanel"
      }
    }
  }

  // ------------------------------
  // Setup Wizard
  Loader {
    id: setupWizardLoader
    active: false
    asynchronous: true
    sourceComponent: SetupWizard {}
    onLoaded: {
      if (setupWizardLoader.item && setupWizardLoader.item.open) {
        setupWizardLoader.item.open()
      }
    }
  }

  Connections {
    target: Settings
    function onSettingsLoaded() {
      // Only open the setup wizard for new users
      if (!Settings.data.setupCompleted) {
        checkSetupWizard()
      }
    }
  }

  function checkSetupWizard() {
    // Wait for distro service
    if (!DistroService.isReady) {
      Qt.callLater(checkSetupWizard)
      return
    }

    // No setup wizard on NixOS
    if (DistroService.isNixOS) {
      Settings.data.setupCompleted = true
      return
    }

    if (Settings.data.settingsVersion >= Settings.settingsVersion) {
      setupWizardLoader.active = true
    } else {
      Settings.data.setupCompleted = true
    }
  }
}
