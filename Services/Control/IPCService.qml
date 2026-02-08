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
                                                if (settingsPanel) {
                                                  settingsPanel.requestedTab = SettingsPanel.Tab.General;
                                                  settingsPanel.openedViaKeybind = true;
                                                  settingsPanel.toggle();
                                                }
                                              });
      }
    }
  }

  IpcHandler {
    target: "calendar"
    function toggle() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var clockPanel = PanelService.getPanel("clockPanel", screen);
                                              if (clockPanel) {
                                                clockPanel.openedViaKeybind = true;
                                                clockPanel.toggle(null, "Clock");
                                              }
                                            });
    }
  }

  IpcHandler {
    target: "notifications"
    function toggleHistory() {
      // Will attempt to open the panel next to the bar button if any.
      root.screenDetector.withCurrentScreen(screen => {
                                              var notificationHistoryPanel = PanelService.getPanel("notificationHistoryPanel", screen);
                                              if (notificationHistoryPanel) {
                                                notificationHistoryPanel.openedViaKeybind = true;
                                                notificationHistoryPanel.toggle(null, "NotificationHistory");
                                              }
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
                                                launcherPanel.openedViaKeybind = true;
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
                                                launcherPanel.openedViaKeybind = true;
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
    function command() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                                              if (!launcherPanel)
                                              return;
                                              var searchText = launcherPanel.searchText || "";
                                              var isInClipMode = searchText.startsWith(">cmd");
                                              if (!launcherPanel.isPanelOpen) {
                                                // Closed -> open in clipboard mode
                                                launcherPanel.openedViaKeybind = true;
                                                launcherPanel.open();
                                                launcherPanel.setSearchText(">cmd ");
                                              } else if (isInClipMode) {
                                                // Already in clipboard mode -> close
                                                launcherPanel.close();
                                              } else {
                                                // In another mode -> switch to clipboard mode
                                                launcherPanel.setSearchText(">cmd ");
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
                                                launcherPanel.openedViaKeybind = true;
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
    function windows() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                                              if (!launcherPanel)
                                              return;
                                              var searchText = launcherPanel.searchText || "";
                                              var isInWindowsMode = searchText.startsWith(">win");
                                              if (!launcherPanel.isPanelOpen) {
                                                // Closed -> open in windows mode
                                                launcherPanel.openedViaKeybind = true;
                                                launcherPanel.open();
                                                launcherPanel.setSearchText(">win ");
                                              } else if (isInWindowsMode) {
                                                // Already in windows mode -> close
                                                launcherPanel.close();
                                              } else {
                                                // In another mode -> switch to windows mode
                                                launcherPanel.setSearchText(">win ");
                                              }
                                            });
    }
    function settings() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                                              if (!launcherPanel)
                                              return;
                                              var searchText = launcherPanel.searchText || "";
                                              var isInSettingsMode = searchText.startsWith(">settings");
                                              if (!launcherPanel.isPanelOpen) {
                                                // Closed -> open in settings mode
                                                launcherPanel.openedViaKeybind = true;
                                                launcherPanel.open();
                                                launcherPanel.setSearchText(">settings ");
                                              } else if (isInSettingsMode) {
                                                // Already in settings mode -> close
                                                launcherPanel.close();
                                              } else {
                                                // In another mode -> switch to settings mode
                                                launcherPanel.setSearchText(">settings ");
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
    function set(value: string) {
      var val = parseFloat(value);
      if (isNaN(val))
        return;

      // Normalize logic: heuristic handling of 0-100 vs 0-1
      if (val > 1.0)
        val = val / 100.0;

      // Clamp
      val = Math.max(0.0, Math.min(1.0, val));

      BrightnessService.setBrightness(val);
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
        Settings.data.nightLight.forced = false;
      } else {
        if (Settings.data.nightLight.enabled) {
          Settings.data.nightLight.enabled = false;
        } else {
          Settings.data.nightLight.forced = true;
          Settings.data.nightLight.enabled = true;
        }
      }
    }
  }

  IpcHandler {
    target: "colorScheme"
    function set(schemeName: string) {
      ColorSchemeService.setPredefinedScheme(schemeName);
    }
    function setGenerationMethod(method: string) {
      var valid = false;
      for (var i = 0; i < TemplateProcessor.schemeTypes.length; i++) {
        if (TemplateProcessor.schemeTypes[i].key === method) {
          valid = true;
          break;
        }
      }

      if (valid) {
        Settings.data.colorSchemes.generationMethod = method;
      } else {
        Logger.w("IPC", "Invalid generation method received: " + method);
      }
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
                                              if (panel) {
                                                panel.openedViaKeybind = true;
                                                panel.toggle();
                                              }
                                            });
    }
    function openPanel() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var panel = PanelService.getPanel("audioPanel", screen);
                                              if (panel) {
                                                panel.openedViaKeybind = true;
                                                panel.open();
                                              }
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
                                              if (sessionMenuPanel) {
                                                sessionMenuPanel.openedViaKeybind = true;
                                                sessionMenuPanel.toggle();
                                              }
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
                                              if (controlCenterPanel) {
                                                controlCenterPanel.openedViaKeybind = true;
                                                if (Settings.data.controlCenter.position === "close_to_bar_button") {
                                                  // Will attempt to open the panel next to the bar button if any.
                                                  controlCenterPanel.toggle(null, "ControlCenter");
                                                } else {
                                                  controlCenterPanel.toggle();
                                                }
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
                                                if (wallpaperPanel) {
                                                  wallpaperPanel.openedViaKeybind = true;
                                                  wallpaperPanel.toggle();
                                                }
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
      Settings.data.wallpaper.automationEnabled = !Settings.data.wallpaper.automationEnabled;
    }
    function disableAutomation() {
      Settings.data.wallpaper.automationEnabled = false;
    }
    function enableAutomation() {
      Settings.data.wallpaper.automationEnabled = true;
    }
  }

  IpcHandler {
    target: "wifi"
    function toggle() {
      NetworkService.setWifiEnabled(!Settings.data.network.wifiEnabled);
    }
    function enable() {
      NetworkService.setWifiEnabled(true);
    }
    function disable() {
      NetworkService.setWifiEnabled(false);
    }
  }

  IpcHandler {
    target: "network"
    function togglePanel() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var networkPanel = PanelService.getPanel("networkPanel", screen);
                                              if (networkPanel) {
                                                networkPanel.openedViaKeybind = true;
                                                networkPanel.toggle(null, "WiFi");
                                              }
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
                                              if (bluetoothPanel) {
                                                bluetoothPanel.openedViaKeybind = true;
                                                bluetoothPanel.toggle(null, "Bluetooth");
                                              }
                                            });
    }
  }

  IpcHandler {
    target: "battery"
    function togglePanel() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var batteryPanel = PanelService.getPanel("batteryPanel", screen);
                                              if (batteryPanel) {
                                                batteryPanel.openedViaKeybind = true;
                                                batteryPanel.toggle(null, "Battery");
                                              }
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

    function toggle() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var panel = PanelService.getPanel("mediaPlayerPanel", screen);
                                              if (panel) {
                                                panel.openedViaKeybind = true;
                                                panel.toggle(null, "MediaMini");
                                              }
                                            });
    }

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

  IpcHandler {
    target: "systemMonitor"
    function toggle() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var panel = PanelService.getPanel("systemStatsPanel", screen);
                                              if (panel) {
                                                panel.openedViaKeybind = true;
                                                panel.toggle(null, "SystemMonitor");
                                              }
                                            });
    }
  }

  IpcHandler {
    target: "plugin"
    function openSettings(key: string) {
      var manifest = PluginRegistry.getPluginManifest(key);
      if (!manifest) {
        Logger.w("IPC", "Plugin not found:", key);
        return;
      }
      if (!manifest.entryPoints?.settings) {
        Logger.w("IPC", "Plugin has no settings entry point:", key);
        return;
      }
      root.screenDetector.withCurrentScreen(screen => {
                                              BarService.openPluginSettings(screen, manifest);
                                            });
    }

    function openPanel(key: string) {
      var manifest = PluginRegistry.getPluginManifest(key);
      if (!manifest) {
        Logger.w("IPC", "Plugin not found:", key);
        return;
      }
      if (!manifest.entryPoints?.panel) {
        Logger.w("IPC", "Plugin has no panel entry point:", key);
        return;
      }
      root.screenDetector.withCurrentScreen(screen => {
                                              PluginService.openPluginPanel(key, screen, null);
                                            });
    }

    function closePanel(key: string) {
      var manifest = PluginRegistry.getPluginManifest(key);
      if (!manifest) {
        Logger.w("IPC", "Plugin not found:", key);
        return;
      }
      if (!manifest.entryPoints?.panel) {
        Logger.w("IPC", "Plugin has no panel entry point:", key);
        return;
      }
      root.screenDetector.withCurrentScreen(screen => {
                                              var api = PluginService.getPluginAPI(key);
                                              if (api) {
                                                api.closePanel(screen);
                                              }
                                            });
    }

    function togglePanel(key: string) {
      var manifest = PluginRegistry.getPluginManifest(key);
      if (!manifest) {
        Logger.w("IPC", "Plugin not found:", key);
        return;
      }
      if (!manifest.entryPoints?.panel) {
        Logger.w("IPC", "Plugin has no panel entry point:", key);
        return;
      }
      root.screenDetector.withCurrentScreen(screen => {
                                              PluginService.togglePluginPanel(key, screen, null);
                                            });
    }
  }
}
