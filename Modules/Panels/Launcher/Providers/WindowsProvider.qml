import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Compositor

Item {
  id: root

  property string name: I18n.tr("common.windows")
  property var launcher: null
  property bool handleSearch: Settings.data.appLauncher.enableWindowsSearch
  property string supportedLayouts: "list"

  function init() {
    Logger.d("WindowsProvider", "Initialized");
  }

  // Check if this provider handles the command
  function handleCommand(searchText) {
    return searchText.startsWith(">win");
  }

  // Return available commands when user types ">"
  function commands() {
    return [
          {
            "name": ">win",
            "description": I18n.tr("launcher.providers.windows-search-description"),
            "icon": "app-window",
            "isTablerIcon": true,
            "isImage": false,
            "onActivate": function () {
              launcher.setSearchText(">win ");
            }
          }
        ];
  }

  function getResults(query) {
    if (!query)
      return [];

    var trimmed = query.trim();

    // Handle command mode: ">win" or ">win <search>"
    var isCommandMode = trimmed.startsWith(">win");
    if (isCommandMode) {
      // Extract search term after ">win "
      var searchTerm = trimmed.substring(4).trim();
      // In command mode, show all windows if no search term
      if (searchTerm.length === 0) {
        return getAllWindows();
      }
      trimmed = searchTerm;
    } else {
      // Regular search mode - require at least 2 chars
      if (trimmed.length < 2)
        return [];
    }

    var items = [];

    // Collect all windows from CompositorService
    for (var i = 0; i < CompositorService.windows.count; i++) {
      var win = CompositorService.windows.get(i);
      items.push({
                   "id": win.id,
                   "title": win.title || "",
                   "appId": win.appId || "",
                   "workspaceId": win.workspaceId,
                   "isFocused": win.isFocused,
                   "searchText": (win.title + " " + win.appId).toLowerCase()
                 });
    }

    // Fuzzy search on title and appId
    var results = FuzzySort.go(trimmed, items, {
                                 "keys": ["title", "appId"],
                                 "limit": 10
                               });

    // Map to launcher items
    var launcherItems = [];
    for (var j = 0; j < results.length; j++) {
      var entry = results[j].obj;
      var score = results[j].score;

      // Get icon name from DesktopEntry if available, otherwise use appId
      var iconName = entry.appId;
      var appEntry = ThemeIcons.findAppEntry(entry.appId);
      if (appEntry && appEntry.icon) {
        iconName = appEntry.icon;
      }

      launcherItems.push({
                           "name": entry.title || entry.appId,
                           "description": entry.appId,
                           "icon": iconName || "application-x-executable",
                           "isTablerIcon": false,
                           "badgeIcon": "app-window",
                           "_score": score,
                           "provider": root,
                           "windowId": entry.id,
                           "onActivate": createActivateHandler(entry)
                         });
    }

    return launcherItems;
  }

  function getAllWindows() {
    var launcherItems = [];

    for (var i = 0; i < CompositorService.windows.count; i++) {
      var win = CompositorService.windows.get(i);

      var iconName = win.appId;
      var appEntry = ThemeIcons.findAppEntry(win.appId);
      if (appEntry && appEntry.icon) {
        iconName = appEntry.icon;
      }

      launcherItems.push({
                           "name": win.title || win.appId,
                           "description": win.appId,
                           "icon": iconName || "application-x-executable",
                           "isTablerIcon": false,
                           "badgeIcon": "app-window",
                           "_score": 0,
                           "provider": root,
                           "windowId": win.id,
                           "onActivate": createActivateHandler({
                                                                 "id": win.id
                                                               })
                         });
    }

    return launcherItems;
  }

  function createActivateHandler(windowEntry) {
    return function () {
      if (launcher)
        launcher.close();

      Qt.callLater(() => {
                     // Find the actual window object to pass to focusWindow
                     for (var i = 0; i < CompositorService.windows.count; i++) {
                       var win = CompositorService.windows.get(i);
                       if (win.id === windowEntry.id) {
                         CompositorService.focusWindow(win);
                         break;
                       }
                     }
                   });
    };
  }
}
