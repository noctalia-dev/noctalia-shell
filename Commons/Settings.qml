pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import "../Helpers/QtObj2JS.js" as QtObj2JS

Singleton {
  id: root

  // Used to access via Settings.data.xxx.yyy
  readonly property alias data: adapter
  property bool isLoaded: false
  property bool directoriesCreated: false
  property int settingsVersion: 16
  property bool isDebug: Quickshell.env("NOCTALIA_DEBUG") === "1"

  // Define our app directories
  // Default config directory: ~/.config/noctalia
  // Default cache directory: ~/.cache/noctalia
  property string shellName: "noctalia"
  property string configDir: Quickshell.env("NOCTALIA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/" + shellName + "/"
  property string cacheDir: Quickshell.env("NOCTALIA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/" + shellName + "/"
  property string cacheDirImages: cacheDir + "images/"
  property string cacheDirImagesWallpapers: cacheDir + "images/wallpapers/"
  property string cacheDirImagesNotifications: cacheDir + "images/notifications/"
  property string settingsFile: Quickshell.env("NOCTALIA_SETTINGS_FILE") || (configDir + "settings.json")

  property string defaultLocation: "Tokyo"
  property string defaultAvatar: Quickshell.env("HOME") + "/.face"
  property string defaultVideosDirectory: Quickshell.env("HOME") + "/Videos"
  property string defaultWallpapersDirectory: Quickshell.env("HOME") + "/Pictures/Wallpapers"

  // Signal emitted when settings are loaded after startupcale changes
  signal settingsLoaded
  signal settingsSaved

  // -----------------------------------------------------
  // -----------------------------------------------------
  // Ensure directories exist before FileView tries to read files
  Component.onCompleted: {
    // ensure settings dir exists
    Quickshell.execDetached(["mkdir", "-p", configDir])
    Quickshell.execDetached(["mkdir", "-p", cacheDir])

    Quickshell.execDetached(["mkdir", "-p", cacheDirImagesWallpapers])
    Quickshell.execDetached(["mkdir", "-p", cacheDirImagesNotifications])

    // Mark directories as created and trigger file loading
    directoriesCreated = true

    // This should only be activated once when the settings structure has changed
    // Then it should be commented out again, regular users don't need to generate
    // default settings on every start
    // TODO: automate this someday!
    // generateDefaultSettings()

    // Patch-in the local default, resolved to user's home
    adapter.general.avatarImage = defaultAvatar
    adapter.screenRecorder.directory = defaultVideosDirectory
    adapter.wallpaper.directory = defaultWallpapersDirectory
    adapter.wallpaper.defaultWallpaper = Quickshell.shellDir + "/Assets/Wallpaper/noctalia.png"

    // Set the adapter to the settingsFileView to trigger the real settings load
    settingsFileView.adapter = adapter
  }

  // Don't write settings to disk immediately
  // This avoid excessive IO when a variable changes rapidly (ex: sliders)
  Timer {
    id: saveTimer
    running: false
    interval: 1000
    onTriggered: {
      root.saveImmediate()
    }
  }

  FileView {
    id: settingsFileView
    path: directoriesCreated ? settingsFile : undefined
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: saveTimer.start()

    // Trigger initial load when path changes from empty to actual path
    onPathChanged: {
      if (path !== undefined) {
        reload()
      }
    }
    onLoaded: function () {
      if (!isLoaded) {
        Logger.i("Settings", "Settings loaded")

        upgradeSettingsData()
        validateMonitorConfigurations()
        isLoaded = true

        // Emit the signal
        root.settingsLoaded()

        // Finally, update our local settings version
        adapter.settingsVersion = settingsVersion
      }
    }
    onLoadFailed: function (error) {
      if (error.toString().includes("No such file") || error === 2) {
        // File doesn't exist, create it with default values
        writeAdapter()
        // Also write to fallback if set
        if (Quickshell.env("NOCTALIA_SETTINGS_FALLBACK")) {
          settingsFallbackFileView.writeAdapter()
        }
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
  JsonAdapter {
    id: adapter

    property int settingsVersion: root.settingsVersion
    property bool setupCompleted: false

    // bar
    property JsonObject bar: JsonObject {
      property string position: "top" // "top", "bottom", "left", or "right"
      property real backgroundOpacity: 1.0
      property list<string> monitors: []
      property string density: "default" // "compact", "default", "comfortable"
      property bool showCapsule: true

      // Floating bar settings
      property bool floating: false
      property real marginVertical: 0.25
      property real marginHorizontal: 0.25

      // Widget configuration for modular bar system
      property JsonObject widgets
      widgets: JsonObject {
        property list<var> left: [{
            "id": "SystemMonitor"
          }, {
            "id": "ActiveWindow"
          }, {
            "id": "MediaMini"
          }]
        property list<var> center: [{
            "id": "Workspace"
          }]
        property list<var> right: [{
            "id": "ScreenRecorder"
          }, {
            "id": "Tray"
          }, {
            "id": "NotificationHistory"
          }, {
            "id": "Battery"
          }, {
            "id": "Volume"
          }, {
            "id": "Brightness"
          }, {
            "id": "Clock"
          }, {
            "id": "ControlCenter"
          }]
      }
    }

    // general
    property JsonObject general: JsonObject {
      property string avatarImage: ""
      property bool dimDesktop: true
      property bool showScreenCorners: false
      property bool forceBlackScreenCorners: false
      property real scaleRatio: 1.0
      property real radiusRatio: 1.0
      property real screenRadiusRatio: 1.0
      property real animationSpeed: 1.0
      property bool animationDisabled: false
      property bool compactLockScreen: false
      property bool lockOnSuspend: true
      property string language: ""
    }

    // location
    property JsonObject location: JsonObject {
      property string name: defaultLocation
      property bool weatherEnabled: true
      property bool useFahrenheit: false
      property bool use12hourFormat: false
      property bool showWeekNumberInCalendar: false
      property bool showCalendarEvents: true
      property bool analogClockInCalendar: false
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
      property string audioSource: "default_output"
      property string videoSource: "portal"
    }

    // wallpaper
    property JsonObject wallpaper: JsonObject {
      property bool enabled: true
      property string directory: ""
      property bool enableMultiMonitorDirectories: false
      property bool recursiveSearch: false
      property bool setWallpaperOnAllMonitors: true
      property string defaultWallpaper: ""
      property string fillMode: "crop"
      property color fillColor: "#000000"
      property bool randomEnabled: false
      property int randomIntervalSec: 300 // 5 min
      property int transitionDuration: 1500 // 1500 ms
      property string transitionType: "random"
      property real transitionEdgeSmoothness: 0.05
      property list<var> monitors: []
    }

    // applauncher
    property JsonObject appLauncher: JsonObject {
      property bool enableClipboardHistory: false
      // Position: center, top_left, top_right, bottom_left, bottom_right, bottom_center, top_center
      property string position: "center"
      property real backgroundOpacity: 1.0
      property list<string> pinnedExecs: []
      property bool useApp2Unit: false
      property bool sortByMostUsed: true
      property string terminalCommand: "xterm -e"
      property bool customLaunchPrefixEnabled: false
      property string customLaunchPrefix: ""
    }

    // control center
    property JsonObject controlCenter: JsonObject {
      // Position: close_to_bar_button, center, top_left, top_right, bottom_left, bottom_right, bottom_center, top_center
      property string position: "close_to_bar_button"
      property JsonObject shortcuts
      shortcuts: JsonObject {
        property list<var> left: [{
            "id": "WiFi"
          }, {
            "id": "Bluetooth"
          }, {
            "id": "ScreenRecorder"
          }, {
            "id": "WallpaperSelector"
          }]
        property list<var> right: [{
            "id": "Notifications"
          }, {
            "id": "PowerProfile"
          }, {
            "id": "KeepAwake"
          }, {
            "id": "NightLight"
          }]
      }
      property list<var> cards: [{
          "id": "profile-card",
          "enabled": true
        }, {
          "id": "shortcuts-card",
          "enabled": true
        }, {
          "id": "audio-card",
          "enabled": true
        }, {
          "id": "weather-card",
          "enabled": true
        }, {
          "id": "media-sysmon-card",
          "enabled": true
        }]
    }

    // dock
    property JsonObject dock: JsonObject {
      property string displayMode: "always_visible" // "always_visible", "auto_hide", "exclusive"
      property real backgroundOpacity: 1.0
      property real floatingRatio: 1.0
      property real size: 1
      property bool onlySameOutput: true
      property list<string> monitors: []
      // Desktop entry IDs pinned to the dock (e.g., "org.kde.konsole", "firefox.desktop")
      property list<string> pinnedApps: []
      property bool colorizeIcons: false
    }

    // network
    property JsonObject network: JsonObject {
      property bool wifiEnabled: true
    }

    // notifications
    property JsonObject notifications: JsonObject {
      property bool doNotDisturb: false
      property list<string> monitors: []
      property string location: "top_right"
      property bool overlayLayer: true
      property real backgroundOpacity: 1.0
      property bool respectExpireTimeout: false
      property int lowUrgencyDuration: 3
      property int normalUrgencyDuration: 8
      property int criticalUrgencyDuration: 15
    }

    // on-screen display
    property JsonObject osd: JsonObject {
      property bool enabled: true
      property string location: "top_right"
      property list<string> monitors: []
      property int autoHideMs: 2000
      property bool overlayLayer: true
    }

    // audio
    property JsonObject audio: JsonObject {
      property int volumeStep: 5
      property bool volumeOverdrive: false
      property int cavaFrameRate: 60
      property string visualizerType: "linear"
      property list<string> mprisBlacklist: []
      property string preferredPlayer: ""
    }

    // ui
    property JsonObject ui: JsonObject {
      property string fontDefault: "Roboto"
      property string fontFixed: "DejaVu Sans Mono"
      property real fontDefaultScale: 1.0
      property real fontFixedScale: 1.0
      property bool tooltipsEnabled: true
      property bool panelsOverlayLayer: true
    }

    // brightness
    property JsonObject brightness: JsonObject {
      property int brightnessStep: 5
      property bool enforceMinimum: true
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
      property bool kitty: false
      property bool ghostty: false
      property bool foot: false
      property bool fuzzel: false
      property bool discord: false
      property bool discord_vesktop: false
      property bool discord_webcord: false
      property bool discord_armcord: false
      property bool discord_equibop: false
      property bool discord_lightcord: false
      property bool discord_dorion: false
      property bool pywalfox: false
      property bool vicinae: false
      property bool walker: false
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
    }

    // battery
    property JsonObject battery: JsonObject {
      property int chargingMode: 0
    }
  }

  // -----------------------------------------------------
  // Function to preprocess paths by expanding "~" to user's home directory
  function preprocessPath(path) {
    if (typeof path !== "string" || path === "") {
      return path
    }

    // Expand "~" to user's home directory
    if (path.startsWith("~/")) {
      return Quickshell.env("HOME") + path.substring(1)
    } else if (path === "~") {
      return Quickshell.env("HOME")
    }

    return path
  }

  // -----------------------------------------------------
  // Public function to trigger immediate settings saving
  function saveImmediate() {
    settingsFileView.writeAdapter()
    // Write to fallback location if set
    if (Quickshell.env("NOCTALIA_SETTINGS_FALLBACK")) {
      settingsFallbackFileView.writeAdapter()
    }
    root.settingsSaved() // Emit signal after saving
  }

  // -----------------------------------------------------
  // Generate default settings at the root of the repo
  function generateDefaultSettings() {
    try {
      Logger.d("Settings", "Generating settings-default.json")

      // Prepare a clean JSON
      var plainAdapter = QtObj2JS.qtObjectToPlainObject(adapter)
      var jsonData = JSON.stringify(plainAdapter, null, 2)

      var defaultPath = Quickshell.shellDir + "/Assets/settings-default.json"

      // Encode transfer it has base64 to avoid any escaping issue
      var base64Data = Qt.btoa(jsonData)
      Quickshell.execDetached(["sh", "-c", `echo "${base64Data}" | base64 -d > "${defaultPath}"`])
    } catch (error) {
      Logger.e("Settings", "Failed to generate default settings file: " + error)
    }
  }

  // -----------------------------------------------------
  // Function to validate monitor configurations
  function validateMonitorConfigurations() {
    var availableScreenNames = []
    for (var i = 0; i < Quickshell.screens.length; i++) {
      availableScreenNames.push(Quickshell.screens[i].name)
    }

    Logger.d("Settings", "Available monitors: [" + availableScreenNames.join(", ") + "]")
    Logger.d("Settings", "Configured bar monitors: [" + adapter.bar.monitors.join(", ") + "]")

    // Check bar monitors
    if (adapter.bar.monitors.length > 0) {
      var hasValidBarMonitor = false
      for (var j = 0; j < adapter.bar.monitors.length; j++) {
        if (availableScreenNames.includes(adapter.bar.monitors[j])) {
          hasValidBarMonitor = true
          break
        }
      }
      if (!hasValidBarMonitor) {
        Logger.w("Settings", "No configured bar monitors found on system, clearing bar monitor list to show on all screens")
        adapter.bar.monitors = []
      } else {

        //Logger.i("Settings", "Found valid bar monitors, keeping configuration")
      }
    } else {

      //Logger.i("Settings", "Bar monitor list is empty, will show on all available screens")
    }
  }

  // -----------------------------------------------------
  // If the settings structure has changed, ensure
  // backward compatibility by upgrading the settings
  function upgradeSettingsData() {
    // Wait for BarWidgetRegistry to be ready
    if (!BarWidgetRegistry.widgets || Object.keys(BarWidgetRegistry.widgets).length === 0) {
      Logger.w("Settings", "BarWidgetRegistry not ready, deferring upgrade")
      Qt.callLater(upgradeSettingsData)
      return
    }

    const sections = ["left", "center", "right"]

    // -----------------
    // 1st. convert old widget id to new id
    for (var s = 0; s < sections.length; s++) {
      const sectionName = sections[s]
      for (var i = 0; i < adapter.bar.widgets[sectionName].length; i++) {
        var widget = adapter.bar.widgets[sectionName][i]

        switch (widget.id) {
        case "DarkModeToggle":
          widget.id = "DarkMode"
          break
        case "PowerToggle":
          widget.id = "SessionMenu"
          break
        case "ScreenRecorderIndicator":
          widget.id = "ScreenRecorder"
          break
        case "SidePanelToggle":
          widget.id = "ControlCenter"
          break
        }
      }
    }

    // -----------------
    // 2nd. remove any non existing widget type
    var removedWidget = false
    for (var s = 0; s < sections.length; s++) {
      const sectionName = sections[s]
      const widgets = adapter.bar.widgets[sectionName]
      // Iterate backward through the widgets array, so it does not break when removing a widget
      for (var i = widgets.length - 1; i >= 0; i--) {
        var widget = widgets[i]
        if (!BarWidgetRegistry.hasWidget(widget.id)) {
          Logger.w(`Settings`, `Deleted invalid widget ${widget.id}`)
          widgets.splice(i, 1)
          removedWidget = true
        }
      }
    }

    // -----------------
    // 3nd. upgrade widget settings
    for (var s = 0; s < sections.length; s++) {
      const sectionName = sections[s]
      for (var i = 0; i < adapter.bar.widgets[sectionName].length; i++) {
        var widget = adapter.bar.widgets[sectionName][i]

        // Check if widget registry supports user settings, if it does not, then there is nothing to do
        const reg = BarWidgetRegistry.widgetMetadata[widget.id]
        if ((reg === undefined) || (reg.allowUserSettings === undefined) || !reg.allowUserSettings) {
          continue
        }

        if (upgradeWidget(widget)) {
          Logger.d("Settings", `Upgraded ${widget.id} widget:`, JSON.stringify(widget))
        }
      }
    }

    // -----------------
    // 4th. safety check
    // if a widget was deleted, ensure we still have a control center
    if (removedWidget) {
      var gotControlCenter = false
      for (var s = 0; s < sections.length; s++) {
        const sectionName = sections[s]
        for (var i = 0; i < adapter.bar.widgets[sectionName].length; i++) {
          var widget = adapter.bar.widgets[sectionName][i]
          if (widget.id === "ControlCenter") {
            gotControlCenter = true
            break
          }
        }
      }

      if (!gotControlCenter) {
        //const obj = JSON.parse('{"id": "ControlCenter"}');
        adapter.bar.widgets["right"].push(({
                                             "id": "ControlCenter"
                                           }))
        Logger.w("Settings", "Added a ControlCenter widget to the right section")
      }
    }
  }

  // -----------------------------------------------------
  function upgradeWidget(widget) {
    // Backup the widget definition before altering
    const widgetBefore = JSON.stringify(widget)

    // Get all existing custom settings keys
    const keys = Object.keys(BarWidgetRegistry.widgetMetadata[widget.id])

    // Delete deprecated user settings from the wiget
    for (const k of Object.keys(widget)) {
      if (k === "id" || k === "allowUserSettings") {
        continue
      }
      if (!keys.includes(k)) {
        delete widget[k]
      }
    }

    // Inject missing default setting (metaData) from BarWidgetRegistry
    for (var i = 0; i < keys.length; i++) {
      const k = keys[i]
      if (k === "id" || k === "allowUserSettings") {
        continue
      }

      if (widget[k] === undefined) {
        widget[k] = BarWidgetRegistry.widgetMetadata[widget.id][k]
      }
    }

    // Compare settings, to detect if something has been upgraded
    const widgetAfter = JSON.stringify(widget)
    return (widgetAfter !== widgetBefore)
  }
}
