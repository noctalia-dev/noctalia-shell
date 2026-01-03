pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../Helpers/QtObj2JS.js" as QtObj2JS
import qs.Commons
import qs.Commons.Migrations
import qs.Modules.OSD
import qs.Services.Noctalia
import qs.Services.UI

Singleton {
  id: root

  property bool isLoaded: false
  property bool reloadSettings: false
  property bool directoriesCreated: false
  property bool shouldOpenSetupWizard: false
  property bool isFreshInstall: false

  /*
  Shell directories.
  - Default config directory: ~/.config/noctalia
  - Default cache directory: ~/.cache/noctalia
  */
  readonly property alias data: adapter  // Used to access via Settings.data.xxx.yyy
  readonly property int settingsVersion: 37
  readonly property bool isDebug: Quickshell.env("NOCTALIA_DEBUG") === "1"
  readonly property string shellName: "noctalia"
  readonly property string configDir: Quickshell.env("NOCTALIA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/" + shellName + "/"
  readonly property string cacheDir: Quickshell.env("NOCTALIA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/" + shellName + "/"
  readonly property string settingsFile: Quickshell.env("NOCTALIA_SETTINGS_FILE") || (configDir + "settings.json")
  readonly property string defaultLocation: "Tokyo"
  readonly property string defaultAvatar: Quickshell.env("HOME") + "/.face"
  readonly property string defaultVideosDirectory: Quickshell.env("HOME") + "/Videos"
  readonly property string defaultWallpapersDirectory: Quickshell.env("HOME") + "/Pictures/Wallpapers"

  // Signal emitted when settings are loaded after startupcale changes
  signal settingsLoaded
  signal settingsSaved

  // -----------------------------------------------------
  // -----------------------------------------------------
  // Ensure directories exist before FileView tries to read files
  Component.onCompleted: {
    // ensure settings dir exists
    Quickshell.execDetached(["mkdir", "-p", configDir]);
    Quickshell.execDetached(["mkdir", "-p", cacheDir]);

    // Ensure PAM config file exists in configDir (create once, never override)
    ensurePamConfig();

    // Mark directories as created and trigger file loading
    directoriesCreated = true;

    // This should only be activated once when the settings structure has changed
    // Then it should be commented out again, regular users don't need to generate
    // default settings on every start
    if (isDebug) {
      generateDefaultSettings();
      generateWidgetDefaultSettings();
    }

    // Patch-in the local default, resolved to user's home
    adapter.general.avatarImage = defaultAvatar;
    adapter.screenRecorder.directory = defaultVideosDirectory;
    adapter.wallpaper.directory = defaultWallpapersDirectory;
    adapter.ui.fontDefault = Qt.application.font.family;
    adapter.ui.fontFixed = "monospace";

    // Set the adapter to the settingsFileView to trigger the real settings load
    settingsFileView.adapter = adapter;
  }

  // Don't write settings to disk immediately
  // This avoid excessive IO when a variable changes rapidly (ex: sliders)
  Timer {
    id: saveTimer
    running: false
    interval: 500
    onTriggered: {
      root.saveImmediate();
    }
  }

  FileView {
    id: settingsFileView
    path: directoriesCreated ? settingsFile : undefined
    printErrors: false
    watchChanges: true
    onAdapterUpdated: saveTimer.start()

    onFileChanged: {
      reloadSettings = true;
      reload();
    }

    // Trigger initial load when path changes from empty to actual path
    onPathChanged: {
      if (path !== undefined) {
        reload();
      }
    }
    onLoaded: function () {
      if (!isLoaded) {
        Logger.i("Settings", "Settings loaded");

        // Load raw JSON for migrations (adapter doesn't expose removed properties)
        var rawJson = null;
        try {
          rawJson = JSON.parse(settingsFileView.text());
        } catch (e) {
          Logger.w("Settings", "Could not parse raw JSON for migrations");
        }

        // Run versioned migrations immediately, don't move it in upgradeSettings
        runVersionedMigrations(rawJson);

        // Finally, update our local settings version
        adapter.settingsVersion = settingsVersion;

        // Emit the signal
        root.isLoaded = true;
        root.settingsLoaded();

        upgradeSettings();
      }
    }
    onLoadFailed: function (error) {
      if (reloadSettings) {
        reloadSettings = false;
        return;
      }
      if (error.toString().includes("No such file") || error === 2) {
        // File doesn't exist, create it with default values
        root.isFreshInstall = true;
        writeAdapter();

        // Also write to fallback if set
        if (Quickshell.env("NOCTALIA_SETTINGS_FALLBACK")) {
          settingsFallbackFileView.writeAdapter();
        }

        // We started without settings, we should open the setupWizard
        root.shouldOpenSetupWizard = true;
      }
    }
  }

  // Fallback FileView for writing settings to alternate location
  FileView {
    id: settingsFallbackFileView
    path: Quickshell.env("NOCTALIA_SETTINGS_FALLBACK") || ""
    adapter: Quickshell.env("NOCTALIA_SETTINGS_FALLBACK") ? adapter : null
    printErrors: false
    watchChanges: false
  }

  // FileView to load default settings for comparison
  FileView {
    id: defaultSettingsFileView
    path: Quickshell.shellDir + "/Assets/settings-default.json"
    printErrors: false
    watchChanges: false
  }

  // Cached default settings object
  property var _defaultSettings: null

  // Load default settings when file is loaded
  Connections {
    target: defaultSettingsFileView
    function onLoaded() {
      try {
        root._defaultSettings = JSON.parse(defaultSettingsFileView.text());
      } catch (e) {
        Logger.w("Settings", "Failed to parse default settings file: " + e);
        root._defaultSettings = null;
      }
    }
  }

  JsonAdapter {
    id: adapter

    property int settingsVersion: 0

    // bar
    property JsonObject bar: JsonObject {
      property string position: "top" // "top", "bottom", "left", or "right"
      property list<string> monitors: [] // holds bar visibility per monitor
      property string density: "default" // "compact", "default", "comfortable"
      property bool showOutline: false
      property bool showCapsule: true
      property real capsuleOpacity: 1.0

      // Bar background opacity settings
      property real backgroundOpacity: 0.93
      property bool useSeparateOpacity: false

      // Floating bar settings
      property bool floating: false
      property real marginVertical: 0.25
      property real marginHorizontal: 0.25

      // Bar outer corners (inverted/concave corners at bar edges when not floating)
      property bool outerCorners: true

      // Reserves space with compositor
      property bool exclusive: true

      // Widget configuration for modular bar system
      property JsonObject widgets
      widgets: JsonObject {
        property list<var> left: [
          {
            "icon": "rocket",
            "id": "CustomButton",
            "leftClickExec": "qs -c noctalia-shell ipc call launcher toggle"
          },
          {
            "id": "Clock",
            "usePrimaryColor": false
          },
          {
            "id": "SystemMonitor"
          },
          {
            "id": "ActiveWindow"
          },
          {
            "id": "MediaMini"
          }
        ]
        property list<var> center: [
          {
            "id": "Workspace"
          }
        ]
        property list<var> right: [
          {
            "id": "ScreenRecorder"
          },
          {
            "id": "Tray"
          },
          {
            "id": "NotificationHistory"
          },
          {
            "id": "Battery"
          },
          {
            "id": "Volume"
          },
          {
            "id": "Brightness"
          },
          {
            "id": "ControlCenter"
          }
        ]
      }
    }

    // general
    property JsonObject general: JsonObject {
      property string avatarImage: ""
      property real dimmerOpacity: 0.2
      property bool showScreenCorners: false
      property bool forceBlackScreenCorners: false
      property real scaleRatio: 1.0
      property real radiusRatio: 1.0
      property real iRadiusRatio: 1.0
      property real boxRadiusRatio: 1.0
      property real screenRadiusRatio: 1.0
      property real animationSpeed: 1.0
      property bool animationDisabled: false
      property bool compactLockScreen: false
      property bool lockOnSuspend: true
      property bool showSessionButtonsOnLockScreen: true
      property bool showHibernateOnLockScreen: false
      property bool enableShadows: true
      property string shadowDirection: "bottom_right"
      property int shadowOffsetX: 2
      property int shadowOffsetY: 3
      property string language: ""
      property bool allowPanelsOnScreenWithoutBar: true
    }

    // ui
    property JsonObject ui: JsonObject {
      property string fontDefault: ""
      property string fontFixed: ""
      property real fontDefaultScale: 1.0
      property real fontFixedScale: 1.0
      property bool tooltipsEnabled: true
      property real panelBackgroundOpacity: 0.93
      property bool panelsAttachedToBar: true
      property string settingsPanelMode: "attached" // "centered", "attached", "window"
      property bool boxBorderEnabled: false
    }

    // location
    property JsonObject location: JsonObject {
      property string name: defaultLocation
      property bool weatherEnabled: true
      property bool weatherShowEffects: true
      property bool useFahrenheit: false
      property bool use12hourFormat: false
      property bool showWeekNumberInCalendar: false
      property bool showCalendarEvents: true
      property bool showCalendarWeather: true
      property bool analogClockInCalendar: false
      property int firstDayOfWeek: -1 // -1 = auto (use locale), 0 = Sunday, 1 = Monday, 6 = Saturday
    }

    // calendar
    property JsonObject calendar: JsonObject {
      property list<var> cards: [
        {
          "id": "calendar-header-card",
          "enabled": true
        },
        {
          "id": "calendar-month-card",
          "enabled": true
        },
        {
          "id": "timer-card",
          "enabled": true
        },
        {
          "id": "weather-card",
          "enabled": true
        }
      ]
    }

    // screen recorder
    property JsonObject screenRecorder: JsonObject {
      property string directory: ""
      property int frameRate: 60
      property string audioCodec: "opus"
      property string videoCodec: "h264"
      property string quality: "very_high"
      property string colorRange: "limited"
      property bool showCursor: true
      property bool copyToClipboard: false
      property string audioSource: "default_output"
      property string videoSource: "portal"
    }

    // wallpaper
    property JsonObject wallpaper: JsonObject {
      property bool enabled: true
      property bool overviewEnabled: false
      property string directory: ""
      property list<var> monitorDirectories: []
      property bool enableMultiMonitorDirectories: false
      property bool recursiveSearch: false
      property bool setWallpaperOnAllMonitors: true
      property string fillMode: "crop"
      property color fillColor: "#000000"
      property bool useSolidColor: false
      property color solidColor: "#1a1a2e"
      property bool randomEnabled: false // Deprecated: use wallpaperChangeMode instead
      property string wallpaperChangeMode: "random" // "random" or "alphabetical"
      property int randomIntervalSec: 300 // 5 min
      property int transitionDuration: 1500 // 1500 ms
      property string transitionType: "random"
      property real transitionEdgeSmoothness: 0.05
      property string panelPosition: "follow_bar"
      property bool hideWallpaperFilenames: false
      // Wallhaven settings
      property bool useWallhaven: false
      property string wallhavenQuery: ""
      property string wallhavenSorting: "relevance"
      property string wallhavenOrder: "desc"
      property string wallhavenCategories: "111" // general,anime,people
      property string wallhavenPurity: "100" // sfw only
      property string wallhavenRatios: ""
      property string wallhavenApiKey: ""
      property string wallhavenResolutionMode: "atleast" // "atleast" or "exact"
      property string wallhavenResolutionWidth: ""
      property string wallhavenResolutionHeight: ""
    }

    // applauncher
    property JsonObject appLauncher: JsonObject {
      property bool enableClipboardHistory: false
      property bool enableClipPreview: true
      // Position: center, top_left, top_right, bottom_left, bottom_right, bottom_center, top_center
      property string position: "center"
      property list<string> pinnedExecs: []
      property bool useApp2Unit: false
      property bool sortByMostUsed: true
      property string terminalCommand: "xterm -e"
      property bool customLaunchPrefixEnabled: false
      property string customLaunchPrefix: ""
      // View mode: "list" or "grid"
      property string viewMode: "list"
      property bool showCategories: true
      // Icon mode: "tabler" or "native"
      property string iconMode: "tabler"
      property bool ignoreMouseInput: false
      property string screenshotAnnotationTool: ""
    }

    // control center
    property JsonObject controlCenter: JsonObject {
      // Position: close_to_bar_button, center, top_left, top_right, bottom_left, bottom_right, bottom_center, top_center
      property string position: "close_to_bar_button"
      property string diskPath: "/"
      property JsonObject shortcuts
      shortcuts: JsonObject {
        property list<var> left: [
          {
            "id": "WiFi"
          },
          {
            "id": "Bluetooth"
          },
          {
            "id": "ScreenRecorder"
          },
          {
            "id": "WallpaperSelector"
          }
        ]
        property list<var> right: [
          {
            "id": "Notifications"
          },
          {
            "id": "PowerProfile"
          },
          {
            "id": "KeepAwake"
          },
          {
            "id": "NightLight"
          }
        ]
      }
      property list<var> cards: [
        {
          "id": "profile-card",
          "enabled": true
        },
        {
          "id": "shortcuts-card",
          "enabled": true
        },
        {
          "id": "audio-card",
          "enabled": true
        },
        {
          "id": "brightness-card",
          "enabled": false
        },
        {
          "id": "weather-card",
          "enabled": true
        },
        {
          "id": "media-sysmon-card",
          "enabled": true
        }
      ]
    }

    // system monitor
    property JsonObject systemMonitor: JsonObject {
      property int cpuWarningThreshold: 80
      property int cpuCriticalThreshold: 90
      property int tempWarningThreshold: 80
      property int tempCriticalThreshold: 90
      property int gpuWarningThreshold: 80
      property int gpuCriticalThreshold: 90
      property int memWarningThreshold: 80
      property int memCriticalThreshold: 90
      property int diskWarningThreshold: 80
      property int diskCriticalThreshold: 90
      property int cpuPollingInterval: 3000
      property int tempPollingInterval: 3000
      property int gpuPollingInterval: 3000
      property bool enableDgpuMonitoring: false // Opt-in: reading dGPU sysfs/nvidia-smi wakes it from D3cold, draining battery
      property int memPollingInterval: 3000
      property int diskPollingInterval: 3000
      property int networkPollingInterval: 3000
      property int loadAvgPollingInterval: 3000
      property bool useCustomColors: false
      property string warningColor: ""
      property string criticalColor: ""
      property string externalMonitor: "resources || missioncenter || jdsystemmonitor || corestats || system-monitoring-center || gnome-system-monitor || plasma-systemmonitor || mate-system-monitor || ukui-system-monitor || deepin-system-monitor || pantheon-system-monitor"
    }

    // dock
    property JsonObject dock: JsonObject {
      property bool enabled: true
      property string displayMode: "auto_hide" // "always_visible", "auto_hide", "exclusive"
      property real backgroundOpacity: 1.0
      property real floatingRatio: 1.0
      property real size: 1
      property bool onlySameOutput: true
      property list<string> monitors: [] // holds dock visibility per monitor
      property list<string> pinnedApps: [] // Desktop entry IDs pinned to the dock (e.g., "org.kde.konsole", "firefox.desktop")
      property bool colorizeIcons: false

      property bool pinnedStatic: false
      property bool inactiveIndicators: false
      property double deadOpacity: 0.6
      property real animationSpeed: 1.0 // Speed multiplier for hide/show animations (0.1 = slowest, 2.0 = fastest)
    }

    // network
    property JsonObject network: JsonObject {
      property bool wifiEnabled: true
      property bool bluetoothRssiPollingEnabled: false  // Opt-in Bluetooth RSSI polling (uses bluetoothctl)
      property int bluetoothRssiPollIntervalMs: 10000 // Polling interval in milliseconds for RSSI queries
      property string wifiDetailsViewMode: "grid"   // "grid" or "list"
      property string bluetoothDetailsViewMode: "grid" // "grid" or "list"
      property bool bluetoothHideUnnamedDevices: false
    }

    // session menu
    property JsonObject sessionMenu: JsonObject {
      property bool enableCountdown: true
      property int countdownDuration: 10000
      property string position: "center"
      property bool showHeader: true
      property bool largeButtonsStyle: false
      property string largeButtonsLayout: "grid"
      property bool showNumberLabels: true
      property list<var> powerOptions: [
        {
          "action": "lock",
          "enabled": true
        },
        {
          "action": "suspend",
          "enabled": true
        },
        {
          "action": "hibernate",
          "enabled": true
        },
        {
          "action": "reboot",
          "enabled": true
        },
        {
          "action": "logout",
          "enabled": true
        },
        {
          "action": "shutdown",
          "enabled": true
        }
      ]
    }

    // notifications
    property JsonObject notifications: JsonObject {
      property bool enabled: true
      property list<string> monitors: [] // holds notifications visibility per monitor
      property string location: "top_right"
      property bool overlayLayer: true
      property real backgroundOpacity: 1.0
      property bool respectExpireTimeout: false
      property int lowUrgencyDuration: 3
      property int normalUrgencyDuration: 8
      property int criticalUrgencyDuration: 15
      property bool enableKeyboardLayoutToast: true
      property JsonObject saveToHistory: JsonObject {
        property bool low: true
        property bool normal: true
        property bool critical: true
      }
      property JsonObject sounds: JsonObject {
        property bool enabled: false
        property real volume: 0.5
        property bool separateSounds: false
        property string criticalSoundFile: ""
        property string normalSoundFile: ""
        property string lowSoundFile: ""
        property string excludedApps: "discord,firefox,chrome,chromium,edge"
      }
    }

    // on-screen display
    property JsonObject osd: JsonObject {
      property bool enabled: true
      property string location: "top_right"
      property int autoHideMs: 2000
      property bool overlayLayer: true
      property real backgroundOpacity: 1.0
      property list<var> enabledTypes: [OSD.Type.Volume, OSD.Type.InputVolume, OSD.Type.Brightness, OSD.Type.CustomText]
      property list<string> monitors: [] // holds osd visibility per monitor
    }

    // audio
    property JsonObject audio: JsonObject {
      property int volumeStep: 5
      property bool volumeOverdrive: false
      property int cavaFrameRate: 30
      property string visualizerType: "linear"
      property list<string> mprisBlacklist: []
      property string preferredPlayer: ""
      property string externalMixer: "pwvucontrol || pavucontrol"
    }

    // brightness
    property JsonObject brightness: JsonObject {
      property int brightnessStep: 5
      property bool enforceMinimum: true
      property bool enableDdcSupport: false
    }

    property JsonObject colorSchemes: JsonObject {
      property bool useWallpaperColors: false
      property string predefinedScheme: "Noctalia (default)"
      property bool darkMode: true
      property string schedulingMode: "off"
      property string manualSunrise: "06:30"
      property string manualSunset: "18:30"
      property string matugenSchemeType: "scheme-fruit-salad"
      property bool generateTemplatesForPredefined: true
    }

    // templates toggles
    property JsonObject templates: JsonObject {
      property bool gtk: false
      property bool qt: false
      property bool kcolorscheme: false
      property bool alacritty: false
      property bool kitty: false
      property bool ghostty: false
      property bool foot: false
      property bool wezterm: false
      property bool fuzzel: false
      property bool discord: false
      property bool pywalfox: false
      property bool vicinae: false
      property bool walker: false
      property bool code: false
      property bool spicetify: false
      property bool telegram: false
      property bool cava: false
      property bool yazi: false
      property bool emacs: false
      property bool niri: false
      property bool hyprland: false
      property bool mango: false
      property bool zed: false
      property bool helix: false
      property bool enableUserTemplates: false
    }

    // night light
    property JsonObject nightLight: JsonObject {
      property bool enabled: false
      property bool forced: false
      property bool autoSchedule: true
      property string nightTemp: "4000"
      property string dayTemp: "6500"
      property string manualSunrise: "06:30"
      property string manualSunset: "18:30"
    }

    // hooks
    property JsonObject hooks: JsonObject {
      property bool enabled: false
      property string wallpaperChange: ""
      property string darkModeChange: ""
      property string screenLock: ""
      property string screenUnlock: ""
      property string performanceModeEnabled: ""
      property string performanceModeDisabled: ""
    }

    // desktop widgets
    property JsonObject desktopWidgets: JsonObject {
      property bool enabled: false
      property bool gridSnap: false
      property list<var> monitorWidgets: []
      // Format: [{ "name": "DP-1", "widgets": [...] }, { "name": "HDMI-1", "widgets": [...] }]
    }
  }

  // -----------------------------------------------------
  // Function to preprocess paths by expanding "~" to user's home directory
  function preprocessPath(path) {
    if (typeof path !== "string" || path === "") {
      return path;
    }

    // Expand "~" to user's home directory
    if (path.startsWith("~/")) {
      return Quickshell.env("HOME") + path.substring(1);
    } else if (path === "~") {
      return Quickshell.env("HOME");
    }

    return path;
  }

  // -----------------------------------------------------
  // Get default value for a setting path (e.g., "general.scaleRatio" or "bar.position")
  // Returns undefined if not found
  function getDefaultValue(path) {
    if (!root._defaultSettings) {
      return undefined;
    }

    var parts = path.split(".");
    var current = root._defaultSettings;

    for (var i = 0; i < parts.length; i++) {
      if (current === undefined || current === null) {
        return undefined;
      }
      current = current[parts[i]];
    }

    return current;
  }

  // -----------------------------------------------------
  // Compare current value with default value
  // Returns true if values differ, false if they match or default is not found
  function isValueChanged(path, currentValue) {
    var defaultValue = getDefaultValue(path);
    if (defaultValue === undefined) {
      return false; // Can't compare if default not found
    }

    // Deep comparison for objects and arrays
    if (typeof currentValue === "object" && typeof defaultValue === "object") {
      return JSON.stringify(currentValue) !== JSON.stringify(defaultValue);
    }

    // Simple comparison for primitives
    return currentValue !== defaultValue;
  }

  // -----------------------------------------------------
  // Format default value for tooltip display
  // Returns a human-readable string representation of the default value
  function formatDefaultValueForTooltip(path) {
    var defaultValue = getDefaultValue(path);
    if (defaultValue === undefined) {
      return "";
    }

    // Format based on type
    if (typeof defaultValue === "boolean") {
      return defaultValue ? "true" : "false";
    } else if (typeof defaultValue === "number") {
      return defaultValue.toString();
    } else if (typeof defaultValue === "string") {
      return defaultValue === "" ? "(empty)" : defaultValue;
    } else if (Array.isArray(defaultValue)) {
      return defaultValue.length === 0 ? "(empty)" : "[" + defaultValue.length + " items]";
    } else if (typeof defaultValue === "object") {
      return "(object)";
    }

    return String(defaultValue);
  }

  // -----------------------------------------------------
  // Public function to trigger immediate settings saving
  function saveImmediate() {
    settingsFileView.writeAdapter();
    // Write to fallback location if set
    if (Quickshell.env("NOCTALIA_SETTINGS_FALLBACK")) {
      settingsFallbackFileView.writeAdapter();
    }
    root.settingsSaved(); // Emit signal after saving
  }

  // -----------------------------------------------------
  // Generate default settings: for reference only, not used by the shell
  function generateDefaultSettings() {
    try {
      Logger.d("Settings", "Generating settings-default.json");

      // Prepare a clean JSON
      var plainAdapter = QtObj2JS.qtObjectToPlainObject(adapter);
      var jsonData = JSON.stringify(plainAdapter, null, 2);

      var defaultPath = Quickshell.shellDir + "/Assets/settings-default.json";

      // Encode transfer it has base64 to avoid any escaping issue
      var base64Data = Qt.btoa(jsonData);
      Quickshell.execDetached(["sh", "-c", `echo "${base64Data}" | base64 -d > "${defaultPath}"`]);
    } catch (error) {
      Logger.e("Settings", "Failed to generate default settings file: " + error);
    }
  }

  // -----------------------------------------------------
  // Generate default widget settings: for reference only, not used by the shell
  function generateWidgetDefaultSettings() {
    try {
      Logger.d("Settings", "Generating settings-widgets-default.json");

      var output = {
        "bar": QtObj2JS.qtObjectToPlainObject(BarWidgetRegistry.widgetMetadata),
        "controlCenter": QtObj2JS.qtObjectToPlainObject(ControlCenterWidgetRegistry.widgetMetadata),
        "desktop": QtObj2JS.qtObjectToPlainObject(DesktopWidgetRegistry.widgetMetadata)
      };
      var jsonData = JSON.stringify(output, null, 2);

      var defaultPath = Quickshell.shellDir + "/Assets/settings-widgets-default.json";

      var base64Data = Qt.btoa(jsonData);
      Quickshell.execDetached(["sh", "-c", `echo "${base64Data}" | base64 -d > "${defaultPath}"`]);
    } catch (error) {
      Logger.e("Settings", "Failed to generate widget default settings file: " + error);
    }
  }

  // -----------------------------------------------------
  // Run versioned migrations using MigrationRegistry
  // rawJson is the parsed JSON file content (before adapter filtering)
  function runVersionedMigrations(rawJson) {
    // Skip migrations on fresh installs (no prior settings file)
    if (!rawJson || root.isFreshInstall) {
      Logger.i("Settings", "Fresh install detected, skipping migrations");
      return;
    }

    const currentVersion = adapter.settingsVersion;
    const migrations = MigrationRegistry.migrations;

    Logger.i("Settings", "adapter.settingsVersion:", adapter.settingsVersion);

    // Get all migration versions and sort them
    const versions = Object.keys(migrations).map(v => parseInt(v)).sort((a, b) => a - b);

    // Run migrations in order for versions newer than current
    for (var i = 0; i < versions.length; i++) {
      const version = versions[i];

      if (currentVersion < version) {
        // Create migration instance and run it
        const migrationComponent = migrations[version];
        const migration = migrationComponent.createObject(root);

        if (migration && typeof migration.migrate === "function") {
          const success = migration.migrate(adapter, Logger, rawJson);
          if (!success) {
            Logger.e("Settings", "Migration to v" + version + " failed");
          }
        } else {
          Logger.e("Settings", "Invalid migration for v" + version);
        }

        // Clean up migration instance
        if (migration) {
          migration.destroy();
        }
      }
    }
  }

  // -----------------------------------------------------
  // If the settings structure has changed, ensure
  // backward compatibility by upgrading the settings
  function upgradeSettings() {
    // Wait for PluginService to finish loading plugins first
    // This prevents deleting plugin widgets during reload before plugins are registered
    if (!PluginService.initialized || !PluginService.pluginsFullyLoaded) {
      Logger.d("Settings", "Plugins not fully loaded yet, deferring upgrade");
      Qt.callLater(upgradeSettings);
      return;
    }

    // Wait for BarWidgetRegistry to be ready
    if (!BarWidgetRegistry.widgets || Object.keys(BarWidgetRegistry.widgets).length === 0) {
      Logger.d("Settings", "BarWidgetRegistry not ready, deferring upgrade");
      Qt.callLater(upgradeSettings);
      return;
    }

    // -----------------
    const sections = ["left", "center", "right"];

    // 1. remove any non existing widget type
    var removedWidget = false;
    for (var s = 0; s < sections.length; s++) {
      const sectionName = sections[s];
      const widgets = adapter.bar.widgets[sectionName];
      // Iterate backward through the widgets array, so it does not break when removing a widget
      for (var i = widgets.length - 1; i >= 0; i--) {
        var widget = widgets[i];
        if (!BarWidgetRegistry.hasWidget(widget.id)) {
          Logger.w(`Settings`, `!!! Deleted invalid widget ${widget.id} !!!`);
          widgets.splice(i, 1);
          removedWidget = true;
        }
      }
    }

    // -----------------
    // 2. upgrade user widget settings
    for (var s = 0; s < sections.length; s++) {
      const sectionName = sections[s];
      for (var i = 0; i < adapter.bar.widgets[sectionName].length; i++) {
        var widget = adapter.bar.widgets[sectionName][i];

        // Check if widget registry supports user settings, if it does not, then there is nothing to do
        if (BarWidgetRegistry.widgetMetadata[widget.id] === undefined) {
          continue;
        }

        if (upgradeWidget(widget)) {
          Logger.d("Settings", `Upgraded ${widget.id} widget:`, JSON.stringify(widget));
        }
      }
    }
  }

  // -----------------------------------------------------
  // Ensure PAM password.conf exists in configDir (create once, never override)
  function ensurePamConfig() {
    var pamConfigDir = configDir + "pam";
    var pamConfigFile = pamConfigDir + "/password.conf";

    // Check if file already exists
    fileCheckPamProcess.command = ["sh", "-c", `grep -q '^ID=nixos' /etc/os-release || test -f ${pamConfigFile}`];
    fileCheckPamProcess.running = true;
  }

  function doCreatePamConfig() {
    var pamConfigDir = configDir + "pam";
    var pamConfigFile = pamConfigDir + "/password.conf";
    var pamConfigDirEsc = pamConfigDir.replace(/'/g, "'\\''");
    var pamConfigFileEsc = pamConfigFile.replace(/'/g, "'\\''");

    // Ensure directory exists
    Quickshell.execDetached(["mkdir", "-p", pamConfigDir]);

    // Generate the PAM config file content
    var configContent = "#auth sufficient pam_fprintd.so max-tries=1\n";
    configContent += "# only uncomment this if you have a fingerprint reader\n";
    configContent += "auth required pam_unix.so\n";

    // Write the config file using heredoc to avoid escaping issues
    var script = `cat > '${pamConfigFileEsc}' << 'EOF'\n`;
    script += configContent;
    script += "EOF\n";
    Quickshell.execDetached(["sh", "-c", script]);

    Logger.d("Settings", "PAM config file created at:", pamConfigFile);
  }

  // Process for checking if PAM config file exists
  Process {
    id: fileCheckPamProcess
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        // File exists, skip creation
        Logger.d("Settings", "On NixOS or PAM config file already exists, skipping creation");
      } else {
        // File doesn't exist, create it
        doCreatePamConfig();
      }
    }
  }

  // -----------------------------------------------------
  // Function to clean up deprecated user/custom bar widgets settings
  function upgradeWidget(widget) {
    // Backup the widget definition before altering
    const widgetBefore = JSON.stringify(widget);

    // Get all existing custom settings keys
    const keys = Object.keys(BarWidgetRegistry.widgetMetadata[widget.id]);

    // Delete deprecated user settings from the wiget
    for (const k of Object.keys(widget)) {
      if (k === "id" || k === "allowUserSettings") {
        continue;
      }
      if (!keys.includes(k)) {
        delete widget[k];
      }
    }

    // Inject missing default setting (metaData) from BarWidgetRegistry
    for (var i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (k === "id" || k === "allowUserSettings") {
        continue;
      }

      if (widget[k] === undefined) {
        widget[k] = BarWidgetRegistry.widgetMetadata[widget.id][k];
      }
    }

    // Compare settings, to detect if something has been upgraded
    const widgetAfter = JSON.stringify(widget);
    return (widgetAfter !== widgetBefore);
  }
}
