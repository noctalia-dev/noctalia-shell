import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
pragma Singleton

Singleton {
  id: root

  // Define our app directories
  // Default config directory: ~/.config/noctalia
  // Default cache directory: ~/.cache/noctalia
  property string shellName: "noctalia"
  property string configDir: Quickshell.env("NOCTALIA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME")
                                                                       || Quickshell.env(
                                                                         "HOME") + "/.config") + "/" + shellName + "/"
  property string cacheDir: Quickshell.env("NOCTALIA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env(
                                                                       "HOME") + "/.cache") + "/" + shellName + "/"
  property string cacheDirImages: cacheDir + "images/"

  property string settingsFile: Quickshell.env("NOCTALIA_SETTINGS_FILE") || (configDir + "settings.json")

  property string defaultWallpaper: Qt.resolvedUrl("../Assets/Tests/wallpaper.png")
  property string defaultAvatar: Quickshell.env("HOME") + "/.face"

  // Used to access via Settings.data.xxx.yyy
  property alias data: adapter

  // Flag to prevent unnecessary wallpaper calls during reloads
  property bool isInitialLoad: true

  // Needed to only have one NPanel loaded at a time. <--- VERY BROKEN
  //property var openPanel: null
  Item {
    Component.onCompleted: {

      // ensure settings dir exists
      Quickshell.execDetached(["mkdir", "-p", configDir])
      Quickshell.execDetached(["mkdir", "-p", cacheDir])
      Quickshell.execDetached(["mkdir", "-p", cacheDirImages])
    }
  }

  FileView {
    path: settingsFile
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    Component.onCompleted: function () {
      reload()
    }
    onLoaded: function () {
      Logger.log("Settings", "OnLoaded")
      Qt.callLater(function () {
        // Only set wallpaper on initial load, not on reloads
        if (isInitialLoad && adapter.wallpaper.current !== "") {
          Logger.log("Settings", "Set current wallpaper", adapter.wallpaper.current)
          WallpaperService.setCurrentWallpaper(adapter.wallpaper.current, true)
        }
        isInitialLoad = false
      })
    }
    onLoadFailed: function (error) {
      if (error.toString().includes("No such file") || error === 2)
        // File doesn't exist, create it with default values
        writeAdapter()
    }

    JsonAdapter {
      id: adapter

      // bar
      property JsonObject bar

      bar: JsonObject {
        property bool showActiveWindow: true
        property bool showSystemInfo: false
        property bool showMedia: false
        property bool showBrightness: true
        property bool showNotificationsHistory: true
        property bool showTray: true
        property list<string> monitors: []
      }

      // general
      property JsonObject general

      general: JsonObject {
        property string avatarImage: defaultAvatar
        property bool dimDesktop: true
        property bool showScreenCorners: false
        property real radiusRatio: 1.0
      }

      // location
      property JsonObject location

      location: JsonObject {
        property string name: "Tokyo"
        property bool autoLocation: false
        property bool useFahrenheit: false
        property bool reverseDayMonth: false
        property bool use12HourClock: false
        property bool showDateWithClock: false
      }

      // screen recorder
      property JsonObject screenRecorder

      screenRecorder: JsonObject {
        property string directory: "~/Videos"
        property int frameRate: 60
        property string audioCodec: "opus"
        property string videoCodec: "h264"
        property string quality: "very_high"
        property string colorRange: "limited"
        property bool showCursor: true
        property string audioSource: "default_output"
      }

      // wallpaper
      property JsonObject wallpaper

      wallpaper: JsonObject {
        property string directory: "/usr/share/wallpapers"
        property string current: ""
        property bool isRandom: false
        property int randomInterval: 300
        property JsonObject swww

        onDirectoryChanged: WallpaperService.listWallpapers()
        onIsRandomChanged: WallpaperService.toggleRandomWallpaper()
        onRandomIntervalChanged: WallpaperService.restartRandomWallpaperTimer()

        swww: JsonObject {
          property bool enabled: false
          property string resizeMethod: "crop"
          property int transitionFps: 60
          property string transitionType: "random"
          property real transitionDuration: 1.1
        }
      }

      // applauncher
      property JsonObject appLauncher

      appLauncher: JsonObject {
        property list<string> pinnedExecs: []
      }

      // dock
      property JsonObject dock

      dock: JsonObject {
        property bool autoHide: false
        property bool exclusive: false
        property list<string> monitors: []
      }

      // network
      property JsonObject network

      network: JsonObject {
        property bool wifiEnabled: true
        property bool bluetoothEnabled: true
      }

      // notifications
      property JsonObject notifications

      notifications: JsonObject {
        property list<string> monitors: []
      }

      // audio
      property JsonObject audio

      audio: JsonObject {
        property string visualizerType: "linear"
      }

      // ui
      property JsonObject ui

      ui: JsonObject {
        property string fontFamily: "Roboto" // Family for all text
        property list<string> monitorsScale: []
      }

      // brightness
      property JsonObject brightness

      brightness: JsonObject {
        property int brightnessStep: 5
      }

      property JsonObject colorSchemes

      colorSchemes: JsonObject {
        property bool useWallpaperColors: false
        property string predefinedScheme: ""
        property bool darkMode: true
      }
    }
  }
}
