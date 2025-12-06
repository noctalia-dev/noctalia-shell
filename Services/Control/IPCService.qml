import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

import qs.Commons
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Services.Media
import qs.Services.Noctalia
import qs.Services.Power
import qs.Services.System
import qs.Services.Theming
import qs.Services.UI

Item {
  id: root

  IpcHandler {
    target: "bar"
    function toggle() {
      BarService.isVisible = !BarService.isVisible;
    }
  }

  IpcHandler {
    target: "screenRecorder"
    function toggle() {
      if (ScreenRecorderService.isAvailable) {
        ScreenRecorderService.toggleRecording();
      }
    }
  }

  IpcHandler {
    target: "settings"
    function toggle() {
      root.withTargetScreen(screen => {
                              var settingsPanel = PanelService.getPanel("settingsPanel", screen);
                              settingsPanel?.toggle();
                            });
    }
  }

  IpcHandler {
    target: "calendar"
    function toggle() {
      root.withTargetScreen(screen => {
                              var clockPanel = PanelService.getPanel("clockPanel", screen);
                              clockPanel?.toggle(null, "Clock");
                            });
    }
  }

  IpcHandler {
    target: "notifications"
    function toggleHistory() {
      // Will attempt to open the panel next to the bar button if any.
      root.withTargetScreen(screen => {
                              var notificationHistoryPanel = PanelService.getPanel("notificationHistoryPanel", screen);
                              notificationHistoryPanel.toggle(null, "NotificationHistory");
                            });
    }
    function toggleDND() {
      NotificationService.doNotDisturb = !NotificationService.doNotDisturb;
    }
    function enableDND() {
      NotificationService.doNotDisturb = true;
    }
    function disableDND() {
      NotificationService.doNotDisturb = false;
    }
    function clear() {
      NotificationService.clearHistory();
    }

    function dismissOldest() {
      NotificationService.dismissOldestActive();
    }

    function removeOldestHistory() {
      NotificationService.removeOldestHistory();
    }

    function dismissAll() {
      NotificationService.dismissAllActive();
    }
  }

  IpcHandler {
    target: "idleInhibitor"
    function toggle() {
      return IdleInhibitorService.manualToggle();
    }
  }

  IpcHandler {
    target: "launcher"
    function toggle() {
      root.withTargetScreen(screen => {
                              var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                              if (!launcherPanel?.isPanelOpen || (launcherPanel?.isPanelOpen && !launcherPanel?.activePlugin))
                              launcherPanel?.toggle();
                              launcherPanel?.setSearchText("");
                            });
    }
    function clipboard() {
      root.withTargetScreen(screen => {
                              var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                              if (!launcherPanel?.isPanelOpen) {
                                launcherPanel?.toggle();
                              }
                              launcherPanel?.setSearchText(">clip ");
                            });
    }
    function calculator() {
      root.withTargetScreen(screen => {
                              var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                              if (!launcherPanel?.isPanelOpen) {
                                launcherPanel?.toggle();
                              }
                              launcherPanel?.setSearchText(">calc ");
                            });
    }
    function emoji() {
      root.withTargetScreen(screen => {
                              var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                              if (!launcherPanel?.isPanelOpen) {
                                launcherPanel?.toggle();
                              }
                              launcherPanel?.setSearchText(">emoji ");
                            });
    }
  }

  IpcHandler {
    target: "lockScreen"

    // New preferred method - lock the screen
    function lock() {
      // Only lock if not already locked (prevents the red screen issue)
      if (!PanelService.lockScreen.active) {
        PanelService.lockScreen.active = true;
      }
    }
  }

  IpcHandler {
    target: "brightness"
    function increase() {
      BrightnessService.increaseBrightness();
    }
    function decrease() {
      BrightnessService.decreaseBrightness();
    }
  }

  IpcHandler {
    target: "darkMode"
    function toggle() {
      Settings.data.colorSchemes.darkMode = !Settings.data.colorSchemes.darkMode;
    }
    function setDark() {
      Settings.data.colorSchemes.darkMode = true;
    }
    function setLight() {
      Settings.data.colorSchemes.darkMode = false;
    }
  }

  IpcHandler {
    target: "colorScheme"
    function set(schemeName: string) {
      ColorSchemeService.setPredefinedScheme(schemeName);
    }
  }

  IpcHandler {
    target: "volume"
    function increase() {
      AudioService.increaseVolume();
    }
    function decrease() {
      AudioService.decreaseVolume();
    }
    function muteOutput() {
      AudioService.setOutputMuted(!AudioService.muted);
    }
    function increaseInput() {
      AudioService.increaseInputVolume();
    }
    function decreaseInput() {
      AudioService.decreaseInputVolume();
    }
    function muteInput() {
      AudioService.setInputMuted(!AudioService.inputMuted);
    }
  }

  IpcHandler {
    target: "sessionMenu"
    function toggle() {
      root.withTargetScreen(screen => {
                              var sessionMenuPanel = PanelService.getPanel("sessionMenuPanel", screen);
                              sessionMenuPanel?.toggle();
                            });
    }

    function lockAndSuspend() {
      CompositorService.lockAndSuspend();
    }
  }

  IpcHandler {
    target: "controlCenter"
    function toggle() {
      root.withTargetScreen(screen => {
                              var controlCenterPanel = PanelService.getPanel("controlCenterPanel", screen);
                              if (Settings.data.controlCenter.position === "close_to_bar_button") {
                                // Will attempt to open the panel next to the bar button if any.
                                controlCenterPanel?.toggle(null, "ControlCenter");
                              } else {
                                controlCenterPanel?.toggle();
                              }
                            });
    }
  }

  IpcHandler {
    target: "dock"
    function toggle() {
      Settings.data.dock.enabled = !Settings.data.dock.enabled;
    }
  }

  // Wallpaper IPC: trigger a new random wallpaper
  IpcHandler {
    target: "wallpaper"
    function toggle() {
      if (Settings.data.wallpaper.enabled) {
        root.withTargetScreen(screen => {
                                var wallpaperPanel = PanelService.getPanel("wallpaperPanel", screen);
                                wallpaperPanel?.toggle();
                              });
      }
    }

    function random() {
      if (Settings.data.wallpaper.enabled) {
        WallpaperService.setRandomWallpaper();
      }
    }

    function set(path: string, screen: string) {
      if (screen === "all" || screen === "") {
        screen = undefined;
      }
      WallpaperService.changeWallpaper(path, screen);
    }

    function toggleAutomation() {
      Settings.data.wallpaper.randomEnabled = !Settings.data.wallpaper.randomEnabled;
    }
    function disableAutomation() {
      Settings.data.wallpaper.randomEnabled = false;
    }
    function enableAutomation() {
      Settings.data.wallpaper.randomEnabled = true;
    }
  }

  IpcHandler {
    target: "batteryManager"

    function cycle() {
      BatteryService.cycleModes();
    }

    function set(mode: string) {
      switch (mode) {
      case "full":
        BatteryService.setChargingMode(BatteryService.ChargingMode.Full);
        break;
      case "balanced":
        BatteryService.setChargingMode(BatteryService.ChargingMode.Balanced);
        break;
      case "lifespan":
        BatteryService.setChargingMode(BatteryService.ChargingMode.Lifespan);
        break;
      }
    }
  }

  IpcHandler {
    target: "powerProfile"
    function cycle() {
      PowerProfileService.cycleProfile();
    }

    function set(mode: string) {
      switch (mode) {
      case "performance":
        PowerProfileService.setProfile(2);
        break;
      case "balanced":
        PowerProfileService.setProfile(1);
        break;
      case "powersaver":
        PowerProfileService.setProfile(0);
        break;
      }
    }

    function toggleNoctaliaPerformance() {
      PowerProfileService.toggleNoctaliaPerformance();
    }

    function enableNoctaliaPerformance() {
      PowerProfileService.setNoctaliaPerformance(true);
    }

    function disableNoctaliaPerformance() {
      PowerProfileService.setNoctaliaPerformance(false);
    }
  }

  IpcHandler {
    target: "media"
    function playPause() {
      MediaService.playPause();
    }

    function play() {
      MediaService.play();
    }

    function stop() {
      MediaService.stop();
    }

    function pause() {
      MediaService.pause();
    }

    function next() {
      MediaService.next();
    }

    function previous() {
      MediaService.previous();
    }

    function seekRelative(offset: string) {
      var offsetVal = parseFloat(offset);
      if (Number.isNaN(offsetVal)) {
        Logger.w("Media", "Argument to ipc call 'media seekRelative' must be a number");
        return;
      }
      MediaService.seekRelative(offsetVal);
    }

    function seekByRatio(position: string) {
      var positionVal = parseFloat(position);
      if (Number.isNaN(positionVal)) {
        Logger.w("Media", "Argument to ipc call 'media seekByRatio' must be a number");
        return;
      }
      MediaService.seekByRatio(positionVal);
    }
  }

  IpcHandler {
    target: "state"

    // Returns all settings and shell state as JSON
    function all(): string {
      try {
        var snapshot = ShellState.buildStateSnapshot();
        if (!snapshot) {
          throw new Error("State snapshot unavailable");
        }
        return JSON.stringify(snapshot, null, 2);
      } catch (error) {
        Logger.e("IPC", "Failed to serialize state:", error);
        return JSON.stringify({
                                "error": "Failed to serialize state: " + error
                              }, null, 2);
      }
    }
  }

  // -------------------------------------------------------------------
  // Queue an IPC panel operation - will execute when screen is detected
  // -------------------------------------------------------------------
  function withTargetScreen(callback) {
    if (pendingCallback) {
      Logger.w("IPC", "Another IPC call is pending, ignoring new call");
      return;
    }

    // Single monitor setup can execute immediately
    if (Quickshell.screens.length === 1) {
      callback(Quickshell.screens[0]);
    } else {
      // Multi-monitors setup needs to start async detection
      detectedScreen = null;
      pendingCallback = callback;
      screenDetectorLoader.active = true;
    }
  }
  /**
  * For IPC calls on multi-monitors setup that will open panels on screen,
  * we need to open a QS PanelWindow and wait for it's "screen" property to stabilize.
  */
  property ShellScreen detectedScreen: null
  property var pendingCallback: null

  Timer {
    id: screenDetectorDebounce
    running: false
    interval: 20
    onTriggered: {
      Logger.d("IPC", "Screen debounced to:", detectedScreen?.name || "null");

      // Execute pending callback if any
      if (pendingCallback) {
        if (!Settings.data.general.allowPanelsOnScreenWithoutBar) {
          // If we explicitely disabled panels on screen without bar, check if bar is configured
          // for this screen, and fallback to primary screen if necessary
          var monitors = Settings.data.bar.monitors || [];
          const hasBar = monitors.length === 0 || monitors.includes(detectedScreen?.name);
          if (!hasBar) {
            detectedScreen = Quickshell.screens[0];
          }
        }

        Logger.d("IPC", "Executing pending IPC callback on screen:", detectedScreen.name);
        pendingCallback(detectedScreen);
        pendingCallback = null;
      }

      // Clean up
      screenDetectorLoader.active = false;
    }
  }

  // Invisible dummy PanelWindow to detect which screen should receive IPC calls
  Loader {
    id: screenDetectorLoader
    active: false

    sourceComponent: PanelWindow {
      implicitWidth: 0
      implicitHeight: 0
      color: Color.transparent
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-ipc-screen-detector"
      mask: Region {}

      onScreenChanged: {
        detectedScreen = screen;
        screenDetectorDebounce.restart();
      }
    }
  }
  // -------------------------------------------------------------------
  // -------------------------------------------------------------------
}
