pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// GitHub API logic for contributors
Singleton {
  id: root

  property string githubDataFile: Quickshell.env("NOCTALIA_GITHUB_FILE") || (Settings.cacheDir + "github.json")
  property int githubUpdateFrequency: 60 * 60 // 1 hour expressed in seconds
  property bool isFetchingData: false
  readonly property alias data: adapter // Used to access via GitHubService.data.xxx.yyy

  // Public properties for easy access
  property string latestVersion: I18n.tr("common.unknown")
  property var contributors: []

  // Avatar caching properties (simplified - uses ImageCacheService)
  property var cachedAvatars: ({}) // username → file:// path
  property bool avatarsCached: false // Track if we've already processed avatars

  property bool isInitialized: false

  FileView {
    id: githubDataFileView
    path: githubDataFile
    printErrors: false
    watchChanges: false  // Disable to prevent reload on our own writes
    Component.onCompleted: {
      // Data loading handled by FileView onLoaded
    }
    onLoaded: {
      if (!root.isInitialized) {
        root.isInitialized = true;
        loadFromCache();
      }
    }
    onLoadFailed: function (error) {
      if (error.toString().includes("No such file") || error === 2) {
        // No cache file exists, fetch fresh data
        root.isInitialized = true;
        fetchFromGitHub();
      }
    }

    JsonAdapter {
      id: adapter

      property string version: I18n.tr("common.unknown")
      property var contributors: []
      property real timestamp: 0
    }
  }

  // --------------------------------
  function init() {
    Logger.i("GitHub", "Service started");
    // FileView will handle loading automatically via onLoaded
  }

  // --------------------------------
  function loadFromCache() {
    const now = Time.timestamp;
    var needsRefetch = false;

    Logger.i("GitHub", "Checking cache - timestamp:", data.timestamp, "now:", now, "age:", data.timestamp ? Math.round((now - data.timestamp) / 60) : "N/A", "minutes");

    if (!data.timestamp || (now >= data.timestamp + githubUpdateFrequency)) {
      needsRefetch = true;
      Logger.i("GitHub", "Cache expired or missing, scheduling fetch (update frequency:", Math.round(githubUpdateFrequency / 60), "minutes)");
    } else {
      Logger.i("GitHub", "Cache is fresh, using cached data (age:", Math.round((now - data.timestamp) / 60), "minutes)");
    }

    if (data.version) {
      root.latestVersion = data.version;
    }
    if (data.contributors && data.contributors.length > 0) {
      root.contributors = data.contributors;
      Logger.d("GitHub", "Loaded", data.contributors.length, "contributors from cache");
    }

    if (needsRefetch) {
      fetchFromGitHub();
    }
  }

  // --------------------------------
  function fetchFromGitHub() {
    if (isFetchingData) {
      Logger.d("GitHub", "GitHub data is still fetching");
      return;
    }

    isFetchingData = true;
    versionProcess.running = true;
    contributorsProcess.running = true;
  }

  // --------------------------------
  function saveData() {
    data.timestamp = Time.timestamp;
    Logger.d("GitHub", "Saving data to cache file:", githubDataFile, "with timestamp:", data.timestamp);
    Logger.d("GitHub", "Data to save - version:", data.version, "contributors:", data.contributors.length);

    // Ensure cache directory exists
    Quickshell.execDetached(["mkdir", "-p", Settings.cacheDir]);

    try {
      // Write immediately instead of Qt.callLater to ensure it completes
      githubDataFileView.writeAdapter();
      Logger.d("GitHub", "Cache file written successfully");
    } catch (error) {
      Logger.e("GitHub", "Failed to write cache file:", error);
    }
  }

  // --------------------------------
  function checkAndSaveData() {
    // Only save when all processes are finished
    if (!versionProcess.running && !contributorsProcess.running) {
      root.isFetchingData = false;

      // Check results
      var anySucceeded = versionProcess.fetchSucceeded || contributorsProcess.fetchSucceeded;
      var wasRateLimited = versionProcess.wasRateLimited || contributorsProcess.wasRateLimited;

      if (anySucceeded) {
        root.saveData();
        Logger.d("GitHub", "Successfully fetched data from GitHub");
      } else if (wasRateLimited) {
        root.saveData();
        Logger.w("GitHub", "API rate limited - using cached data (retry in", Math.round(githubUpdateFrequency / 60), "minutes)");
      } else {
        Logger.w("GitHub", "API request failed - using cached data without updating timestamp");
      }

      // Reset fetch flags for next time
      versionProcess.fetchSucceeded = false;
      versionProcess.wasRateLimited = false;
      contributorsProcess.fetchSucceeded = false;
      contributorsProcess.wasRateLimited = false;
    }
  }

  // --------------------------------
  function resetCache() {
    data.version = I18n.tr("common.unknown");
    data.contributors = [];
    data.timestamp = 0;

    // Try to fetch immediately
    fetchFromGitHub();
  }

  // --------------------------------
  // Avatar Caching Functions (simplified - uses ImageCacheService)
  // --------------------------------

  function getAvatarPath(username) {
    return cachedAvatars[username] || "";
  }

  function cacheTopContributorAvatars() {
    if (contributors.length === 0)
      return;

    avatarsCached = true;

    for (var i = 0; i < Math.min(contributors.length, 20); i++) {
      var contributor = contributors[i];
      var username = contributor.login;
      var avatarUrl = contributor.avatar_url;

      // Use closure to capture username
      (function (uname, url) {
        ImageCacheService.getCircularAvatar(url, uname, function (cachedPath, success) {
          if (success) {
            cachedAvatars[uname] = "file://" + cachedPath;
            cachedAvatarsChanged();
          }
        });
      })(username, avatarUrl);
    }
  }

  // --------------------------------
  // Hook into contributors change - only process once
  onContributorsChanged: {
    if (contributors.length > 0 && !avatarsCached && ImageCacheService.initialized) {
      Qt.callLater(cacheTopContributorAvatars);
    }
  }

  // Also watch for ImageCacheService to become initialized
  Connections {
    target: ImageCacheService
    function onInitializedChanged() {
      if (ImageCacheService.initialized && contributors.length > 0 && !avatarsCached) {
        Qt.callLater(cacheTopContributorAvatars);
      }
    }
  }

  Process {
    id: versionProcess

    property bool fetchSucceeded: false
    property bool wasRateLimited: false

    command: ["curl", "-s", "https://api.github.com/repos/noctalia-dev/noctalia-shell/releases/latest"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const response = text;
          if (response && response.trim()) {
            const data = JSON.parse(response);
            if (data.tag_name) {
              const version = data.tag_name;
              root.data.version = version;
              root.latestVersion = version;
              versionProcess.fetchSucceeded = true;
              Logger.d("GitHub", "Latest version fetched:", version);
            } else if (data.message) {
              // Check if it's a rate limit error
              if (data.message.includes("rate limit")) {
                versionProcess.wasRateLimited = true;
              } else {
                Logger.w("GitHub", "Version API error:", data.message);
              }
            }
          }
        } catch (e) {
          Logger.e("GitHub", "Failed to parse version response:", e);
        }

        // Check if both processes are done
        checkAndSaveData();
      }
    }
  }

  Process {
    id: contributorsProcess

    property bool fetchSucceeded: false
    property bool wasRateLimited: false

    command: ["curl", "-s", "https://api.github.com/repos/noctalia-dev/noctalia-shell/contributors?per_page=100"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const response = text;
          Logger.d("GitHub", "Raw contributors response length:", response ? response.length : 0);
          if (response && response.trim()) {
            const data = JSON.parse(response);
            Logger.d("GitHub", "Parsed contributors data type:", typeof data, "length:", Array.isArray(data) ? data.length : "not array");
            // Only update if we got a valid array
            if (Array.isArray(data)) {
              root.data.contributors = data;
              root.contributors = root.data.contributors;
              contributorsProcess.fetchSucceeded = true;
              Logger.d("GitHub", "Contributors fetched:", root.contributors.length);
            } else if (data.message) {
              // Check if it's a rate limit error
              if (data.message.includes("rate limit")) {
                contributorsProcess.wasRateLimited = true;
              } else {
                Logger.w("GitHub", "Contributors API error:", data.message);
              }
            }
          }
        } catch (e) {
          Logger.e("GitHub", "Failed to parse contributors response:", e);
        }

        // Check if both processes are done
        checkAndSaveData();
      }
    }
  }
}
