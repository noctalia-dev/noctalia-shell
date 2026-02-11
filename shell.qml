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

// Modules
import qs.Modules.Background
import qs.Modules.Bar
import qs.Modules.DesktopWidgets
import qs.Modules.Dock
import qs.Modules.LockScreen
import qs.Modules.MainScreen
import qs.Modules.Notification
import qs.Modules.OSD
import qs.Modules.Panels.Launcher
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

        // Critical services needed for initial UI rendering
        WallpaperService.init();
        ImageCacheService.init();
        AppThemeService.init();
        ColorSchemeService.init();
        DarkModeService.init();

        // Defer non-critical services to unblock first frame
        Qt.callLater(function () {
          LocationService.init();
          NightLightService.apply();
          HooksService.init();
          BluetoothService.init();
          IdleInhibitorService.init();
          PowerProfileService.init();
          HostService.init();
          GitHubService.init();
          SupporterService.init();
        });

        delayedInitTimer.running = true;
      }

      Overview {}
      Background {}
      DesktopWidgets {}
      AllScreens {}
      Dock {}
      Notification {}
      ToastOverlay {}
      OSD {}

      // Launcher overlay window (for overlay layer mode)
      Loader {
        active: Settings.data.appLauncher.overviewLayer
        sourceComponent: Component {
          LauncherOverlayWindow {}
        }
      }

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

      // CustomButtonIPCService handles IPC commands for custom buttons
      CustomButtonIPCService {
        id: customButtonIPCService
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
  // Delayed initialization and wizard/changelog
  // ---------------------------------------------
  Timer {
    id: delayedInitTimer
    running: false
    interval: 1500
    onTriggered: {
      FontService.init();
      UpdateService.init();
      showWizardOrChangelog();
    }
  }

  // Retry timer for when panel isn't ready yet
  Timer {
    id: wizardRetryTimer
    running: false
    interval: 500
    property string pendingWizardType: "" // "setup", "telemetry", or ""
    onTriggered: showWizardOrChangelog()
  }

  // Connect to telemetry wizard signal from UpdateService (for async state loading)
  Connections {
    target: UpdateService
    function onTelemetryWizardNeeded() {
      wizardRetryTimer.pendingWizardType = "telemetry";
      showWizardOrChangelog();
    }
  }

  property var telemetryWizardConnection: null

  function showWizardOrChangelog() {
    // Determine what to show: setup wizard > telemetry wizard > changelog
    var wizardType = wizardRetryTimer.pendingWizardType;

    if (wizardType === "") {
      // First call - determine wizard type
      if (Settings.shouldOpenSetupWizard) {
        wizardType = "setup";
      } else if (UpdateService.shouldShowTelemetryWizard()) {
        wizardType = "telemetry";
      } else {
        // No wizard needed - init telemetry and show changelog
        TelemetryService.init();
        UpdateService.checkTelemetryWizardOrChangelog();
        return;
      }
    }

    var targetScreen = PanelService.findScreenForPanels();
    if (!targetScreen) {
      Logger.w("Shell", "No screen available to show wizard");
      wizardRetryTimer.pendingWizardType = "";
      return;
    }

    var setupPanel = PanelService.getPanel("setupWizardPanel", targetScreen);
    if (!setupPanel) {
      // Panel not ready, retry
      wizardRetryTimer.pendingWizardType = wizardType;
      wizardRetryTimer.restart();
      return;
    }

    // Panel is ready, show it
    wizardRetryTimer.pendingWizardType = "";

    if (wizardType === "telemetry") {
      setupPanel.telemetryOnlyMode = true;

      // Connect to completion signal to show changelog afterward
      if (telemetryWizardConnection) {
        setupPanel.telemetryWizardCompleted.disconnect(telemetryWizardConnection);
      }
      telemetryWizardConnection = function () {
        UpdateService.showLatestChangelog();
      };
      setupPanel.telemetryWizardCompleted.connect(telemetryWizardConnection);
    } else {
      setupPanel.telemetryOnlyMode = false;
    }

    setupPanel.open();
  }
}
