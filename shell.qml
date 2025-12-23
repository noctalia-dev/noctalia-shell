/*
* Noctalia – made by https://github.com/noctalia-dev
* Licensed under the MIT License.
* Forks and modifications are allowed under the MIT License,
* but proper credit must be given to the original author.
*/

// Qt & Quickshell Core
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

// Commons & Services
import qs.Commons

// Modules
import qs.Modules.Background
import qs.Modules.Bar
import qs.Modules.DesktopWidgets
import qs.Modules.Dock
import qs.Modules.LockScreen
import qs.Modules.MainScreen
import qs.Modules.Notification
import qs.Modules.OSD
import qs.Modules.Panels.Settings
import qs.Modules.Toast
import qs.Services.Control
import qs.Services.Hardware
import qs.Services.Location
import qs.Services.Networking
import qs.Services.Noctalia
import qs.Services.Power
import qs.Services.System
import qs.Services.Theming
import qs.Services.UI

ShellRoot {
  id: shellRoot

  property bool i18nLoaded: false
  property bool settingsLoaded: false
  property bool shellStateLoaded: false

  Component.onCompleted: {
    Logger.i("Shell", "---------------------------");
    Logger.i("Shell", "Noctalia Hello!");

    // Initialize plugin system early so Settings can validate plugin widgets
    PluginRegistry.init();
  }

  Connections {
    target: Quickshell
    function onReloadCompleted() {
      Quickshell.inhibitReloadPopup();
    }
    function onReloadFailed() {
      if (!Settings?.isDebug) {
        Quickshell.inhibitReloadPopup();
      }
    }
  }

  Connections {
    target: I18n ? I18n : null
    function onTranslationsLoaded() {
      i18nLoaded = true;
    }
  }

  Connections {
    target: Settings ? Settings : null
    function onSettingsLoaded() {
      settingsLoaded = true;
    }
  }

  Connections {
    target: ShellState ? ShellState : null
    function onIsLoadedChanged() {
      if (ShellState.isLoaded) {
        shellStateLoaded = true;
      }
    }
  }

  Loader {
    active: i18nLoaded && settingsLoaded && shellStateLoaded

    sourceComponent: Item {
      Component.onCompleted: {
        Logger.i("Shell", "---------------------------");
        WallpaperService.init();
        WallpaperCacheService.init();
        AppThemeService.init();
        ColorSchemeService.init();
        LocationService.init();
        NightLightService.apply();
        DarkModeService.init();
        HooksService.init();
        BluetoothService.init();
        IdleInhibitorService.init();
        PowerProfileService.init();
        HostService.init();
        GitHubService.init();

        delayedInitTimer.running = true;
        checkSetupWizard();
      }

      Overview {}
      Background {}
      DesktopWidgets {}
      AllScreens {}
      Dock {}
      Notification {}
      ToastOverlay {}
      OSD {}

      LockScreen {}

      // Settings window mode (single window across all monitors)
      SettingsPanelWindow {}

      // Shared screen detector for IPC and plugins
      CurrentScreenDetector {
        id: screenDetector
      }

      // IPCService is treated as a service but it must be in graphics scene.
      IPCService {
        id: ipcService
        screenDetector: screenDetector
      }

      // Container for plugins Main.qml instances (must be in graphics scene)
      Item {
        id: pluginContainer
        visible: false

        Component.onCompleted: {
          PluginService.pluginContainer = pluginContainer;
          PluginService.screenDetector = screenDetector;
        }
      }
    }
  }

  // ---------------------------------------------
  // Delayed timer
  // ---------------------------------------------
  Timer {
    id: delayedInitTimer
    running: false
    interval: 1500
    onTriggered: {
      FontService.init();
      UpdateService.init();
      UpdateService.showLatestChangelog();
    }
  }

  // ---------------------------------------------
  // Setup Wizard
  // ---------------------------------------------
  Timer {
    id: setupWizardTimer
    running: false
    interval: 2000
    onTriggered: {
      showSetupWizard();
    }
  }

  function checkSetupWizard() {
    // Only open the setup wizard for new users
    if (!Settings.shouldOpenSetupWizard) {
      return;
    }

    // Wait for HostService to be fully ready
    if (!HostService.isReady) {
      Qt.callLater(checkSetupWizard);
      return;
    }

    // No setup wizard on NixOS
    if (HostService.isNixOS) {
      return;
    }

    setupWizardTimer.start();
  }

  function showSetupWizard() {
    // Open Setup Wizard as a panel in the same windowing system as Settings/ControlCenter
    if (Quickshell.screens.length > 0) {
      var targetScreen = Quickshell.screens[0];
      var setupPanel = PanelService.getPanel("setupWizardPanel", targetScreen);
      if (setupPanel) {
        setupPanel.open();
      } else {
        // If not yet loaded, ensure it loads and try again shortly
        setupWizardTimer.restart();
      }
    }
  }
}
