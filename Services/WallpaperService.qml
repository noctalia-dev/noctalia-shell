pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  readonly property ListModel fillModeModel: ListModel {}

  // All available wallpaper transitions
  readonly property ListModel transitionsModel: ListModel {}

  // All transition keys but filter out "none" and "random" so we are left with the real transitions
  readonly property var allTransitions: Array.from({
                                                     "length": transitionsModel.count
                                                   }, (_, i) => transitionsModel.get(i).key).filter(key => key !== "random" && key != "none")

  property var wallpaperLists: ({})
  property int scanningCount: 0
  readonly property bool scanning: (scanningCount > 0)

  // Cache for current wallpapers - can be updated directly since we use signals for notifications
  property var currentWallpapers: ({})

  property bool isInitialized: false

  // Signals for reactive UI updates
  signal wallpaperChanged(string screenName, string path)
  // Emitted when a wallpaper changes
  signal wallpaperDirectoryChanged(string screenName, string directory)
  // Emitted when a monitor's directory changes
  signal wallpaperListChanged(string screenName, int count)

  // Emitted when available wallpapers list changes
  Connections {
    target: Settings.data.wallpaper
    function onDirectoryChanged() {
      root.refreshWallpapersList()
      // Emit directory change signals for monitors using the default directory
      if (!Settings.data.wallpaper.enableMultiMonitorDirectories) {
        // All monitors use the main directory
        for (var i = 0; i < Quickshell.screens.length; i++) {
          root.wallpaperDirectoryChanged(Quickshell.screens[i].name, Settings.data.wallpaper.directory)
        }
      } else {
        // Only monitors without custom directories are affected
        for (var i = 0; i < Quickshell.screens.length; i++) {
          var screenName = Quickshell.screens[i].name
          var monitor = root.getMonitorConfig(screenName)
          if (!monitor || !monitor.directory) {
            root.wallpaperDirectoryChanged(screenName, Settings.data.wallpaper.directory)
          }
        }
      }
    }
    function onEnableMultiMonitorDirectoriesChanged() {
      root.refreshWallpapersList()
      // Notify all monitors about potential directory changes
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name
        root.wallpaperDirectoryChanged(screenName, root.getMonitorDirectory(screenName))
      }
    }
    function onRandomEnabledChanged() {
      root.toggleRandomWallpaper()
    }
    function onRandomIntervalSecChanged() {
      root.restartRandomWallpaperTimer()
    }
  }

  // -------------------------------------------------
  function init() {
    Logger.log("Wallpaper", "Service started")

    translateModels()

    // Rebuild cache from settings
    currentWallpapers = ({})
    var monitors = Settings.data.wallpaper.monitors || []
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].name && monitors[i].wallpaper) {
        currentWallpapers[monitors[i].name] = monitors[i].wallpaper
      }
    }

    isInitialized = true
  }

  // -------------------------------------------------
  function translateModels() {
    // Wait for i18n to be ready by retrying every time
    if (!I18n.isLoaded) {
      Qt.callLater(translateModels)
      return
    }

    // Populate fillModeModel with translated names
    fillModeModel.append({
                           "key": "center",
                           "name": I18n.tr("wallpaper.fill-modes.center"),
                           "uniform": 0.0
                         })
    fillModeModel.append({
                           "key": "crop",
                           "name": I18n.tr("wallpaper.fill-modes.crop"),
                           "uniform": 1.0
                         })
    fillModeModel.append({
                           "key": "fit",
                           "name": I18n.tr("wallpaper.fill-modes.fit"),
                           "uniform": 2.0
                         })
    fillModeModel.append({
                           "key": "stretch",
                           "name": I18n.tr("wallpaper.fill-modes.stretch"),
                           "uniform": 3.0
                         })

    // Populate transitionsModel with translated names
    transitionsModel.append({
                              "key": "none",
                              "name": I18n.tr("wallpaper.transitions.none")
                            })
    transitionsModel.append({
                              "key": "random",
                              "name": I18n.tr("wallpaper.transitions.random")
                            })
    transitionsModel.append({
                              "key": "fade",
                              "name": I18n.tr("wallpaper.transitions.fade")
                            })
    transitionsModel.append({
                              "key": "disc",
                              "name": I18n.tr("wallpaper.transitions.disc")
                            })
    transitionsModel.append({
                              "key": "stripes",
                              "name": I18n.tr("wallpaper.transitions.stripes")
                            })
    transitionsModel.append({
                              "key": "wipe",
                              "name": I18n.tr("wallpaper.transitions.wipe")
                            })
  }

  // -------------------------------------------------------------------
  function getFillModeUniform() {
    for (var i = 0; i < fillModeModel.count; i++) {
      const mode = fillModeModel.get(i)
      if (mode.key === Settings.data.wallpaper.fillMode) {
        return mode.uniform
      }
    }
    // Fallback to crop
    return 1.0
  }

  // -------------------------------------------------------------------
  // Get specific monitor wallpaper data
  function getMonitorConfig(screenName) {
    var monitors = Settings.data.wallpaper.monitors
    if (monitors !== undefined) {
      for (var i = 0; i < monitors.length; i++) {
        if (monitors[i].name !== undefined && monitors[i].name === screenName) {
          return monitors[i]
        }
      }
    }
  }

  // -------------------------------------------------------------------
  // Get specific monitor directory
  function getMonitorDirectory(screenName) {
    if (!Settings.data.wallpaper.enableMultiMonitorDirectories) {
      return Settings.data.wallpaper.directory
    }

    var monitor = getMonitorConfig(screenName)
    if (monitor !== undefined && monitor.directory !== undefined) {
      return monitor.directory
    }

    // Fall back to the main/single directory
    return Settings.data.wallpaper.directory
  }

  // -------------------------------------------------------------------
  // Set specific monitor directory
  function setMonitorDirectory(screenName, directory) {
    var monitors = Settings.data.wallpaper.monitors || []
    var found = false

    // Create a new array with updated values
    var newMonitors = monitors.map(function (monitor) {
      if (monitor.name === screenName) {
        found = true
        return {
          "name": screenName,
          "directory": directory,
          "wallpaper": monitor.wallpaper || ""
        }
      }
      return monitor
    })

    if (!found) {
      newMonitors.push({
                         "name": screenName,
                         "directory": directory,
                         "wallpaper": ""
                       })
    }

    // Update Settings with new array to ensure proper persistence
    Settings.data.wallpaper.monitors = newMonitors.slice()
    root.wallpaperDirectoryChanged(screenName, directory)
  }

  // -------------------------------------------------------------------
  // Get specific monitor wallpaper - now from cache
  function getWallpaper(screenName) {
    return currentWallpapers[screenName] || Settings.data.wallpaper.defaultWallpaper
  }

  // -------------------------------------------------------------------
  function changeWallpaper(path, screenName) {
    if (screenName !== undefined) {
      _setWallpaper(screenName, path)
    } else {
      // If no screenName specified change for all screens
      for (var i = 0; i < Quickshell.screens.length; i++) {
        _setWallpaper(Quickshell.screens[i].name, path)
      }
    }
  }

  // -------------------------------------------------------------------
  function _setWallpaper(screenName, path) {
    if (path === "" || path === undefined) {
      return
    }

    if (screenName === undefined) {
      Logger.warn("Wallpaper", "setWallpaper", "no screen specified")
      return
    }

    //Logger.log("Wallpaper", "setWallpaper on", screenName, ": ", path)

    // Check if wallpaper actually changed
    var oldPath = currentWallpapers[screenName] || ""
    var wallpaperChanged = (oldPath !== path)

    if (!wallpaperChanged) {
      // No change needed
      return
    }

    // Update cache directly
    currentWallpapers[screenName] = path

    // Update Settings - still need immutable update for Settings persistence
    // The slice() ensures Settings detects the change and saves properly
    var monitors = Settings.data.wallpaper.monitors || []
    var found = false

    var newMonitors = monitors.map(function (monitor) {
      if (monitor.name === screenName) {
        found = true
        return {
          "name": screenName,
          "directory": monitor.directory || getMonitorDirectory(screenName),
          "wallpaper": path
        }
      }
      return monitor
    })

    if (!found) {
      newMonitors.push({
                         "name": screenName,
                         "directory": getMonitorDirectory(screenName),
                         "wallpaper": path
                       })
    }

    Settings.data.wallpaper.monitors = newMonitors.slice()

    // Emit signal for this specific wallpaper change
    root.wallpaperChanged(screenName, path)

    // Restart the random wallpaper timer
    if (randomWallpaperTimer.running) {
      randomWallpaperTimer.restart()
    }
  }

  // -------------------------------------------------------------------
  function setRandomWallpaper() {
    Logger.log("Wallpaper", "setRandomWallpaper")

    if (Settings.data.wallpaper.enableMultiMonitorDirectories) {
      // Pick a random wallpaper per screen
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name
        var wallpaperList = getWallpapersList(screenName)

        if (wallpaperList.length > 0) {
          var randomIndex = Math.floor(Math.random() * wallpaperList.length)
          var randomPath = wallpaperList[randomIndex]
          changeWallpaper(randomPath, screenName)
        }
      }
    } else {
      // Pick a random wallpaper common to all screens
      // We can use any screenName here, so we just pick the primary one.
      if (Quickshell.screens.length > 0) {
        var wallpaperList = getWallpapersList(Quickshell.screens[0].name)
        if (wallpaperList.length > 0) {
          var randomIndex = Math.floor(Math.random() * wallpaperList.length)
          var randomPath = wallpaperList[randomIndex]
          changeWallpaper(randomPath, undefined)
        }
      }
    }
  }

  // -------------------------------------------------------------------
  function toggleRandomWallpaper() {
    Logger.log("Wallpaper", "toggleRandomWallpaper")
    if (Settings.data.wallpaper.randomEnabled) {
      restartRandomWallpaperTimer()
      setRandomWallpaper()
    }
  }

  // -------------------------------------------------------------------
  function restartRandomWallpaperTimer() {
    if (Settings.data.wallpaper.isRandom) {
      randomWallpaperTimer.restart()
    }
  }

  // -------------------------------------------------------------------
  function getWallpapersList(screenName) {
    if (screenName != undefined && wallpaperLists[screenName] != undefined) {
      return wallpaperLists[screenName]
    }
    return []
  }

  // -------------------------------------------------------------------
  function refreshWallpapersList() {
    Logger.log("Wallpaper", "refreshWallpapersList")
    scanningCount = 0

    // Force refresh by toggling the folder property on each FolderListModel
    for (var i = 0; i < wallpaperScanners.count; i++) {
      var scanner = wallpaperScanners.objectAt(i)
      if (scanner) {
        var currentFolder = scanner.folder
        scanner.folder = ""
        scanner.folder = currentFolder
      }
    }
  }

  // -------------------------------------------------------------------
  // -------------------------------------------------------------------
  // -------------------------------------------------------------------
  Timer {
    id: randomWallpaperTimer
    interval: Settings.data.wallpaper.randomIntervalSec * 1000
    running: Settings.data.wallpaper.randomEnabled
    repeat: true
    onTriggered: setRandomWallpaper()
    triggeredOnStart: false
  }

  // Instantiator (not Repeater) to create FolderListModel for each monitor
  Instantiator {
    id: wallpaperScanners
    model: Quickshell.screens
    delegate: FolderListModel {
      property string screenName: modelData.name
      property string currentDirectory: root.getMonitorDirectory(screenName)

      folder: "file://" + currentDirectory
      nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.pnm", "*.bmp"]
      showDirs: false
      sortField: FolderListModel.Name

      // Watch for directory changes via property binding
      onCurrentDirectoryChanged: {
        folder = "file://" + currentDirectory
      }

      Component.onCompleted: {
        // Connect to directory change signal
        root.wallpaperDirectoryChanged.connect(function (screen, directory) {
          if (screen === screenName) {
            currentDirectory = directory
          }
        })
      }

      onStatusChanged: {
        if (status === FolderListModel.Null) {
          // Flush the list
          root.wallpaperLists[screenName] = []
          root.wallpaperListChanged(screenName, 0)
        } else if (status === FolderListModel.Loading) {
          // Flush the list
          root.wallpaperLists[screenName] = []
          scanningCount++
        } else if (status === FolderListModel.Ready) {
          var files = []
          for (var i = 0; i < count; i++) {
            var directory = root.getMonitorDirectory(screenName)
            var filepath = directory + "/" + get(i, "fileName")
            files.push(filepath)
          }

          // Update the list
          root.wallpaperLists[screenName] = files

          scanningCount--
          Logger.log("Wallpaper", "List refreshed for", screenName, "count:", files.length)
          root.wallpaperListChanged(screenName, files.length)
        }
      }
    }
  }
}
