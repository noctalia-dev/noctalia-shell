pragma Singleton

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

  // All transition keys but filter out "none" and "random" so we are left with the real transitions
  readonly property var allTransitions: Array.from({
                                                     "length": transitionsModel.count
                                                   }, (_, i) => transitionsModel.get(i).key).filter(key => key !== "random" && key != "none")

  property var wallpaperLists: ({})
  property int scanningCount: 0

  // Cache for current wallpapers - can be updated directly since we use signals for notifications
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
  // Emitted when a wallpaper changes
  signal wallpaperProcessingComplete(string screenName, string path, string cachedPath)
  // Emitted when wallpaper processing (resize/cache) is complete. cachedPath is the resized version.
  signal wallpaperDirectoryChanged(string screenName, string directory)
  // Emitted when a monitor's directory changes
  signal wallpaperListChanged(string screenName, int count)

  // Emitted when available wallpapers list changes

  // Browse mode: track current browse path per screen (separate from root directory)
  property var currentBrowsePaths: ({})

  // Signal emitted when browse path changes for a screen
  signal browsePathChanged(string screenName, string path)

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
    function onAutomationEnabledChanged() {
      root.toggleRandomWallpaper();
    }
    function onRandomIntervalSecChanged() {
      root.restartRandomWallpaperTimer();
    }
    function onWallpaperChangeModeChanged() {
      // Reset alphabetical indices when mode changes
      root.alphabeticalIndices = {};
      if (Settings.data.wallpaper.automationEnabled) {
        root.restartRandomWallpaperTimer();
        root.setNextWallpaper();
      }
    }
    function onViewModeChanged() {
      // Reset browse paths to root when mode changes
      root.currentBrowsePaths = {};
      root.refreshWallpapersList();
    }
    function onShowHiddenFilesChanged() {
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
    function onSortOrderChanged() {
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
                           "name": I18n.tr("positions.center"),
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
    fillModeModel.append({
                           "key": "repeat",
                           "name": I18n.tr("wallpaper.fill-modes.repeat"),
                           "uniform": 4.0
                         });

    // Populate transitionsModel with translated names
    transitionsModel.append({
                              "key": "none",
                              "name": I18n.tr("common.none")
                            });
    transitionsModel.append({
                              "key": "random",
                              "name": I18n.tr("common.random")
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
    transitionsModel.append({
                              "key": "pixelate",
                              "name": I18n.tr("wallpaper.transitions.pixelate")
                            });
    transitionsModel.append({
                              "key": "honeycomb",
                              "name": I18n.tr("wallpaper.transitions.honeycomb")
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
  // Solid color helpers
  // -------------------------------------------------------------------
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
    // Return solid color path when in solid color mode
    if (Settings.data.wallpaper.useSolidColor) {
      return createSolidColorPath(Settings.data.wallpaper.solidColor.toString());
    }
    return currentWallpapers[screenName] || root.defaultWallpaper;
  }

  // -------------------------------------------------------------------
  function changeWallpaper(path, screenName) {
    // Turn off solid color mode when selecting a wallpaper
    if (Settings.data.wallpaper.useSolidColor) {
      Settings.data.wallpaper.useSolidColor = false;
    }

    if (screenName !== undefined) {
      _setWallpaper(screenName, path);
    } else {
      // If no screenName specified change for all screens
      // Merge connected screens and cached screens to include disconnected monitors
      var allScreenNames = new Set(Object.keys(currentWallpapers));
      for (var i = 0; i < Quickshell.screens.length; i++) {
        allScreenNames.add(Quickshell.screens[i].name);
      }
      allScreenNames.forEach(name => _setWallpaper(name, path));
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
  function setAlphabeticalWallpaper() {
    Logger.d("Wallpaper", "setAlphabeticalWallpaper");

    if (Settings.data.wallpaper.enableMultiMonitorDirectories) {
      // Pick next alphabetical wallpaper per screen
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name;
        var wallpaperList = getWallpapersList(screenName);

        if (wallpaperList.length > 0) {
          // Get or initialize index for this screen
          if (alphabeticalIndices[screenName] === undefined) {
            // Find current wallpaper in list to set initial index
            var currentWallpaper = currentWallpapers[screenName] || "";
            var foundIndex = wallpaperList.indexOf(currentWallpaper);
            alphabeticalIndices[screenName] = (foundIndex >= 0) ? foundIndex : 0;
          }

          // Get next index (wrap around)
          var currentIndex = alphabeticalIndices[screenName];
          var nextIndex = (currentIndex + 1) % wallpaperList.length;
          alphabeticalIndices[screenName] = nextIndex;

          var nextPath = wallpaperList[nextIndex];
          changeWallpaper(nextPath, screenName);
        }
      }
    } else {
      // Pick next alphabetical wallpaper common to all screens
      var wallpaperList = getWallpapersList(Screen.name);
      if (wallpaperList.length > 0) {
        // Use primary screen name as key for single directory mode
        var key = "all";
        if (alphabeticalIndices[key] === undefined) {
          // Find current wallpaper in list to set initial index
          var currentWallpaper = currentWallpapers[Screen.name] || "";
          var foundIndex = wallpaperList.indexOf(currentWallpaper);
          alphabeticalIndices[key] = (foundIndex >= 0) ? foundIndex : 0;
        }

        // Get next index (wrap around)
        var currentIndex = alphabeticalIndices[key];
        var nextIndex = (currentIndex + 1) % wallpaperList.length;
        alphabeticalIndices[key] = nextIndex;

        var nextPath = wallpaperList[nextIndex];
        changeWallpaper(nextPath, undefined);
      }
    }
  }

  // -------------------------------------------------------------------
  function toggleRandomWallpaper() {
    Logger.d("Wallpaper", "toggleRandomWallpaper");
    if (Settings.data.wallpaper.automationEnabled) {
      restartRandomWallpaperTimer();
      setNextWallpaper();
    }
  }

  // -------------------------------------------------------------------
  function setNextWallpaper() {
    var mode = Settings.data.wallpaper.wallpaperChangeMode || "random";
    if (mode === "alphabetical") {
      setAlphabeticalWallpaper();
    } else {
      setRandomWallpaper();
    }
  }

  // -------------------------------------------------------------------
  function restartRandomWallpaperTimer() {
    if (Settings.data.wallpaper.automationEnabled) {
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
  // Browse mode helper functions
  // -------------------------------------------------------------------
  function getCurrentBrowsePath(screenName) {
    if (currentBrowsePaths[screenName] !== undefined) {
      var stored = currentBrowsePaths[screenName];
      var root = getMonitorDirectory(screenName);
      if (root && stored.startsWith(root)) {
        return stored;
      }
      // Stored path is outside the root directory, reset it
      delete currentBrowsePaths[screenName];
    }
    return getMonitorDirectory(screenName);
  }

  function setBrowsePath(screenName, path) {
    if (!screenName)
      return;
    currentBrowsePaths[screenName] = path;
    browsePathChanged(screenName, path);
  }

  function navigateUp(screenName) {
    if (!screenName)
      return;
    var currentPath = getCurrentBrowsePath(screenName);
    var rootPath = getMonitorDirectory(screenName);

    // Don't navigate if root is invalid or we're already at root
    if (!rootPath || currentPath === rootPath)
      return;

    // Get parent directory
    var parentPath = currentPath.replace(/\/[^\/]+\/?$/, "");
    if (parentPath === "")
      parentPath = rootPath;

    // Don't go above root
    if (!parentPath.startsWith(rootPath)) {
      parentPath = rootPath;
    }

    setBrowsePath(screenName, parentPath);
  }

  function navigateToRoot(screenName) {
    if (!screenName)
      return;
    var rootPath = getMonitorDirectory(screenName);
    setBrowsePath(screenName, rootPath);
  }

  // Scan directory with optional directory listing (for browse mode)
  // callback receives { files: [], directories: [] }
  function scanDirectoryWithDirs(screenName, directory, callback) {
    if (!directory || directory === "") {
      callback({
                 files: [],
                 directories: []
               });
      return;
    }

    var result = {
      files: [],
      directories: []
    };
    var pendingScans = 2;

    function checkComplete() {
      pendingScans--;
      if (pendingScans === 0) {
        // Files are already sorted by _scanDirectoryInternal according to sortOrder setting
        // Only sort directories alphabetically
        result.directories.sort();
        callback(result);
      }
    }

    // Scan for files
    _scanDirectoryInternal(screenName, directory, false, false, function (files) {
      result.files = files;
      checkComplete();
    });

    // Scan for directories
    _scanForDirectories(directory, function (dirs) {
      result.directories = dirs;
      checkComplete();
    });
  }

  function _scanForDirectories(directory, callback) {
    var findArgs = ["find", "-L", directory, "-maxdepth", "1", "-mindepth", "1", "-type", "d"];

    var processString = `
    import QtQuick
    import Quickshell.Io
    Process {
      id: process
      command: ${JSON.stringify(findArgs)}
      stdout: StdioCollector {}
      stderr: StdioCollector {}
    }
    `;

    var processObject = Qt.createQmlObject(processString, root, "DirScan");

    processObject.exited.connect(function (exitCode) {
      var dirs = [];
      if (exitCode === 0) {
        var lines = processObject.stdout.text.split('\n');
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim();
          if (line !== '') {
            var showHidden = Settings.data.wallpaper.showHiddenFiles;
            var name = line.split('/').pop();
            if (showHidden || !name.startsWith('.')) {
              dirs.push(line);
            }
          }
        }
      }
      callback(dirs);
      processObject.destroy();
    });

    processObject.running = true;
  }

  // -------------------------------------------------------------------
  function refreshWallpapersList() {
    var mode = Settings.data.wallpaper.viewMode;
    Logger.d("Wallpaper", "refreshWallpapersList", "viewMode:", mode);
    scanningCount = 0;

    if (mode === "recursive") {
      // Use Process-based recursive search for all screens
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name;
        var directory = getMonitorDirectory(screenName);
        scanDirectoryRecursive(screenName, directory);
      }
    } else if (mode === "browse") {
      // Browse mode: scan current browse path (non-recursive)
      // Note: The actual directory+subdirectory scanning happens in WallpaperPanel
      // Here we just scan the current browse path for files
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name;
        var directory = getCurrentBrowsePath(screenName);
        _scanDirectoryInternal(screenName, directory, false, true, null);
      }
    } else {
      // Single directory mode (non-recursive)
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name;
        var directory = getMonitorDirectory(screenName);
        _scanDirectoryInternal(screenName, directory, false, true, null);
      }
    }
  }

  // Internal scan function
  // recursive: whether to scan subdirectories
  // updateList: whether to update wallpaperLists and emit signal
  // callback: optional callback with files array
  function _scanDirectoryInternal(screenName, directory, recursive, updateList, callback) {
    if (!directory || directory === "") {
      Logger.w("Wallpaper", "Empty directory for", screenName);
      if (updateList) {
        wallpaperLists[screenName] = [];
        wallpaperListChanged(screenName, 0);
      }
      if (callback)
        callback([]);
      return;
    }

    // Cancel any existing scan for this screen
    if (recursiveProcesses[screenName]) {
      Logger.d("Wallpaper", "Cancelling existing scan for", screenName);
      recursiveProcesses[screenName].running = false;
      recursiveProcesses[screenName].destroy();
      delete recursiveProcesses[screenName];
      if (updateList)
        scanningCount--;
    }

    if (updateList)
      scanningCount++;
    Logger.i("Wallpaper", "Starting scan for", screenName, "in", directory, "recursive:", recursive);

    // Build find command args dynamically from ImageCacheService filters
    var filters = ImageCacheService.imageFilters;
    var findArgs = ["find", "-L", directory];

    // Add depth limit for non-recursive
    if (!recursive) {
      findArgs.push("-maxdepth", "1", "-mindepth", "1");
    }

    findArgs.push("-type", "f", "(");
    for (var i = 0; i < filters.length; i++) {
      if (i > 0) {
        findArgs.push("-o");
      }
      findArgs.push("-iname");
      findArgs.push(filters[i]);
    }
    findArgs.push(")");
    // Add printf to get modification time
    findArgs.push("-printf", "%T@|%p\\n");

    // Create Process component inline
    var processString = `
    import QtQuick
    import Quickshell.Io
    Process {
      id: process
      command: ${JSON.stringify(findArgs)}
      stdout: StdioCollector {}
      stderr: StdioCollector {}
    }
    `;

    var processObject = Qt.createQmlObject(processString, root, "Scan_" + screenName);

    // Store reference to avoid garbage collection
    if (updateList) {
      recursiveProcesses[screenName] = processObject;
    }

    var handler = function (exitCode) {
      if (updateList)
        scanningCount--;
      Logger.d("Wallpaper", "Process exited with code", exitCode, "for", screenName);

      var files = [];
      if (exitCode === 0) {
        var lines = processObject.stdout.text.split('\n');
        var parsedFiles = [];

        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim();
          if (line !== '') {
            var parts = line.split('|');
            if (parts.length >= 2) { // Handle potential extra pipes in filename by joining rest
              var timestamp = parseFloat(parts[0]);
              var path = parts.slice(1).join('|');

              var showHidden = Settings.data.wallpaper.showHiddenFiles;
              var name = path.split('/').pop();
              if (showHidden || !name.startsWith('.')) {
                parsedFiles.push({
                                   path: path,
                                   time: timestamp,
                                   name: name
                                 });
              }
            } else if (line.indexOf('|') === -1) {
              // Fallback for unexpected output format or old find versions (unlikely but safe)
              var path = line;
              var showHidden = Settings.data.wallpaper.showHiddenFiles;
              var name = path.split('/').pop();
              if (showHidden || !name.startsWith('.')) {
                parsedFiles.push({
                                   path: path,
                                   time: 0,
                                   name: name
                                 });
              }
            }
          }
        }
        // Sort files based on settings
        var sortOrder = Settings.data.wallpaper.sortOrder || "name";

        // Fischer-Yates shuffle
        if (sortOrder === "random") {
          for (let i = parsedFiles.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const temp = parsedFiles[i];
            parsedFiles[i] = parsedFiles[j];
            parsedFiles[j] = temp;
          }
        } else {
          parsedFiles.sort(function (a, b) {
            if (sortOrder === "date_desc") { // Newest first
              return b.time - a.time;
            } else if (sortOrder === "date_asc") { // Oldest first
              return a.time - b.time;
            } else if (sortOrder === "name_desc") {
              return b.name.localeCompare(a.name);
            } else { // name (asc)
              return a.name.localeCompare(b.name);
            }
          });
        }

        // Map back to string array
        files = parsedFiles.map(f => f.path);

        if (updateList) {
          wallpaperLists[screenName] = files;

          // Reset alphabetical indices when list changes
          if (alphabeticalIndices[screenName] !== undefined) {
            var currentWallpaper = currentWallpapers[screenName] || "";
            var foundIndex = files.indexOf(currentWallpaper);
            alphabeticalIndices[screenName] = (foundIndex >= 0) ? foundIndex : 0;
          }

          Logger.i("Wallpaper", "Scan completed for", screenName, "found", files.length, "files");
          wallpaperListChanged(screenName, files.length);
        }
      } else {
        Logger.w("Wallpaper", "Scan failed for", screenName, "exit code:", exitCode, "(directory might not exist)");
        if (updateList) {
          wallpaperLists[screenName] = [];
          if (alphabeticalIndices[screenName] !== undefined) {
            alphabeticalIndices[screenName] = 0;
          }
          wallpaperListChanged(screenName, 0);
        }
      }

      // Clean up
      if (updateList) {
        delete recursiveProcesses[screenName];
      }

      if (callback)
        callback(files);
      processObject.destroy();
    };

    processObject.exited.connect(handler);
    Logger.d("Wallpaper", "Starting process for", screenName);
    processObject.running = true;
  }

  // Process instances for scanning (one per screen)
  property var recursiveProcesses: ({})

  // -------------------------------------------------------------------
  function scanDirectoryRecursive(screenName, directory) {
    _scanDirectoryInternal(screenName, directory, true, true, null);
  }

  // -------------------------------------------------------------------
  // -------------------------------------------------------------------
  // -------------------------------------------------------------------
  Timer {
    id: randomWallpaperTimer
    interval: Settings.data.wallpaper.randomIntervalSec * 1000
    running: Settings.data.wallpaper.automationEnabled
    repeat: true
    onTriggered: setNextWallpaper()
    triggeredOnStart: false
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
