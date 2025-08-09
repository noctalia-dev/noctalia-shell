pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

Singleton {

    property string shellName: "Noctalia"
    property string settingsDir: Quickshell.env("NOCTALIA_SETTINGS_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/" + shellName + "/"
    property string settingsFile: Quickshell.env("NOCTALIA_SETTINGS_FILE") || (settingsDir + "Settings.json")
    property string themeFile: Quickshell.env("NOCTALIA_THEME_FILE") || (settingsDir + "Theme.json")
    property var settings: settingAdapter

    Item {
        Component.onCompleted: {
            // ensure settings dir
            Quickshell.execDetached(["mkdir", "-p", settingsDir]);
        }
    }

    FileView {
        id: settingFileView
        path: settingsFile
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        Component.onCompleted: function() {
            reload()
        }
        onLoaded: function() {
            Qt.callLater(function () {
                WallpaperManager.setCurrentWallpaper(settings.currentWallpaper, true);
                // One-time migration: normalize old configs where empty arrays meant "all".
                try {
                    if (settings.monitorListsNormalized !== true) {
                        if (!Array.isArray(settings.barMonitors) || settings.barMonitors.length === 0) {
                            settings.barMonitors = ["*"]
                        }
                        if (!Array.isArray(settings.dockMonitors) || settings.dockMonitors.length === 0) {
                            settings.dockMonitors = ["*"]
                        }
                        if (!Array.isArray(settings.notificationMonitors) || settings.notificationMonitors.length === 0) {
                            settings.notificationMonitors = ["*"]
                        }
                        settings.monitorListsNormalized = true
                    }
                } catch (e) {
                    console.warn("Failed to normalize monitor lists:", e)
                }
            })
        }
        onLoadFailed: function(error) {
            settingAdapter = {}
            writeAdapter()
        }
        JsonAdapter {
            id: settingAdapter
            // Marks that legacy monitor arrays have been normalized
            property bool monitorListsNormalized: false
            property string weatherCity: "Dinslaken"
            property string profileImage: Quickshell.env("HOME") + "/.face"
            property bool useFahrenheit: false
            property string wallpaperFolder: "/usr/share/wallpapers"
            property string currentWallpaper: ""
            property string videoPath: "~/Videos/"
            property bool showActiveWindow: true
            property bool showActiveWindowIcon: false
            property bool showSystemInfoInBar: false
            property bool showCorners: false
            property bool showTaskbar: true
            property bool showMediaInBar: false
            property bool useSWWW: false
            property bool randomWallpaper: false
            property bool useWallpaperTheme: false
            property int wallpaperInterval: 300
            property string wallpaperResize: "crop"
            property int transitionFps: 60
            property string transitionType: "random"
            property real transitionDuration: 1.1
            property string visualizerType: "radial"
            property bool reverseDayMonth: false
            property bool use12HourClock: false
            property bool dimPanels: true
            property real fontSizeMultiplier: 1.0  // Font size multiplier (1.0 = normal, 1.2 = 20% larger, 0.8 = 20% smaller)
            property int taskbarIconSize: 24  // Taskbar icon button size in pixels (default: 32, smaller: 24, larger: 40)
            property var pinnedExecs: [] // Added for AppLauncher pinned apps

            property bool showDock: true
            property bool dockExclusive: false
            property bool wifiEnabled: false
            property bool bluetoothEnabled: false
            property int recordingFrameRate: 60
            property string recordingQuality: "very_high"
            property string recordingCodec: "h264"
            property string audioCodec: "opus"
            property bool showCursor: true
            property string colorRange: "limited"
            
            // Monitor/Display Settings
            // Use ["*"] to represent "all monitors". Use [] to represent "none".
            property var barMonitors: ["*"]
            property var dockMonitors: ["*"]
            property var notificationMonitors: ["*"]
            property var monitorScaleOverrides: {} // Map of monitor name -> scale override (e.g., 0.8..2.0). When set, Theme.scale() returns this value
        }
    }

    Connections {
        target: settingAdapter
        function onRandomWallpaperChanged() { WallpaperManager.toggleRandomWallpaper() }
        function onWallpaperIntervalChanged() { WallpaperManager.restartRandomWallpaperTimer() }
        function onWallpaperFolderChanged() { WallpaperManager.loadWallpapers() }
        function onNotificationMonitorsChanged() { 
        }
    }
}