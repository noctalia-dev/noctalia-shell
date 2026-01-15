pragma Singleton
import Qt.labs.folderlistmodel

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  readonly property ListModel fillModeModel: ListModel {}
  readonly property string defaultDirectory: Settings.preprocessPath(Settings.data.wallpaper.directory)
  readonly property string solidColorPrefix: "solid://"

  // All available wallpaper transitions
  readonly property ListModel transitionsModel: ListModel {}

  // All transition keys but filter out "none" and "random"
  readonly property var allTransitions: Array.from({
    "length": transitionsModel.count
  }, (_, i) => transitionsModel.get(i).key).filter(key => key !== "random" && key != "none")

  property var wallpaperLists: ({})
  property int scanningCount: 0

  // Cache for current wallpapers
  property var currentWallpapers: ({})

  // Track current alphabetical index for each screen
  property var alphabeticalIndices: ({})

  property bool isInitialized: false
  property string wallpaperCacheFile: ""

  readonly property bool scanning: (scanningCount > 0)
  readonly property string noctaliaDefaultWallpaper: Quickshell.shellDir + "/Assets/Wallpaper/noctalia.png"
  property string defaultWallpaper: noctaliaDefaultWallpaper

  // Signals for reactive UI updates
  signal wallpaperChanged(string screenName, string path)
  signal wallpaperDirectoryChanged(string screenName, string directory)
  signal wallpaperListChanged(string screenName, int count)

  // Emitted when available wallpapers list changes
  Connections {
    target: Settings.data.wallpaper
    function onDirectoryChanged() {
      root.refreshWallpapersList();
      if (!Settings.data.wallpaper.enableMultiMonitorDirectories) {
        for (var i = 0; i < Quickshell.screens.length; i++) {
          root.wallpaperDirectoryChanged(Quickshell.screens[i].name, root.defaultDirectory);
        }
      } else {
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
    function onWallpaperChangeModeChanged() {
      root.alphabeticalIndices = {};
      if (Settings.data.wallpaper.randomEnabled) {
        root.restartRandomWallpaperTimer();
        root.setNextWallpaper();
      }
    }
    function onRecursiveSearchChanged() {
      root.refreshWallpapersList();
    }
    function onUseSolidColorChanged() {
      if (Settings.data.wallpaper.useSolidColor) {
        var solidPath = root.createSolidColorPath(Settings.data.wallpaper.solidColor.toString());
        for (var i = 0; i < Quickshell.screens.length; i++) {
          root.wallpaperChanged(Quickshell.screens[i].name, solidPath);
        }
      } else {
        for (var i = 0; i < Quickshell.screens.length; i++) {
          var screenName = Quickshell.screens[i].name;
          root.wallpaperChanged(screenName, currentWallpapers[screenName] || root.defaultWallpaper);
        }
      }
    }
    function onSolidColorChanged() {
      if (Settings.data.wallpaper.useSolidColor) {
        var solidPath = root.createSolidColorPath(Settings.data.wallpaper.solidColor.toString());
        for (var i = 0; i < Quickshell.screens.length; i++) {
          root.wallpaperChanged(Quickshell.screens[i].name, solidPath);
        }
      }
    }
  }

  // -------------------------------------------------
  function init() {
    Logger.i("Wallpaper", "Service started");
    translateModels();

    Qt.callLater(() => {
      if (typeof Settings !== 'undefined' && Settings.cacheDir) {
        wallpaperCacheFile = Settings.cacheDir + "wallpapers.json";
        wallpaperCacheView.path = wallpaperCacheFile;
      }
    });
    Logger.d("Wallpaper", "Triggering initial wallpaper scan");
    Qt.callLater(refreshWallpapersList);

    // Attempt initial theme sync
    Qt.callLater(syncPlasmaTheme);
  }

  // -------------------------------------------------
  function translateModels() {
    if (!I18n.isLoaded) {
      Qt.callLater(translateModels);
      return;
    }
    fillModeModel.append({ "key": "center", "name": I18n.tr("positions.center"), "uniform": 0.0 });
    fillModeModel.append({ "key": "crop", "name": I18n.tr("wallpaper.fill-modes.crop"), "uniform": 1.0 });
    fillModeModel.append({ "key": "fit", "name": I18n.tr("wallpaper.fill-modes.fit"), "uniform": 2.0 });
    fillModeModel.append({ "key": "stretch", "name": I18n.tr("wallpaper.fill-modes.stretch"), "uniform": 3.0 });

    transitionsModel.append({ "key": "none", "name": I18n.tr("common.none") });
    transitionsModel.append({ "key": "random", "name": I18n.tr("common.random") });
    transitionsModel.append({ "key": "fade", "name": I18n.tr("wallpaper.transitions.fade") });
    transitionsModel.append({ "key": "disc", "name": I18n.tr("wallpaper.transitions.disc") });
    transitionsModel.append({ "key": "stripes", "name": I18n.tr("wallpaper.transitions.stripes") });
    transitionsModel.append({ "key": "wipe", "name": I18n.tr("wallpaper.transitions.wipe") });
  }

  function getFillModeUniform() {
    for (var i = 0; i < fillModeModel.count; i++) {
      const mode = fillModeModel.get(i);
      if (mode.key === Settings.data.wallpaper.fillMode) {
        return mode.uniform;
      }
    }
    return 1.0;
  }

  // -------------------------------------------------------------------
  // Solid color helpers
  function isSolidColorPath(path) {
    return path && typeof path === "string" && path.startsWith(solidColorPrefix);
  }

  function getSolidColor(path) {
    if (!isSolidColorPath(path)) {
      return null;
    }
    return path.substring(solidColorPrefix.length);
  }

  function createSolidColorPath(colorString) {
    return solidColorPrefix + colorString;
  }

  function setSolidColor(colorString) {
    Settings.data.wallpaper.solidColor = colorString;
    Settings.data.wallpaper.useSolidColor = true;
  }

  // -------------------------------------------------------------------
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

  function getMonitorDirectory(screenName) {
    if (!Settings.data.wallpaper.enableMultiMonitorDirectories) {
      return root.defaultDirectory;
    }
    var monitor = getMonitorConfig(screenName);
    if (monitor !== undefined && monitor.directory !== undefined) {
      return Settings.preprocessPath(monitor.directory);
    }
    return root.defaultDirectory;
  }

  function setMonitorDirectory(screenName, directory) {
    var monitors = Settings.data.wallpaper.monitorDirectories || [];
    var found = false;
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
    Settings.data.wallpaper.monitorDirectories = newMonitors.slice();
    root.wallpaperDirectoryChanged(screenName, Settings.preprocessPath(directory));
  }

  function getWallpaper(screenName) {
    if (Settings.data.wallpaper.useSolidColor) {
      return createSolidColorPath(Settings.data.wallpaper.solidColor.toString());
    }
    return currentWallpapers[screenName] || root.defaultWallpaper;
  }

  function changeWallpaper(path, screenName) {
    if (Settings.data.wallpaper.useSolidColor) {
      Settings.data.wallpaper.useSolidColor = false;
    }
    if (screenName !== undefined) {
      _setWallpaper(screenName, path);
    } else {
      var allScreenNames = new Set(Object.keys(currentWallpapers));
      for (var i = 0; i < Quickshell.screens.length; i++) {
        allScreenNames.add(Quickshell.screens[i].name);
      }
      allScreenNames.forEach(name => _setWallpaper(name, path));
    }
  }

  function _setWallpaper(screenName, path) {
    if (path === "" || path === undefined) return;
    if (screenName === undefined) {
      Logger.w("Wallpaper", "setWallpaper", "no screen specified");
      return;
    }

    var oldPath = currentWallpapers[screenName] || "";
    var wallpaperChanged = (oldPath !== path);

    if (!wallpaperChanged) return;

    currentWallpapers[screenName] = path;
    saveTimer.restart();
    root.wallpaperChanged(screenName, path);

    // Sync theme on wallpaper change
    root.syncPlasmaTheme();

    if (randomWallpaperTimer.running) {
      randomWallpaperTimer.restart();
    }
  }

  function setRandomWallpaper() {
    Logger.d("Wallpaper", "setRandomWallpaper");
    if (Settings.data.wallpaper.enableMultiMonitorDirectories) {
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
      var wallpaperList = getWallpapersList(Screen.name);
      if (wallpaperList.length > 0) {
        var randomIndex = Math.floor(Math.random() * wallpaperList.length);
        var randomPath = wallpaperList[randomIndex];
        changeWallpaper(randomPath, undefined);
      }
    }
  }

  function setAlphabeticalWallpaper() {
    Logger.d("Wallpaper", "setAlphabeticalWallpaper");
    if (Settings.data.wallpaper.enableMultiMonitorDirectories) {
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name;
        var wallpaperList = getWallpapersList(screenName);
        if (wallpaperList.length > 0) {
          if (alphabeticalIndices[screenName] === undefined) {
            var currentWallpaper = currentWallpapers[screenName] || "";
            var foundIndex = wallpaperList.indexOf(currentWallpaper);
            alphabeticalIndices[screenName] = (foundIndex >= 0) ? foundIndex : 0;
          }
          var currentIndex = alphabeticalIndices[screenName];
          var nextIndex = (currentIndex + 1) % wallpaperList.length;
          alphabeticalIndices[screenName] = nextIndex;
          var nextPath = wallpaperList[nextIndex];
          changeWallpaper(nextPath, screenName);
        }
      }
    } else {
      var wallpaperList = getWallpapersList(Screen.name);
      if (wallpaperList.length > 0) {
        var key = "all";
        if (alphabeticalIndices[key] === undefined) {
          var currentWallpaper = currentWallpapers[Screen.name] || "";
          var foundIndex = wallpaperList.indexOf(currentWallpaper);
          alphabeticalIndices[key] = (foundIndex >= 0) ? foundIndex : 0;
        }
        var currentIndex = alphabeticalIndices[key];
        var nextIndex = (currentIndex + 1) % wallpaperList.length;
        alphabeticalIndices[key] = nextIndex;
        var nextPath = wallpaperList[nextIndex];
        changeWallpaper(nextPath, undefined);
      }
    }
  }

  function toggleRandomWallpaper() {
    Logger.d("Wallpaper", "toggleRandomWallpaper");
    if (Settings.data.wallpaper.randomEnabled) {
      restartRandomWallpaperTimer();
      setNextWallpaper();
    }
  }

  function setNextWallpaper() {
    var mode = Settings.data.wallpaper.wallpaperChangeMode || "random";
    if (mode === "alphabetical") {
      setAlphabeticalWallpaper();
    } else {
      setRandomWallpaper();
    }
  }

  function restartRandomWallpaperTimer() {
    if (Settings.data.wallpaper.randomEnabled) {
      randomWallpaperTimer.restart();
    }
  }

  function getWallpapersList(screenName) {
    if (screenName != undefined && wallpaperLists[screenName] != undefined) {
      return wallpaperLists[screenName];
    }
    return [];
  }

  function refreshWallpapersList() {
    Logger.d("Wallpaper", "refreshWallpapersList", "recursive:", Settings.data.wallpaper.recursiveSearch);
    scanningCount = 0;
    if (Settings.data.wallpaper.recursiveSearch) {
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name;
        var directory = getMonitorDirectory(screenName);
        scanDirectoryRecursive(screenName, directory);
      }
    } else {
      for (var i = 0; i < wallpaperScanners.count; i++) {
        var scanner = wallpaperScanners.objectAt(i);
        if (scanner) {
          (function (s) {
            var directory = root.getMonitorDirectory(s.screenName);
            s.currentDirectory = "/tmp";
            Qt.callLater(function () {
              s.currentDirectory = directory;
            });
          })(scanner);
        }
      }
    }
  }

  property var recursiveProcesses: ({})

  function scanDirectoryRecursive(screenName, directory) {
    if (!directory || directory === "") {
      Logger.w("Wallpaper", "Empty directory for", screenName);
      wallpaperLists[screenName] = [];
      wallpaperListChanged(screenName, 0);
      return;
    }
    if (recursiveProcesses[screenName]) {
      Logger.d("Wallpaper", "Cancelling existing scan for", screenName);
      recursiveProcesses[screenName].running = false;
      recursiveProcesses[screenName].destroy();
      delete recursiveProcesses[screenName];
      scanningCount--;
    }
    scanningCount++;
    Logger.i("Wallpaper", "Starting recursive scan for", screenName, "in", directory);
    var filters = ImageCacheService.imageFilters;


    var cmd = "find -L '" + directory + "' -type f '('";
    for (var i = 0; i < filters.length; i++) {
      if (i > 0) cmd += " -o";
      cmd += " -iname '" + filters[i] + "'";
    }

    cmd += " ')' -printf '%T@ %p\\n' | sort -nr | cut -d' ' -f2-";

    var processString = `
    import QtQuick
    import Quickshell.Io
    Process {
      id: process
      command: ["sh", "-c", ` + JSON.stringify(cmd) + `]
      stdout: StdioCollector {}
      stderr: StdioCollector {}
    }
    `;
    var processObject = Qt.createQmlObject(processString, root, "RecursiveScan_" + screenName);
    recursiveProcesses[screenName] = processObject;
    var handler = function (exitCode) {
      scanningCount--;
      Logger.d("Wallpaper", "Process exited with code", exitCode, "for", screenName);
      if (exitCode === 0) {
        var lines = processObject.stdout.text.split('\n');
        var files = [];
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim();
          if (line !== '') files.push(line);
        }
        // Removed files.sort() because we are now sorting by date in the shell command
        wallpaperLists[screenName] = files;
        if (alphabeticalIndices[screenName] !== undefined) {
          var currentWallpaper = currentWallpapers[screenName] || "";
          var foundIndex = files.indexOf(currentWallpaper);
          alphabeticalIndices[screenName] = (foundIndex >= 0) ? foundIndex : 0;
        }
        Logger.i("Wallpaper", "Recursive scan completed for", screenName, "found", files.length, "files");
        wallpaperListChanged(screenName, files.length);
      } else {
        Logger.w("Wallpaper", "Recursive scan failed for", screenName, "exit code:", exitCode);
        wallpaperLists[screenName] = [];
        if (alphabeticalIndices[screenName] !== undefined) alphabeticalIndices[screenName] = 0;
        wallpaperListChanged(screenName, 0);
      }
      delete recursiveProcesses[screenName];
      processObject.destroy();
    };
    processObject.exited.connect(handler);
    Logger.d("Wallpaper", "Starting process for", screenName);
    processObject.running = true;
  }

  Timer {
    id: randomWallpaperTimer
    interval: Settings.data.wallpaper.randomIntervalSec * 1000
    running: Settings.data.wallpaper.randomEnabled
    repeat: true
    onTriggered: setNextWallpaper()
    triggeredOnStart: false
  }

  Instantiator {
    id: wallpaperScanners
    model: Quickshell.screens
    delegate: FolderListModel {
      property string screenName: modelData.name
      property string currentDirectory: root.getMonitorDirectory(screenName)
      folder: "file://" + currentDirectory
      nameFilters: ImageCacheService.imageFilters
      caseSensitive: false
        showDirs: false

        // UPDATED: Sort by Time, Reversed (Newest First)
        sortField: FolderListModel.Time
        sortReversed: false

        onCurrentDirectoryChanged: { folder = "file://" + currentDirectory; }
        Component.onCompleted: {
          root.wallpaperDirectoryChanged.connect(function (screen, directory) {
            if (screen === screenName) currentDirectory = directory;
          });
        }
        onStatusChanged: {
          if (status === FolderListModel.Null) {
            root.wallpaperLists[screenName] = [];
            root.wallpaperListChanged(screenName, 0);
          } else if (status === FolderListModel.Loading) {
            root.wallpaperLists[screenName] = [];
            scanningCount++;
          } else if (status === FolderListModel.Ready) {
            var files = [];
            for (var i = 0; i < count; i++) {
              var directory = root.getMonitorDirectory(screenName);
              var filepath = directory + "/" + get(i, "fileName");
              files.push(filepath);
            }
            root.wallpaperLists[screenName] = files;
            if (root.alphabeticalIndices[screenName] !== undefined) {
              var currentWallpaper = root.currentWallpapers[screenName] || "";
              var foundIndex = files.indexOf(currentWallpaper);
              root.alphabeticalIndices[screenName] = (foundIndex >= 0) ? foundIndex : 0;
            }
            scanningCount--;
            Logger.d("Wallpaper", "List refreshed for", screenName, "count:", files.length);
            root.wallpaperListChanged(screenName, files.length);
          }
        }
    }
  }

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
      root.currentWallpapers = wallpaperCacheAdapter.wallpapers || {};
      if (wallpaperCacheAdapter.defaultWallpaper && wallpaperCacheAdapter.defaultWallpaper !== "") {
        root.defaultWallpaper = wallpaperCacheAdapter.defaultWallpaper;
      } else {
        root.defaultWallpaper = root.noctaliaDefaultWallpaper;
      }
      root.isInitialized = true;
    }
    onLoadFailed: error => {
      root.currentWallpapers = {};
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
    }
  }

  // -------------------------------------------------------------------
  // DYNAMIC DARK/LIGHT MODE LOGIC
  // -------------------------------------------------------------------
  Connections {
    target: Settings.data
    function onDarkModeChanged() {
      root.syncPlasmaTheme();
    }
    function onThemeChanged() {
      root.syncPlasmaTheme();
    }
  }

  property bool isDarkMode: {
    if (Settings.data.appearance && Settings.data.appearance.darkMode !== undefined) return Settings.data.appearance.darkMode;
    if (Settings.data.general && Settings.data.general.darkMode !== undefined) return Settings.data.general.darkMode;
    return true;
  }

  Process {
    id: plasmaThemeProcess

    command: root.isDarkMode
    ? ["sh", "-c", "plasma-apply-colorscheme BreezeDark; sleep 1; plasma-apply-colorscheme noctalia"]
    : ["sh", "-c", "plasma-apply-colorscheme BreezeLight; sleep 1; plasma-apply-colorscheme noctalia"]

    stdout: StdioCollector {
      onTextChanged: { if (text.trim() !== "") Logger.d("Wallpaper", "Plasma Theme Output:", text.trim()) }
    }
    stderr: StdioCollector {
      onTextChanged: { if (text.trim() !== "") Logger.w("Wallpaper", "Plasma Theme Error:", text.trim()) }
    }
  }

  function syncPlasmaTheme() {
    if (plasmaThemeProcess.running) return;
    Logger.i("Wallpaper", "Syncing KDE Plasma color scheme (Dark: " + root.isDarkMode + ")...");
    plasmaThemeProcess.running = true;
  }
}
