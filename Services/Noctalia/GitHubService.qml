pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// GitHub API logic for contributors
Singleton {
  id: root

  property string githubDataFile: Quickshell.env("NOCTALIA_GITHUB_FILE") || (Settings.cacheDir + "github.json")
  property int githubUpdateFrequency: 60 * 60 // 1 hour expressed in seconds
  property bool isFetchingData: false
  readonly property alias data: adapter // Used to access via GitHubService.data.xxx.yyy

  // Public properties for easy access
  property string latestVersion: I18n.tr("system.unknown-version")
  property var contributors: []

  // Avatar caching properties
  property var cachedCircularAvatars: ({}) // username → file:// path
  property var cacheMetadata: ({}) // Loaded from metadata.json
  property var avatarQueue: []
  property bool isProcessingAvatars: false
  property bool metadataLoaded: false
  property bool avatarsCached: false // Track if we've already processed avatars

  readonly property string avatarCacheDir: Settings.cacheDirImages + "contributors/"
  readonly property string metadataPath: avatarCacheDir + "metadata.json"

  property bool isInitialized: false

  FileView {
    id: githubDataFileView
    path: githubDataFile
    printErrors: false
    watchChanges: false  // Disable to prevent reload on our own writes
    Component.onCompleted: {
      loadCacheMetadata();
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

      property string version: I18n.tr("system.unknown-version")
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
    data.version = I18n.tr("system.unknown-version");
    data.contributors = [];
    data.timestamp = 0;

    // Try to fetch immediately
    fetchFromGitHub();
  }

  // --------------------------------
  // Avatar Caching Functions
  // --------------------------------

  function loadCacheMetadata() {
    var loadProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${metadataPath}"]
      }
    `, root, "LoadMetadata");

    loadProcess.stdout = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      StdioCollector {}
    `, loadProcess, "StdoutCollector");

    loadProcess.stdout.onStreamFinished.connect(function () {
      try {
        var text = loadProcess.stdout.text;
        if (text && text.trim()) {
          cacheMetadata = JSON.parse(text);
          Logger.d("GitHubService", "Loaded cache metadata:", Object.keys(cacheMetadata).length, "entries");

          // Populate cachedCircularAvatars from metadata
          for (var username in cacheMetadata) {
            var entry = cacheMetadata[username];
            cachedCircularAvatars[username] = "file://" + entry.cached_path;
          }

          metadataLoaded = true;
          Logger.d("GitHubService", "Cache metadata loaded successfully");
        } else {
          Logger.d("GitHubService", "No existing cache metadata found (empty response)");
          cacheMetadata = {};
          metadataLoaded = true;
        }
      } catch (e) {
        Logger.w("GitHubService", "Failed to parse cache metadata:", e);
        cacheMetadata = {};
        metadataLoaded = true;
      }
      loadProcess.destroy();
    });

    loadProcess.exited.connect(function (exitCode) {
      if (exitCode !== 0) {
        // File doesn't exist, initialize empty
        cacheMetadata = {};
        metadataLoaded = true;
        Logger.d("GitHubService", "Initializing empty cache metadata");
      }
    });

    loadProcess.running = true;
  }

  function saveCacheMetadata() {
    Quickshell.execDetached(["mkdir", "-p", avatarCacheDir]);

    var jsonContent = JSON.stringify(cacheMetadata, null, 2);

    // Use printf with base64 encoding to safely handle special characters
    var base64Content = Qt.btoa(jsonContent); // Base64 encode

    var saveProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "echo '${base64Content}' | base64 -d > '${metadataPath}'"]
      }
    `, root, "SaveMetadata_" + Date.now());

    saveProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        Logger.d("GitHubService", "Saved cache metadata");
      } else {
        Logger.e("GitHubService", "Failed to save cache metadata, exit code:", exitCode);
      }
      saveProcess.destroy();
    });

    saveProcess.running = true;
  }

  function cacheTopContributorAvatars() {
    if (contributors.length === 0)
      return;

    // Mark that we've processed avatars for this contributor set
    avatarsCached = true;

    Quickshell.execDetached(["mkdir", "-p", avatarCacheDir]);

    // Build queue of avatars that need processing
    avatarQueue = [];
    var currentTop20 = {};

    for (var i = 0; i < Math.min(contributors.length, 20); i++) {
      var contributor = contributors[i];
      var username = contributor.login;
      var avatarUrl = contributor.avatar_url;
      var circularPath = avatarCacheDir + username + "_circular.png";

      currentTop20[username] = true;

      // Check if we need to process this avatar
      var needsProcessing = false;
      var reason = "";

      if (!cacheMetadata[username]) {
        // New user in top 20
        needsProcessing = true;
        reason = "new user";
      } else if (cacheMetadata[username].avatar_url !== avatarUrl) {
        // Avatar URL changed (user updated their GitHub avatar)
        needsProcessing = true;
        reason = "avatar URL changed";
      } else {
        // Already cached - add to map
        cachedCircularAvatars[username] = "file://" + circularPath;
      }

      if (needsProcessing) {
        Logger.d("GitHubService", "Queueing avatar for", username, "-", reason);
        avatarQueue.push({
                           username: username,
                           avatarUrl: avatarUrl,
                           circularPath: circularPath
                         });
      }
    }

    // Cleanup: Remove metadata for users no longer in top 20
    var removedUsers = [];
    for (var cachedUsername in cacheMetadata) {
      if (!currentTop20[cachedUsername]) {
        removedUsers.push(cachedUsername);

        // Delete cached circular file
        var pathToDelete = cacheMetadata[cachedUsername].cached_path;
        Quickshell.execDetached(["rm", "-f", pathToDelete]);

        delete cacheMetadata[cachedUsername];
        delete cachedCircularAvatars[cachedUsername];
      }
    }

    if (removedUsers.length > 0) {
      Logger.d("GitHubService", "Cleaned up avatars for users no longer in top 20:", removedUsers.join(", "));
      saveCacheMetadata();
    }

    // Start processing queue
    if (avatarQueue.length > 0) {
      Logger.i("GitHubService", "Processing", avatarQueue.length, "avatar(s)");
      processNextAvatar();
    } else {
      Logger.d("GitHubService", "All avatars already cached");
      cachedCircularAvatarsChanged(); // Notify AboutTab
    }
  }

  function processNextAvatar() {
    if (avatarQueue.length === 0 || isProcessingAvatars)
      return;

    isProcessingAvatars = true;
    var item = avatarQueue.shift();

    Logger.d("GitHubService", "Downloading avatar for", item.username);

    // Download original avatar
    var tempPath = avatarCacheDir + item.username + "_temp.png";
    downloadAvatar(item.avatarUrl, tempPath, function (success) {
      if (success) {
        // Render circular version
        renderCircularAvatar(tempPath, item.circularPath, item.username, item.avatarUrl);
      } else {
        Logger.e("GitHubService", "Failed to download avatar for", item.username);
        isProcessingAvatars = false;
        processNextAvatar();
      }
    });
  }

  function downloadAvatar(url, destPath, callback) {
    var downloadCmd = `curl -L -s -o '${destPath}' '${url}' || wget -q -O '${destPath}' '${url}'`;

    var downloadProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "${downloadCmd}"]
      }
    `, root, "Download_" + Date.now());

    downloadProcess.exited.connect(function (exitCode) {
      callback(exitCode === 0);
      downloadProcess.destroy();
    });

    downloadProcess.running = true;
  }

  function renderCircularAvatar(inputPath, outputPath, username, avatarUrl) {
    Logger.d("GitHubService", "Rendering circular avatar for", username);

    // Use ImageMagick to create a circular avatar with proper alpha transparency
    var convertProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["magick", "${inputPath}", "-resize", "256x256^", "-gravity", "center", "-extent", "256x256", "-alpha", "set", "(", "+clone", "-channel", "A", "-evaluate", "set", "0", "+channel", "-fill", "white", "-draw", "circle 128,128 128,0", ")", "-compose", "DstIn", "-composite", "${outputPath}"]
      }
    `, root, "Convert_" + Date.now());

    convertProcess.exited.connect(function (exitCode) {
      var success = exitCode === 0;

      if (success) {
        // Update cache metadata
        cacheMetadata[username] = {
          avatar_url: avatarUrl,
          cached_path: outputPath,
          cached_at: Date.now()
        };

        cachedCircularAvatars[username] = "file://" + outputPath;
        cachedCircularAvatarsChanged();

        saveCacheMetadata();

        Logger.d("GitHubService", "Cached circular avatar for", username);
      } else {
        Logger.e("GitHubService", "Failed to render circular avatar for", username);
      }

      // Clean up temp file
      Quickshell.execDetached(["rm", "-f", inputPath]);

      // Process next in queue
      isProcessingAvatars = false;
      processNextAvatar();

      convertProcess.destroy();
    });

    convertProcess.running = true;
  }

  // --------------------------------
  // Hook into contributors change - only process once
  onContributorsChanged: {
    if (contributors.length > 0 && !avatarsCached) {
      // Wait for metadata to load before processing
      if (metadataLoaded) {
        Qt.callLater(cacheTopContributorAvatars);
      } else {
        // Metadata not loaded yet, wait for it
        metadataLoadedWatcher.start();
      }
    }
  }

  // Wait for metadata to be loaded before caching avatars
  Timer {
    id: metadataLoadedWatcher
    interval: 100
    repeat: true
    onTriggered: {
      if (metadataLoaded && contributors.length > 0 && !avatarsCached) {
        stop();
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
