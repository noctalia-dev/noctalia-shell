pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  property string supporterDataFile: Settings.cacheDir + "supporters.json"
  property int updateFrequency: 60 * 60 // 1 hour in seconds
  property bool isFetching: false
  property bool isInitialized: false

  readonly property alias data: adapter

  property var supporters: []
  property var cachedAvatars: ({}) // username -> file:// path
  property bool avatarsCached: false

  FileView {
    id: supporterDataFileView
    path: supporterDataFile
    printErrors: false
    watchChanges: false

    onLoaded: {
      if (!root.isInitialized) {
        root.isInitialized = true;
        loadFromCache();
      }
    }
    onLoadFailed: function (error) {
      if (error.toString().includes("No such file") || error === 2) {
        root.isInitialized = true;
        fetchFromApi();
      }
    }

    JsonAdapter {
      id: adapter
      property var supporters: []
      property real timestamp: 0
    }
  }

  function init() {
    Logger.i("Supporter", "Service started");
  }

  function loadFromCache() {
    const now = Time.timestamp;
    var needsRefetch = false;

    if (!data.timestamp || (now >= data.timestamp + updateFrequency)) {
      needsRefetch = true;
      Logger.i("Supporter", "Cache expired or missing, scheduling fetch");
    } else {
      Logger.i("Supporter", "Cache is fresh, using cached data");
    }

    if (data.supporters && data.supporters.length > 0) {
      root.supporters = data.supporters;
      Logger.d("Supporter", "Loaded", data.supporters.length, "supporters from cache");
    }

    if (needsRefetch) {
      fetchFromApi();
    }
  }

  function fetchFromApi() {
    if (isFetching) {
      Logger.d("Supporter", "Already fetching");
      return;
    }

    isFetching = true;
    supporterProcess.running = true;
  }

  function saveData() {
    data.timestamp = Time.timestamp;
    Quickshell.execDetached(["mkdir", "-p", Settings.cacheDir]);

    try {
      supporterDataFileView.writeAdapter();
      Logger.d("Supporter", "Cache file written successfully");
    } catch (error) {
      Logger.e("Supporter", "Failed to write cache file:", error);
    }
  }

  function getAvatarPath(username) {
    return cachedAvatars[username] || "";
  }

  function cacheAvatars() {
    if (supporters.length === 0)
      return;

    avatarsCached = true;

    for (var i = 0; i < supporters.length; i++) {
      var supporter = supporters[i];
      var username = supporter.github_username;

      // Only cache avatars for supporters with GitHub accounts
      if (!username)
        continue;

      var avatarUrl = "https://github.com/" + username + ".png?size=256";

      (function (uname, url) {
        ImageCacheService.getCircularAvatar(url, "supporter_" + uname, function (cachedPath, success) {
          if (success) {
            cachedAvatars[uname] = "file://" + cachedPath;
            cachedAvatarsChanged();
          }
        });
      })(username, avatarUrl);
    }
  }

  onSupportersChanged: {
    if (supporters.length > 0 && !avatarsCached && ImageCacheService.initialized) {
      Qt.callLater(cacheAvatars);
    }
  }

  Connections {
    target: ImageCacheService
    function onInitializedChanged() {
      if (ImageCacheService.initialized && supporters.length > 0 && !avatarsCached) {
        Qt.callLater(cacheAvatars);
      }
    }
  }

  Process {
    id: supporterProcess

    command: ["curl", "-s", "https://api.noctalia.dev/supporters"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const response = text;
          if (response && response.trim()) {
            const parsed = JSON.parse(response);
            if (Array.isArray(parsed)) {
              root.data.supporters = parsed;
              root.supporters = parsed;
              root.saveData();
              Logger.d("Supporter", "Fetched", parsed.length, "supporters");
            } else if (parsed.message) {
              Logger.w("Supporter", "API error:", parsed.message);
            }
          }
        } catch (e) {
          Logger.e("Supporter", "Failed to parse response:", e);
        }
        root.isFetching = false;
      }
    }
  }
}
