import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  // Provider metadata
  property string name: I18n.tr("launcher.providers.bookmarks")
  property var launcher: null
  property string iconMode: Settings.data.appLauncher.iconMode
  property bool handleSearch: false  // Only accessible via >bm command
  property string supportedLayouts: "list"
  property int preferredGridColumns: 5

  // Internal state
  property var bookmarks: []
  property bool isLoading: false
  property bool dataLoaded: false

  // Home directory
  readonly property string homeDir: Quickshell.env("HOME") || "/home"

  // Chromium-based browser configurations
  function getChromiumBrowserConfigs() {
    return [
      {
        "name": "Google Chrome",
        "id": "chrome",
        "paths": [
          homeDir + "/.config/google-chrome",
          homeDir + "/.config/google-chrome-beta",
          homeDir + "/.config/google-chrome-unstable"
        ]
      },
      {
        "name": "Chromium",
        "id": "chromium",
        "paths": [
          homeDir + "/.config/chromium"
        ]
      },
      {
        "name": "Brave",
        "id": "brave",
        "paths": [
          homeDir + "/.config/BraveSoftware/Brave-Browser",
          homeDir + "/.config/BraveSoftware/Brave-Browser-Beta",
          homeDir + "/.config/BraveSoftware/Brave-Browser-Nightly"
        ]
      },
      {
        "name": "Microsoft Edge",
        "id": "edge",
        "paths": [
          homeDir + "/.config/microsoft-edge",
          homeDir + "/.config/microsoft-edge-beta",
          homeDir + "/.config/microsoft-edge-dev"
        ]
      },
      {
        "name": "Vivaldi",
        "id": "vivaldi",
        "paths": [
          homeDir + "/.config/vivaldi",
          homeDir + "/.config/vivaldi-snapshot"
        ]
      },
      {
        "name": "Opera",
        "id": "opera",
        "paths": [
          homeDir + "/.config/opera",
          homeDir + "/.config/opera-beta",
          homeDir + "/.config/opera-developer"
        ]
      }
    ];
  }

  // Firefox-based browser configurations
  function getFirefoxBrowserConfigs() {
    return [
      {
        "name": "Firefox",
        "id": "firefox",
        "paths": [
          homeDir + "/.mozilla/firefox"
        ]
      },
      {
        "name": "Firefox Developer Edition",
        "id": "firefox-dev",
        "paths": [
          homeDir + "/.mozilla/firefox-dev",
          homeDir + "/.mozilla/firefox-developer-edition"
        ]
      },
      {
        "name": "LibreWolf",
        "id": "librewolf",
        "paths": [
          homeDir + "/.librewolf"
        ]
      },
      {
        "name": "Zen Browser",
        "id": "zen",
        "paths": [
          homeDir + "/.zen"
        ]
      }
    ];
  }

  // Initialize provider
  function init() {
    Logger.d("BookmarksProvider", "Initialized");
    loadBookmarks();
  }

  function onOpened() {
    if (!dataLoaded) {
      loadBookmarks();
    }
  }

  // Check if this provider handles the command
  function handleCommand(searchText) {
    return searchText.startsWith(">bm");
  }

  // Return available commands when user types ">"
  function commands() {
    return [
          {
            "name": ">bm",
            "description": I18n.tr("launcher.providers.bookmarks-search-description"),
            "icon": "bookmarks",
            "isTablerIcon": true,
            "isImage": false,
            "onActivate": function () {
              launcher.setSearchText(">bm ");
            }
          }
        ];
  }

  // Get search results
  function getResults(searchText) {
    if (!searchText.startsWith(">bm")) {
      return [];
    }

    let query = searchText.slice(3).trim();

    if (isLoading) {
      return [
            {
              "name": I18n.tr("launcher.providers.bookmarks-loading"),
              "description": I18n.tr("launcher.providers.emoji-loading-description"),
              "icon": "refresh",
              "isTablerIcon": true,
              "isImage": false,
              "onActivate": function () {}
            }
          ];
    }

    if (bookmarks.length === 0 && dataLoaded) {
      return [
            {
              "name": I18n.tr("launcher.providers.bookmarks-empty"),
              "description": I18n.tr("launcher.providers.bookmarks-empty-description"),
              "icon": "bookmarks-off",
              "isTablerIcon": true,
              "isImage": false,
              "onActivate": function () {}
            }
          ];
    }

    let filteredBookmarks = bookmarks;

    if (query !== "") {
      const searchTerm = query.toLowerCase();

      if (typeof FuzzySort !== 'undefined') {
        const fuzzyResults = FuzzySort.go(searchTerm, filteredBookmarks, {
                                            "keys": ["name", "url", "folderPath"],
                                            "limit": 50
                                          });
        return fuzzyResults.map(result => formatBookmarkEntry(result.obj, result.score));
      } else {
        // Fallback to simple search
        filteredBookmarks = filteredBookmarks.filter(bm => {
                                                       const name = (bm.name || "").toLowerCase();
                                                       const url = (bm.url || "").toLowerCase();
                                                       const folder = (bm.folderPath || "").toLowerCase();
                                                       return name.includes(searchTerm) || url.includes(searchTerm) || folder.includes(searchTerm);
                                                     });
      }
    }

    // Sort alphabetically if no search query
    if (query === "") {
      filteredBookmarks = filteredBookmarks.slice().sort((a, b) => {
                                                           return (a.name || "").toLowerCase().localeCompare((b.name || "").toLowerCase());
                                                         });
    }

    // Limit results
    return filteredBookmarks.slice(0, 100).map(bm => formatBookmarkEntry(bm, 0));
  }

  function formatBookmarkEntry(bookmark, score) {
    // Format description with folder path and browser info
    let description = bookmark.url || "";
    if (description.length > 60) {
      description = description.substring(0, 57) + "...";
    }

    let folderInfo = "";
    if (bookmark.folderPath) {
      folderInfo = bookmark.folderPath;
    }
    if (bookmark.browserName) {
      folderInfo = folderInfo ? `${bookmark.browserName} • ${folderInfo}` : bookmark.browserName;
    }

    return {
      "name": bookmark.name || bookmark.url || "Untitled",
      "description": folderInfo ? `${folderInfo}\n${description}` : description,
      "icon": "bookmark",
      "isTablerIcon": true,
      "isImage": false,
      "_score": score || 0,
      "provider": root,
      "bookmarkUrl": bookmark.url,
      "onActivate": function () {
        openBookmark(bookmark.url);
      }
    };
  }

  function openBookmark(url) {
    if (!url)
      return;

    launcher.closeImmediately();
    Qt.callLater(() => {
                   Logger.d("BookmarksProvider", `Opening bookmark: ${url}`);
                   Quickshell.execDetached(["xdg-open", url]);
                 });
  }

  // ============================================
  // Bookmark Loading
  // ============================================

  property var _browserMap: ({})
  property var _foundChromiumFiles: []
  property var _firefoxProfiles: []
  property int _currentFileIndex: 0
  property int _pendingOperations: 0

  function loadBookmarks() {
    if (isLoading)
      return;

    isLoading = true;
    bookmarks = [];
    _foundChromiumFiles = [];
    _firefoxProfiles = [];
    _currentFileIndex = 0;
    _pendingOperations = 0;

    const enabledBrowsers = Settings.data.appLauncher.bookmarksBrowsers || [];

    // Start Chromium bookmark search
    loadChromiumBookmarks(enabledBrowsers);

    // Start Firefox bookmark search
    loadFirefoxBookmarks(enabledBrowsers);
  }

  // ============================================
  // Chromium-based browsers
  // ============================================

  function loadChromiumBookmarks(enabledBrowsers) {
    const chromiumConfigs = getChromiumBrowserConfigs();

    let findPaths = [];
    let browserMap = {};

    for (const browser of chromiumConfigs) {
      if (!enabledBrowsers.includes(browser.id))
        continue;

      for (const basePath of browser.paths) {
        findPaths.push(basePath);
        browserMap[basePath] = browser;
      }
    }

    if (findPaths.length === 0) {
      checkLoadingComplete();
      return;
    }

    root._browserMap = browserMap;
    _pendingOperations++;

    let cmd = "find " + findPaths.map(p => `"${p}"`).join(" ") + " -name 'Bookmarks' -type f 2>/dev/null";
    chromiumFinderProcess.command = ["sh", "-c", cmd];
    chromiumFinderProcess.running = true;
  }

  Process {
    id: chromiumFinderProcess
    running: false

    onExited: function (exitCode, exitStatus) {
      const output = stdout.text.trim();
      if (output !== "") {
        root._foundChromiumFiles = output.split('\n').filter(f => f.length > 0);
        Logger.d("BookmarksProvider", `Found ${root._foundChromiumFiles.length} Chromium bookmark files`);
        root._currentFileIndex = 0;
        root.readNextChromiumFile();
      } else {
        root._pendingOperations--;
        root.checkLoadingComplete();
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  function readNextChromiumFile() {
    if (_currentFileIndex >= _foundChromiumFiles.length) {
      _pendingOperations--;
      checkLoadingComplete();
      return;
    }

    const filePath = _foundChromiumFiles[_currentFileIndex];
    let browser = null;
    for (const basePath in _browserMap) {
      if (filePath.startsWith(basePath)) {
        browser = _browserMap[basePath];
        break;
      }
    }

    chromiumReaderProcess._currentFilePath = filePath;
    chromiumReaderProcess._currentBrowser = browser;
    chromiumReaderProcess.command = ["cat", filePath];
    chromiumReaderProcess.running = true;
  }

  Process {
    id: chromiumReaderProcess
    running: false

    property string _currentFilePath: ""
    property var _currentBrowser: null

    onExited: function (exitCode, exitStatus) {
      if (exitCode === 0) {
        const content = stdout.text.trim();
        if (content !== "") {
          try {
            const data = JSON.parse(content);
            root.parseChromiumBookmarks(data, _currentBrowser);
          } catch (e) {
            Logger.d("BookmarksProvider", `Failed to parse ${_currentFilePath}: ${e}`);
          }
        }
      }

      root._currentFileIndex++;
      Qt.callLater(root.readNextChromiumFile);
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  function parseChromiumBookmarks(data, browser) {
    if (!data || !data.roots)
      return;

    const roots = data.roots;

    if (roots.bookmark_bar && roots.bookmark_bar.children) {
      parseChromiumFolder(roots.bookmark_bar.children, browser, "");
    }

    if (roots.other && roots.other.children) {
      parseChromiumFolder(roots.other.children, browser, "");
    }

    if (roots.synced && roots.synced.children) {
      parseChromiumFolder(roots.synced.children, browser, "");
    }
  }

  function parseChromiumFolder(items, browser, parentPath) {
    if (!Array.isArray(items))
      return;

    for (const item of items) {
      if (item.type === "url" && item.url) {
        bookmarks.push({
                         "name": item.name || "",
                         "url": item.url,
                         "folderPath": parentPath,
                         "browserName": browser ? browser.name : "Unknown"
                       });
      } else if (item.type === "folder" && item.children) {
        const newPath = parentPath ? `${parentPath} / ${item.name}` : item.name;
        parseChromiumFolder(item.children, browser, newPath);
      }
    }
  }

  // ============================================
  // Firefox-based browsers
  // ============================================

  function loadFirefoxBookmarks(enabledBrowsers) {
    const firefoxConfigs = getFirefoxBrowserConfigs();

    let findPaths = [];
    let browserMap = {};

    for (const browser of firefoxConfigs) {
      if (!enabledBrowsers.includes(browser.id))
        continue;

      for (const basePath of browser.paths) {
        findPaths.push(basePath);
        browserMap[basePath] = browser;
      }
    }

    if (findPaths.length === 0) {
      checkLoadingComplete();
      return;
    }

    root._firefoxBrowserMap = browserMap;
    _pendingOperations++;

    let cmd = "find " + findPaths.map(p => `"${p}"`).join(" ") + " -name 'places.sqlite' -type f 2>/dev/null";
    firefoxFinderProcess.command = ["sh", "-c", cmd];
    firefoxFinderProcess.running = true;
  }

  property var _firefoxBrowserMap: ({})
  property var _foundFirefoxFiles: []
  property int _currentFirefoxIndex: 0

  Process {
    id: firefoxFinderProcess
    running: false

    onExited: function (exitCode, exitStatus) {
      const output = stdout.text.trim();
      if (output !== "") {
        root._foundFirefoxFiles = output.split('\n').filter(f => f.length > 0);
        Logger.d("BookmarksProvider", `Found ${root._foundFirefoxFiles.length} Firefox bookmark databases`);
        root._currentFirefoxIndex = 0;
        root.readNextFirefoxFile();
      } else {
        root._pendingOperations--;
        root.checkLoadingComplete();
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  function readNextFirefoxFile() {
    if (_currentFirefoxIndex >= _foundFirefoxFiles.length) {
      _pendingOperations--;
      checkLoadingComplete();
      return;
    }

    const dbPath = _foundFirefoxFiles[_currentFirefoxIndex];

    let browser = null;
    for (const basePath in _firefoxBrowserMap) {
      if (dbPath.startsWith(basePath)) {
        browser = _firefoxBrowserMap[basePath];
        break;
      }
    }

    firefoxReaderProcess._currentBrowser = browser;
    const query = "SELECT b.title, p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type = 1 AND p.url NOT LIKE 'place:%' AND p.url IS NOT NULL AND b.title IS NOT NULL";
    firefoxReaderProcess.command = ["sh", "-c", `sqlite3 -separator '	' "file:${dbPath}?mode=ro&immutable=1" "${query}" 2>/dev/null || sqlite3 -separator '	' "${dbPath}" "${query}" 2>/dev/null`];
    firefoxReaderProcess.running = true;
  }

  Process {
    id: firefoxReaderProcess
    running: false

    property var _currentBrowser: null

    onExited: function (exitCode, exitStatus) {
      const output = stdout.text.trim();
      if (output !== "") {
        root.parseFirefoxOutput(output, _currentBrowser);
      }

      root._currentFirefoxIndex++;
      Qt.callLater(root.readNextFirefoxFile);
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  function parseFirefoxOutput(output, browser) {
    const lines = output.split('\n');
    for (const line of lines) {
      if (!line.trim()) continue;

      const parts = line.split('\t');
      if (parts.length >= 2) {
        const title = parts[0];
        const url = parts[1];

        if (url && !url.startsWith('place:')) {
          bookmarks.push({
                           "name": title || "",
                           "url": url,
                           "folderPath": "",
                           "browserName": browser ? browser.name : "Firefox"
                         });
        }
      }
    }
  }

  // ============================================
  // Loading completion
  // ============================================

  function checkLoadingComplete() {
    if (_pendingOperations <= 0) {
      isLoading = false;
      dataLoaded = true;
      Logger.d("BookmarksProvider", `Loaded ${bookmarks.length} bookmarks total`);
      if (launcher) {
        launcher.updateResults();
      }
    }
  }

  // Refresh bookmarks
  function refresh() {
    dataLoaded = false;
    loadBookmarks();
  }

  // Item actions
  function getItemActions(item) {
    if (!item || !item.bookmarkUrl)
      return [];

    return [
          {
            "icon": "copy",
            "tooltip": I18n.tr("common.copied-to-clipboard"),
            "action": function () {
              Quickshell.execDetached(["wl-copy", item.bookmarkUrl]);
              if (launcher)
                launcher.close();
            }
          }
        ];
  }
}
