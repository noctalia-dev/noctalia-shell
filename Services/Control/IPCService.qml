import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Services.Media
import qs.Services.Networking
import qs.Services.Noctalia
import qs.Services.Power
import qs.Services.System
import qs.Services.Theming
import qs.Services.UI

Item {
  id: root

  // Screen detector passed from shell.qml
  required property CurrentScreenDetector screenDetector

  IpcHandler {
    target: "bar"
    function toggle() {
      BarService.isVisible = !BarService.isVisible;
    }
    function hide() {
      BarService.isVisible = false;
    }
    function show() {
      BarService.isVisible = true;
    }
  }

  IpcHandler {
    target: "settings"
    function toggle() {
      if (Settings.data.ui.settingsPanelMode === "window") {
        SettingsPanelService.toggleWindow(SettingsPanel.Tab.General);
      } else {
        root.screenDetector.withCurrentScreen(screen => {
                                                var settingsPanel = PanelService.getPanel("settingsPanel", screen);
                                                settingsPanel.requestedTab = SettingsPanel.Tab.General;
                                                settingsPanel?.toggle();
                                              });
      }
    }
  }

  IpcHandler {
    target: "calendar"
    function toggle() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var clockPanel = PanelService.getPanel("clockPanel", screen);
                                              clockPanel?.toggle(null, "Clock");
                                            });
    }
  }

  IpcHandler {
    target: "notifications"
    function toggleHistory() {
      // Will attempt to open the panel next to the bar button if any.
      root.screenDetector.withCurrentScreen(screen => {
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

    function getHistory(): string {
      return JSON.stringify(NotificationService.getHistorySnapshot(), null, 2);
    }

    function removeFromHistory(id: string): bool {
      return NotificationService.removeFromHistory(id);
    }
  }

  IpcHandler {
    target: "idleInhibitor"
    function toggle() {
      return IdleInhibitorService.manualToggle();
    }
    function enable() {
      IdleInhibitorService.addManualInhibitor(null);
    }
    function disable() {
      IdleInhibitorService.removeManualInhibitor();
    }
  }

  IpcHandler {
    target: "launcher"
    function toggle() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                                              if (!launcherPanel)
                                              return;
                                              var searchText = launcherPanel.searchText || "";
                                              var isInAppMode = !searchText.startsWith(">");
                                              if (!launcherPanel.isPanelOpen) {
                                                // Closed -> open in app mode
                                                launcherPanel.open();
                                                launcherPanel.setSearchText("");
                                              } else if (isInAppMode) {
                                                // Already in app mode -> close
                                                launcherPanel.close();
                                              } else {
                                                // In another mode -> switch to app mode
                                                launcherPanel.setSearchText("");
                                              }
                                            });
    }
    function clipboard() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                                              if (!launcherPanel)
                                              return;
                                              var searchText = launcherPanel.searchText || "";
                                              var isInClipMode = searchText.startsWith(">clip");
                                              if (!launcherPanel.isPanelOpen) {
                                                // Closed -> open in clipboard mode
                                                launcherPanel.open();
                                                launcherPanel.setSearchText(">clip ");
                                              } else if (isInClipMode) {
                                                // Already in clipboard mode -> close
                                                launcherPanel.close();
                                              } else {
                                                // In another mode -> switch to clipboard mode
                                                launcherPanel.setSearchText(">clip ");
                                              }
                                            });
    }
    function emoji() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                                              if (!launcherPanel)
                                              return;
                                              var searchText = launcherPanel.searchText || "";
                                              var isInEmojiMode = searchText.startsWith(">emoji");
                                              if (!launcherPanel.isPanelOpen) {
                                                // Closed -> open in emoji mode
                                                launcherPanel.open();
                                                launcherPanel.setSearchText(">emoji ");
                                              } else if (isInEmojiMode) {
                                                // Already in emoji mode -> close
                                                launcherPanel.close();
                                              } else {
                                                // In another mode -> switch to emoji mode
                                                launcherPanel.setSearchText(">emoji ");
                                              }
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
    target: "nightLight"
    function toggle() {
      if (!ProgramCheckerService.wlsunsetAvailable) {
        Logger.w("IPC", "wlsunset not available, cannot toggle night light");
        return;
      }

      if (Settings.data.nightLight.forced) {
        Settings.data.nightLight.enabled = false;
        Settings.data.nightLight.forced = false;
      } else {
        Settings.data.nightLight.enabled = true;
        Settings.data.nightLight.forced = true;
      }
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
    function togglePanel() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var panel = PanelService.getPanel("audioPanel", screen);
                                              panel?.toggle();
                                            });
    }
    function openPanel() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var panel = PanelService.getPanel("audioPanel", screen);
                                              panel?.open();
                                            });
    }
    function closePanel() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var panel = PanelService.getPanel("audioPanel", screen);
                                              panel?.close();
                                            });
    }
  }

  IpcHandler {
    target: "sessionMenu"
    function toggle() {
      root.screenDetector.withCurrentScreen(screen => {
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
      root.screenDetector.withCurrentScreen(screen => {
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
        root.screenDetector.withCurrentScreen(screen => {
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
    target: "wifi"
    function toggle() {
      NetworkService.setWifiEnabled(!NetworkService.wifiEnabled);
    }
    function enable() {
      NetworkService.setWifiEnabled(true);
    }
    function disable() {
      NetworkService.setWifiEnabled(false);
    }

    // TODO REMOVE IN FEB. 2026
    function togglePanel() {
      ToastService.showWarning("This IPC call will be deprecated soon, use 'network togglePanel' instead.");
      root.screenDetector.withCurrentScreen(screen => {
                                              var networkPanel = PanelService.getPanel("networkPanel", screen);
                                              networkPanel?.toggle(null, "WiFi");
                                            });
    }
  }

  IpcHandler {
    target: "network"
    function togglePanel() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var networkPanel = PanelService.getPanel("networkPanel", screen);
                                              networkPanel?.toggle(null, "WiFi");
                                            });
    }
  }

  IpcHandler {
    target: "bluetooth"
    function toggle() {
      BluetoothService.setBluetoothEnabled(!BluetoothService.enabled);
    }
    function enable() {
      BluetoothService.setBluetoothEnabled(true);
    }
    function disable() {
      BluetoothService.setBluetoothEnabled(false);
    }
    function togglePanel() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var bluetoothPanel = PanelService.getPanel("bluetoothPanel", screen);
                                              bluetoothPanel?.toggle(null, "Bluetooth");
                                            });
    }
  }

  IpcHandler {
    target: "battery"
    function togglePanel() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var batteryPanel = PanelService.getPanel("batteryPanel", screen);
                                              batteryPanel?.toggle(null, "Battery");
                                            });
    }
  }

  IpcHandler {
    target: "powerProfile"
    function cycle() {
      PowerProfileService.cycleProfile();
    }

    function cycleReverse() {
      PowerProfileService.cycleProfileReverse();
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

  // TODO REMOVE IN FEB. 2026
  IpcHandler {
    target: "osd"

    function showText(text: string) {
      ToastService.showNotice(text, "This IPC call will be deprecated soon, use 'toast send' instead.");
    }

    function showTextWithIcon(text: string, icon: string) {
      ToastService.showNotice(text, "This IPC call will be deprecated soon, use 'toast send' instead.", icon);
    }
  }

  IpcHandler {
    target: "toast"

    function send(json: string) {
      try {
        var data = JSON.parse(json);
        var title = data.title || "";
        var body = data.body || "";
        var icon = data.icon || "";
        var type = data.type || "notice";
        var duration = data.duration;

        switch (type) {
        case "warning":
          ToastService.showWarning(title, body, duration ?? 4000);
          break;
        case "error":
          ToastService.showError(title, body, duration ?? 6000);
          break;
        default:
          ToastService.showNotice(title, body, icon, duration ?? 3000);
        }
      } catch (error) {
        Logger.e("IPC", "Failed to parse toast JSON: " + error);
      }
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

  IpcHandler {
    target: "desktopWidgets"
    function toggle() {
      Settings.data.desktopWidgets.enabled = !Settings.data.desktopWidgets.enabled;
    }
    function disable() {
      Settings.data.desktopWidgets.enabled = false;
    }
    function enable() {
      Settings.data.desktopWidgets.enabled = true;
    }
    function edit() {
      DesktopWidgetRegistry.editMode = !DesktopWidgetRegistry.editMode;
    }
  }

  IpcHandler {
    target: "location"
    function get(): string {
      return Settings.data.location.name;
    }
    function set(name: string) {
      Settings.data.location.name = name;
    }
  }
}
