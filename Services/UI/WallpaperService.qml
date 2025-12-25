pragma Singleton
import Qt.labs.folderlistmodel

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  readonly property ListModel fillModeModel: ListModel {}
  readonly property string defaultDirectory: Settings.preprocessPath(Settings.data.wallpaper.directory)

  // All available wallpaper transitions
  readonly property ListModel transitionsModel: ListModel {}

  // All transition keys but filter out "none" and "random" so we are left with the real transitions
  readonly property var allTransitions: Array.from({
                                                     "length": transitionsModel.count
                                                   }, (_, i) => transitionsModel.get(i).key).filter(key => key !== "random" && key != "none")

  property var wallpaperLists: ({})
  property int scanningCount: 0

  // Cache for current wallpapers - can be updated directly since we use signals for notifications
  property var currentWallpapers: ({})

  property bool isInitialized: false
  property string wallpaperCacheFile: ""

  readonly property bool scanning: (scanningCount > 0)
  readonly property string noctaliaDefaultWallpaper: Quickshell.shellDir + "/Assets/Wallpaper/noctalia.png"
  property string defaultWallpaper: noctaliaDefaultWallpaper

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
      root.refreshWallpapersList();
      // Emit directory change signals for monitors using the default directory
      if (!Settings.data.wallpaper.enableMultiMonitorDirectories) {
        // All monitors use the main directory
        for (var i = 0; i < Quickshell.screens.length; i++) {
          root.wallpaperDirectoryChanged(Quickshell.screens[i].name, root.defaultDirectory);
        }
      } else {
        // Only monitors without custom directories are affected
        for (var i = 0; i < Quickshell.screens.length; i++) {
          var screenName = Quickshell.screens[i].name;
          var monitor = root.getMonitorConfig(screenName);
          if (!monitor || !monitor.directory) {
            root.wallpaperDirectoryChanged(screenName, root.defaultDirectory);
          }
        }
      }
    }
    function onEnableMultiMonitorDirectoriesChanged() {
      root.refreshWallpapersList();
      // Notify all monitors about potential directory changes
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name;
        root.wallpaperDirectoryChanged(screenName, root.getMonitorDirectory(screenName));
      }
    }
    function onRandomEnabledChanged() {
      root.toggleRandomWallpaper();
    }
    function onRandomIntervalSecChanged() {
      root.restartRandomWallpaperTimer();
    }
    function onRecursiveSearchChanged() {
      root.refreshWallpapersList();
    }
  }

  // -------------------------------------------------
  function init() {
    Logger.i("Wallpaper", "Service started");

    translateModels();

    // Initialize cache file path
    Qt.callLater(() => {
                   if (typeof Settings !== 'undefined' && Settings.cacheDir) {
                     wallpaperCacheFile = Settings.cacheDir + "wallpapers.json";
                     wallpaperCacheView.path = wallpaperCacheFile;
                   }
                 });

    // Note: isInitialized will be set to true in wallpaperCacheView.onLoaded
    Logger.d("Wallpaper", "Triggering initial wallpaper scan");
    Qt.callLater(refreshWallpapersList);
  }

  // -------------------------------------------------
  function translateModels() {
    // Wait for i18n to be ready by retrying every time
    if (!I18n.isLoaded) {
      Qt.callLater(translateModels);
      return;
    }

    // Populate fillModeModel with translated names
    fillModeModel.append({
                           "key": "center",
                           "name": I18n.tr("wallpaper.fill-modes.center"),
                           "uniform": 0.0
                         });
    fillModeModel.append({
                           "key": "crop",
                           "name": I18n.tr("wallpaper.fill-modes.crop"),
                           "uniform": 1.0
                         });
    fillModeModel.append({
                           "key": "fit",
                           "name": I18n.tr("wallpaper.fill-modes.fit"),
                           "uniform": 2.0
                         });
    fillModeModel.append({
                           "key": "stretch",
                           "name": I18n.tr("wallpaper.fill-modes.stretch"),
                           "uniform": 3.0
                         });

    // Populate transitionsModel with translated names
    transitionsModel.append({
                              "key": "none",
                              "name": I18n.tr("wallpaper.transitions.none")
                            });
    transitionsModel.append({
                              "key": "random",
                              "name": I18n.tr("wallpaper.transitions.random")
                            });
    transitionsModel.append({
                              "key": "fade",
                              "name": I18n.tr("wallpaper.transitions.fade")
                            });
    transitionsModel.append({
                              "key": "disc",
                              "name": I18n.tr("wallpaper.transitions.disc")
                            });
    transitionsModel.append({
                              "key": "stripes",
                              "name": I18n.tr("wallpaper.transitions.stripes")
                            });
    transitionsModel.append({
                              "key": "wipe",
                              "name": I18n.tr("wallpaper.transitions.wipe")
                            });
  }

  // -------------------------------------------------------------------
  function getFillModeUniform() {
    for (var i = 0; i < fillModeModel.count; i++) {
      const mode = fillModeModel.get(i);
      if (mode.key === Settings.data.wallpaper.fillMode) {
        return mode.uniform;
      }
    }
    // Fallback to crop
    return 1.0;
  }

  // -------------------------------------------------------------------
  // Get specific monitor wallpaper data
  function getMonitorConfig(screenName) {
    var monitors = Settings.data.wallpaper.monitorDirectories;
    if (monitors !== undefined) {
      for (var i = 0; i < monitors.length; i++) {
        if (monitors[i].name !== undefined && monitors[i].name === screenName) {
          return monitors[i];
        }
      }
    }
  }

  // -------------------------------------------------------------------
  // Get specific monitor directory
  function getMonitorDirectory(screenName) {
    if (!Settings.data.wallpaper.enableMultiMonitorDirectories) {
      return root.defaultDirectory;
    }

    var monitor = getMonitorConfig(screenName);
    if (monitor !== undefined && monitor.directory !== undefined) {
      return Settings.preprocessPath(monitor.directory);
    }

    // Fall back to the main/single directory
    return root.defaultDirectory;
  }

  // -------------------------------------------------------------------
  // Set specific monitor directory
  function setMonitorDirectory(screenName, directory) {
    var monitors = Settings.data.wallpaper.monitorDirectories || [];
    var found = false;

    // Create a new array with updated values
    var newMonitors = monitors.map(function (monitor) {
      if (monitor.name === screenName) {
        found = true;
        return {
          "name": screenName,
          "directory": directory,
          "wallpaper": monitor.wallpaper || ""
        };
      }
      return monitor;
    });

    if (!found) {
      newMonitors.push({
                         "name": screenName,
                         "directory": directory,
                         "wallpaper": ""
                       });
    }

    // Update Settings with new array to ensure proper persistence
    Settings.data.wallpaper.monitorDirectories = newMonitors.slice();
    root.wallpaperDirectoryChanged(screenName, Settings.preprocessPath(directory));
  }

  // -------------------------------------------------------------------
  // Get specific monitor wallpaper - now from cache
  function getWallpaper(screenName) {
    return currentWallpapers[screenName] || root.defaultWallpaper;
  }

  // -------------------------------------------------------------------
  function changeWallpaper(path, screenName) {
    if (screenName !== undefined) {
      _setWallpaper(screenName, path);
    } else {
      // If no screenName specified change for all screens
      for (var i = 0; i < Quickshell.screens.length; i++) {
        _setWallpaper(Quickshell.screens[i].name, path);
      }
    }
  }

  // -------------------------------------------------------------------
  function _setWallpaper(screenName, path) {
    if (path === "" || path === undefined) {
      return;
    }

    if (screenName === undefined) {
      Logger.w("Wallpaper", "setWallpaper", "no screen specified");
      return;
    }

    //Logger.i("Wallpaper", "setWallpaper on", screenName, ": ", path)

    // Check if wallpaper actually changed
    var oldPath = currentWallpapers[screenName] || "";
    var wallpaperChanged = (oldPath !== path);

    if (!wallpaperChanged) {
      // No change needed
      return;
    }

    // Update cache directly
    currentWallpapers[screenName] = path;

    // Save to cache file with debounce
    saveTimer.restart();

    // Emit signal for this specific wallpaper change
    root.wallpaperChanged(screenName, path);

    // Restart the random wallpaper timer
    if (randomWallpaperTimer.running) {
      randomWallpaperTimer.restart();
    }
  }

  // -------------------------------------------------------------------
  function setRandomWallpaper() {
    Logger.d("Wallpaper", "setRandomWallpaper");

    if (Settings.data.wallpaper.enableMultiMonitorDirectories) {
      // Pick a random wallpaper per screen
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name;
        var wallpaperList = getWallpapersList(screenName);

        if (wallpaperList.length > 0) {
          var randomIndex = Math.floor(Math.random() * wallpaperList.length);
          var randomPath = wallpaperList[randomIndex];
          changeWallpaper(randomPath, screenName);
        }
      }
    } else {
      // Pick a random wallpaper common to all screens
      // We can use any screenName here, so we just pick the primary one.
      var wallpaperList = getWallpapersList(Screen.name);
      if (wallpaperList.length > 0) {
        var randomIndex = Math.floor(Math.random() * wallpaperList.length);
        var randomPath = wallpaperList[randomIndex];
        changeWallpaper(randomPath, undefined);
      }
    }
  }

  // -------------------------------------------------------------------
  function toggleRandomWallpaper() {
    Logger.d("Wallpaper", "toggleRandomWallpaper");
    if (Settings.data.wallpaper.randomEnabled) {
      restartRandomWallpaperTimer();
      setRandomWallpaper();
    }
  }

  // -------------------------------------------------------------------
  function restartRandomWallpaperTimer() {
    if (Settings.data.wallpaper.isRandom) {
      randomWallpaperTimer.restart();
    }
  }

  // -------------------------------------------------------------------
  function getWallpapersList(screenName) {
    if (screenName != undefined && wallpaperLists[screenName] != undefined) {
      return wallpaperLists[screenName];
    }
    return [];
  }

  // -------------------------------------------------------------------
  function refreshWallpapersList() {
    Logger.d("Wallpaper", "refreshWallpapersList", "recursive:", Settings.data.wallpaper.recursiveSearch);
    scanningCount = 0;

    if (Settings.data.wallpaper.recursiveSearch) {
      // Use Process-based recursive search for all screens
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name;
        var directory = getMonitorDirectory(screenName);
        scanDirectoryRecursive(screenName, directory);
      }
    } else {
      // Use FolderListModel (non-recursive)
      // Force refresh by toggling each scanner's currentDirectory
      for (var i = 0; i < wallpaperScanners.count; i++) {
        var scanner = wallpaperScanners.objectAt(i);
        if (scanner) {
          // Capture scanner in closure
          (function (s) {
            var directory = root.getMonitorDirectory(s.screenName);
            // Trigger a change by setting to /tmp (always exists) then back to the actual directory
            // Note: This causes harmless Qt warnings (QTBUG-52262) but is necessary to force FolderListModel to re-scan
            s.currentDirectory = "/tmp";
            Qt.callLater(function () {
              s.currentDirectory = directory;
            });
          })(scanner);
        }
      }
    }
  }

  // Process instances for recursive scanning (one per screen)
  property var recursiveProcesses: ({})

  // -------------------------------------------------------------------
  function scanDirectoryRecursive(screenName, directory) {
    if (!directory || directory === "") {
      Logger.w("Wallpaper", "Empty directory for", screenName);
      wallpaperLists[screenName] = [];
      wallpaperListChanged(screenName, 0);
      return;
    }

    // Cancel any existing scan for this screen
    if (recursiveProcesses[screenName]) {
      Logger.d("Wallpaper", "Cancelling existing scan for", screenName);
      recursiveProcesses[screenName].running = false;
      recursiveProcesses[screenName].destroy();
      delete recursiveProcesses[screenName];
      scanningCount--;
    }

    scanningCount++;
    Logger.i("Wallpaper", "Starting recursive scan for", screenName, "in", directory);

    // Create Process component inline
    var processComponent = Qt.createComponent("", root);
    var processString = `
    import QtQuick
    import Quickshell.Io
    Process {
    id: process
    command: ["find", "-L", "` + directory + `", "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.gif", "-o", "-iname", "*.pnm", "-o", "-iname", "*.bmp", ")"]
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    }
    `;

    var processObject = Qt.createQmlObject(processString, root, "RecursiveScan_" + screenName);

    // Store reference to avoid garbage collection
    recursiveProcesses[screenName] = processObject;

    var handler = function (exitCode) {
      scanningCount--;
      Logger.d("Wallpaper", "Process exited with code", exitCode, "for", screenName);
      if (exitCode === 0) {
        var lines = processObject.stdout.text.split('\n');
        var files = [];
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim();
          if (line !== '') {
            files.push(line);
          }
        }
        // Sort files for consistent ordering
        files.sort();
        wallpaperLists[screenName] = files;
        Logger.i("Wallpaper", "Recursive scan completed for", screenName, "found", files.length, "files");
        wallpaperListChanged(screenName, files.length);
      } else {
        Logger.w("Wallpaper", "Recursive scan failed for", screenName, "exit code:", exitCode, "(directory might not exist)");
        wallpaperLists[screenName] = [];
        wallpaperListChanged(screenName, 0);
      }
      // Clean up
      delete recursiveProcesses[screenName];
      processObject.destroy();
    };

    processObject.exited.connect(handler);
    Logger.d("Wallpaper", "Starting process for", screenName);
    processObject.running = true;
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
      nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.pnm", "*.bmp", "*.webp"]
      showDirs: false
      sortField: FolderListModel.Name

      // Watch for directory changes via property binding
      onCurrentDirectoryChanged: {
        folder = "file://" + currentDirectory;
      }

      Component.onCompleted: {
        // Connect to directory change signal
        root.wallpaperDirectoryChanged.connect(function (screen, directory) {
          if (screen === screenName) {
            currentDirectory = directory;
          }
        });
      }

      onStatusChanged: {
        if (status === FolderListModel.Null) {
          // Flush the list
          root.wallpaperLists[screenName] = [];
          root.wallpaperListChanged(screenName, 0);
        } else if (status === FolderListModel.Loading) {
          // Flush the list
          root.wallpaperLists[screenName] = [];
          scanningCount++;
        } else if (status === FolderListModel.Ready) {
          var files = [];
          for (var i = 0; i < count; i++) {
            var directory = root.getMonitorDirectory(screenName);
            var filepath = directory + "/" + get(i, "fileName");
            files.push(filepath);
          }

          // Update the list
          root.wallpaperLists[screenName] = files;

          scanningCount--;
          Logger.d("Wallpaper", "List refreshed for", screenName, "count:", files.length);
          root.wallpaperListChanged(screenName, files.length);
        }
      }
    }
  }

  // -------------------------------------------------------------------
  // Cache file persistence
  // -------------------------------------------------------------------
  FileView {
    id: wallpaperCacheView
    printErrors: false
    watchChanges: false

    adapter: JsonAdapter {
      id: wallpaperCacheAdapter
      property var wallpapers: ({})
      property string defaultWallpaper: root.noctaliaDefaultWallpaper
    }

    onLoaded: {
      // Load wallpapers from cache file
      root.currentWallpapers = wallpaperCacheAdapter.wallpapers || {};

      // Load default wallpaper from cache if it exists, otherwise use Noctalia default
      if (wallpaperCacheAdapter.defaultWallpaper && wallpaperCacheAdapter.defaultWallpaper !== "") {
        root.defaultWallpaper = wallpaperCacheAdapter.defaultWallpaper;
        Logger.d("Wallpaper", "Loaded default wallpaper from cache:", wallpaperCacheAdapter.defaultWallpaper);
      } else {
        root.defaultWallpaper = root.noctaliaDefaultWallpaper;
        Logger.d("Wallpaper", "Using Noctalia default wallpaper");
      }

      Logger.d("Wallpaper", "Loaded wallpapers from cache file:", Object.keys(root.currentWallpapers).length, "screens");
      root.isInitialized = true;
    }

    onLoadFailed: error => {
      // File doesn't exist yet or failed to load - initialize with empty state
      root.currentWallpapers = {};
      Logger.d("Wallpaper", "Cache file doesn't exist or failed to load, starting with empty wallpapers");
      root.isInitialized = true;
    }
  }

  Timer {
    id: saveTimer
    interval: 500
    repeat: false
    onTriggered: {
      wallpaperCacheAdapter.wallpapers = root.currentWallpapers;
      wallpaperCacheAdapter.defaultWallpaper = root.defaultWallpaper;
      wallpaperCacheView.writeAdapter();
      Logger.d("Wallpaper", "Saved wallpapers to cache file");
    }
  }
}
