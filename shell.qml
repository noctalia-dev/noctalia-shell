
/*
 * Noctalia – made by https://github.com/noctalia-dev
 * Licensed under the MIT License.
 * Forks and modifications are allowed under the MIT License,
 * but proper credit must be given to the original author.
*/

// Qt & Quickshell Core
import QtQuick
import Quickshell

// Commons & Services
import qs.Commons
import qs.Services.Control
import qs.Services.Theming
import qs.Services.Hardware
import qs.Services.Location
import qs.Services.Networking
import qs.Services.Power
import qs.Services.System
import qs.Services.UI

// Modules
import qs.Modules.Background
import qs.Modules.Bar
import qs.Modules.Dock
import qs.Modules.MainScreen
import qs.Modules.LockScreen
import qs.Modules.Notification
import qs.Modules.OSD
import qs.Modules.Toast

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
        LocationService.init()
        NightLightService.apply()
        DarkModeService.init()
        HooksService.init()
        BluetoothService.init()
        BatteryService.init()
        IdleInhibitorService.init()
        PowerProfileService.init()
        DistroService.init()
        FontService.init()

        // Only open the setup wizard for new users
        if (!Settings.data.setupCompleted) {
          checkSetupWizard()
        }
      }

      Overview {}
      Background {}
      Dock {}
      ToastOverlay {}
      OSD {}
      Notification {}

      LockScreen {
        id: lockScreen
        Component.onCompleted: {
          // Save a ref. to our lockScreen so we can access it  easily
          PanelService.lockScreen = lockScreen
        }
      }

      // IPCService is treated as a service but it's actually an
      // Item that needs to exists in the shell.
      IPCService {}

      // MainScreen for each screen
      AllScreens {}
    }
  }

  // ---------------------------------------------
  // Setup Wizard
  // ---------------------------------------------
  Timer {
    id: setupWizardTimer
    running: false
    interval: 1000
    onTriggered: {
      showSetupWizard()
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
      setupWizardTimer.start()
    } else {
      Settings.data.setupCompleted = true
    }
  }

  function showSetupWizard() {
    // Open Setup Wizard as a panel in the same windowing system as Settings/ControlCenter
    if (Quickshell.screens.length > 0) {
      var targetScreen = Quickshell.screens[0]
      var setupPanel = PanelService.getPanel("setupWizardPanel", targetScreen)
      if (setupPanel) {
        setupPanel.open()
      } else {
        // If not yet loaded, ensure it loads and try again shortly
        setupWizardTimer.restart()
      }
    }
  }
}
