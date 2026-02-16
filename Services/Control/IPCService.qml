pragma Singleton

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

Singleton {
  id: root

  // Screen detector, set via init()
  property var screenDetector: null

  function init(detector) {
    root.screenDetector = detector;
    Logger.i("IPCService", "Service started");
  }

  IpcHandler {
    target: "bar"
    function toggle() {
      BarService.toggleVisibility();
    }
    function hideBar() {
      BarService.hide();
    }
    function showBar() {
      BarService.show();
    }
    function setDisplayMode(mode: string) {
      if (mode === "always_visible" || mode === "non_exclusive" || mode === "auto_hide") {
        Settings.data.bar.displayMode = mode;
      }
    }
    function setPosition(position: string, screen: string) {
      var valid = position === "top" || position === "bottom" || position === "left" || position === "right";
      if (!valid) {
        Logger.w("IPC", "Invalid bar position: " + position + ". Valid: top, bottom, left, right");
        return;
      }
      if (!screen || screen === "all") {
        Settings.data.bar.position = position;
      } else {
        Settings.setScreenOverride(screen, "position", position);
      }
    }
  }

  // Settings IPC helpers (outside IpcHandler to avoid QVariant IPC warnings)
  readonly property var _settingsTabMap: ({
                                            "about": SettingsPanel.Tab.About,
                                            "audio": SettingsPanel.Tab.Audio,
                                            "bar": SettingsPanel.Tab.Bar,
                                            "colorscheme": SettingsPanel.Tab.ColorScheme,
                                            "lockscreen": SettingsPanel.Tab.LockScreen,
                                            "controlcenter": SettingsPanel.Tab.ControlCenter,
                                            "desktopwidgets": SettingsPanel.Tab.DesktopWidgets,
                                            "osd": SettingsPanel.Tab.OSD,
                                            "display": SettingsPanel.Tab.Display,
                                            "dock": SettingsPanel.Tab.Dock,
                                            "general": SettingsPanel.Tab.General,
                                            "hooks": SettingsPanel.Tab.Hooks,
                                            "launcher": SettingsPanel.Tab.Launcher,
                                            "location": SettingsPanel.Tab.Location,
                                            "connections": SettingsPanel.Tab.Connections,
                                            "notifications": SettingsPanel.Tab.Notifications,
                                            "plugins": SettingsPanel.Tab.Plugins,
                                            "sessionmenu": SettingsPanel.Tab.SessionMenu,
                                            "systemmonitor": SettingsPanel.Tab.SystemMonitor,
                                            "userinterface": SettingsPanel.Tab.UserInterface,
                                            "wallpaper": SettingsPanel.Tab.Wallpaper
                                          })

  function _parseSettingsTabArg(tabArg) {
    var parts = tabArg.split("/");
    var tabId = _resolveSettingsTab(parts[0]);
    var subTabId = parts.length > 1 ? parseInt(parts[1]) : -1;
    return {
      "tab": tabId,
      "subTab": isNaN(subTabId) ? -1 : subTabId
    };
  }

  function _resolveSettingsTab(tabName) {
    if (!tabName)
      return SettingsPanel.Tab.General;
    var key = tabName.toLowerCase().replace(/[-_]/g, "");
    if (key in _settingsTabMap)
      return _settingsTabMap[key];
    Logger.w("IPC", "Unknown settings tab: " + tabName);
    return SettingsPanel.Tab.General;
  }

  function _settingsToggle(tabId, subTabId) {
    root.screenDetector.withCurrentScreen(screen => {
                                            SettingsPanelService.toggle(tabId, subTabId, screen);
                                          });
  }

  function _settingsOpen(tabId, subTabId) {
    root.screenDetector.withCurrentScreen(screen => {
                                            SettingsPanelService.openToTab(tabId, subTabId, screen);
                                          });
  }

  IpcHandler {
    target: "settings"

    function toggle() {
      root._settingsToggle(SettingsPanel.Tab.General, -1);
    }

    function toggleTab(tab: string) {
      var parsed = root._parseSettingsTabArg(tab);
      root._settingsToggle(parsed.tab, parsed.subTab);
    }

    function open() {
      root._settingsOpen(SettingsPanel.Tab.General, -1);
    }

    function openTab(tab: string) {
      var parsed = root._parseSettingsTabArg(tab);
      root._settingsOpen(parsed.tab, parsed.subTab);
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
                                              var searchText = PanelService.getLauncherSearchText(screen);
                                              var isInAppMode = !searchText.startsWith(">");
                                              if (!PanelService.isLauncherOpen(screen)) {
                                                // Closed -> open in app mode
                                                PanelService.openLauncherWithSearch(screen, "");
                                              } else if (isInAppMode) {
                                                // Already in app mode -> close
                                                PanelService.closeLauncher(screen);
                                              } else {
                                                // In another mode -> switch to app mode
                                                PanelService.setLauncherSearchText(screen, "");
                                              }
                                            }, Settings.data.appLauncher.overviewLayer);
    }
    function clipboard() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var searchText = PanelService.getLauncherSearchText(screen);
                                              var isInClipMode = searchText.startsWith(">clip");
                                              if (!PanelService.isLauncherOpen(screen)) {
                                                // Closed -> open in clipboard mode
                                                PanelService.openLauncherWithSearch(screen, ">clip ");
                                              } else if (isInClipMode) {
                                                // Already in clipboard mode -> close
                                                PanelService.closeLauncher(screen);
                                              } else {
                                                // In another mode -> switch to clipboard mode
                                                PanelService.setLauncherSearchText(screen, ">clip ");
                                              }
                                            }, Settings.data.appLauncher.overviewLayer);
    }
    function command() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var searchText = PanelService.getLauncherSearchText(screen);
                                              var isInCmdMode = searchText.startsWith(">cmd");
                                              if (!PanelService.isLauncherOpen(screen)) {
                                                PanelService.openLauncherWithSearch(screen, ">cmd ");
                                              } else if (isInCmdMode) {
                                                PanelService.closeLauncher(screen);
                                              } else {
                                                PanelService.setLauncherSearchText(screen, ">cmd ");
                                              }
                                            }, Settings.data.appLauncher.overviewLayer);
    }
    function emoji() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var searchText = PanelService.getLauncherSearchText(screen);
                                              var isInEmojiMode = searchText.startsWith(">emoji");
                                              if (!PanelService.isLauncherOpen(screen)) {
                                                // Closed -> open in emoji mode
                                                PanelService.openLauncherWithSearch(screen, ">emoji ");
                                              } else if (isInEmojiMode) {
                                                // Already in emoji mode -> close
                                                PanelService.closeLauncher(screen);
                                              } else {
                                                // In another mode -> switch to emoji mode
                                                PanelService.setLauncherSearchText(screen, ">emoji ");
                                              }
                                            }, Settings.data.appLauncher.overviewLayer);
    }
    function windows() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var searchText = PanelService.getLauncherSearchText(screen);
                                              var isInWindowsMode = searchText.startsWith(">win");
                                              if (!PanelService.isLauncherOpen(screen)) {
                                                PanelService.openLauncherWithSearch(screen, ">win ");
                                              } else if (isInWindowsMode) {
                                                PanelService.closeLauncher(screen);
                                              } else {
                                                PanelService.setLauncherSearchText(screen, ">win ");
                                              }
                                            }, Settings.data.appLauncher.overviewLayer);
    }
    function settings() {
      root.screenDetector.withCurrentScreen(screen => {
                                              var searchText = PanelService.getLauncherSearchText(screen);
                                              var isInSettingsMode = searchText.startsWith(">settings");
                                              if (!PanelService.isLauncherOpen(screen)) {
                                                PanelService.openLauncherWithSearch(screen, ">settings ");
                                              } else if (isInSettingsMode) {
                                                PanelService.closeLauncher(screen);
                                              } else {
                                                PanelService.setLauncherSearchText(screen, ">settings ");
                                              }
                                            }, Settings.data.appLauncher.overviewLayer);
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
                                              panel?.toggle(null, "MediaMini");
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
                                              panel?.toggle(null, "SystemMonitor");
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
