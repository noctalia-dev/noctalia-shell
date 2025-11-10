pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// GitHub API logic and caching
Singleton {
  id: root

  property string githubDataFile: Quickshell.env("NOCTALIA_GITHUB_FILE") || (Settings.cacheDir + "github.json")
  property int githubUpdateFrequency: 60 * 60 // 1 hour expressed in seconds
  property bool isFetchingData: false
  readonly property alias data: adapter // Used to access via GitHubService.data.xxx.yyy

  // Public properties for easy access
  property string latestVersion: I18n.tr("system.unknown-version")
  property var contributors: []

  FileView {
    id: githubDataFileView
    path: githubDataFile
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    Component.onCompleted: {
      reload()
    }
    onLoaded: {
      loadFromCache()
    }
    onLoadFailed: function (error) {
      if (error.toString().includes("No such file") || error === 2) {
        // Fetch data after a short delay to ensure file is created
        Qt.callLater(() => {
                       fetchFromGitHub()
                     })
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
  function loadFromCache() {
    const now = Time.timestamp
    if (!data.timestamp || (now >= data.timestamp + githubUpdateFrequency)) {
      Logger.d("GitHub", "Cache expired or missing, fetching new data")
      fetchFromGitHub()
      return
    }
    Logger.d("GitHub", "Loading cached GitHub data (age:", Math.round((now - data.timestamp) / 60), "minutes)")

    if (data.version) {
      root.latestVersion = data.version
    }
    if (data.contributors) {
      root.contributors = data.contributors
    }
  }

  // --------------------------------
  function fetchFromGitHub() {
    if (isFetchingData) {
      Logger.w("GitHub", "GitHub data is still fetching")
      return
    }

    isFetchingData = true
    versionProcess.running = true
    contributorsProcess.running = true
  }

  // --------------------------------
  function saveData() {
    data.timestamp = Time.timestamp
    Logger.d("GitHub", "Saving data to cache file:", githubDataFile)
    Logger.d("GitHub", "Data to save - version:", data.version, "contributors:", data.contributors.length)

    // Ensure cache directory exists
    Quickshell.execDetached(["mkdir", "-p", Settings.cacheDir])

    Qt.callLater(() => {
                   // Use direct ID reference to the FileView
                   githubDataFileView.writeAdapter()
                   Logger.d("GitHub", "Cache file written successfully")
                 })
  }

  // --------------------------------
  function resetCache() {
    data.version = I18n.tr("system.unknown-version")
    data.contributors = []
    data.timestamp = 0

    // Try to fetch immediately
    fetchFromGitHub()
  }

  Process {
    id: versionProcess

    command: ["curl", "-s", "https://api.github.com/repos/noctalia-dev/noctalia-shell/releases/latest"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const response = text
          if (response && response.trim()) {
            const data = JSON.parse(response)
            if (data.tag_name) {
              const version = data.tag_name
              root.data.version = version
              root.latestVersion = version
              Logger.d("GitHub", "Latest version fetched from GitHub:", version)
            } else {
              Logger.w("GitHub", "No tag_name in GitHub response")
            }
          } else {
            Logger.w("GitHub", "Empty response from GitHub API")
          }
        } catch (e) {
          Logger.e("GitHub", "Failed to parse version:", e)
        }

        // Check if both processes are done
        checkAndSaveData()
      }
    }
  }

  Process {
    id: contributorsProcess

    command: ["curl", "-s", "https://api.github.com/repos/noctalia-dev/noctalia-shell/contributors?per_page=100"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const response = text
          Logger.d("GitHub", "Raw contributors response length:", response ? response.length : 0)
          if (response && response.trim()) {
            const data = JSON.parse(response)
            Logger.d("GitHub", "Parsed contributors data type:", typeof data, "length:", Array.isArray(data) ? data.length : "not array")
            root.data.contributors = data || []
            root.contributors = root.data.contributors
            Logger.d("GitHub", "Contributors fetched from GitHub:", root.contributors.length)
          } else {
            Logger.w("GitHub", "Empty response from GitHub API for contributors")
            root.data.contributors = []
            root.contributors = []
          }
        } catch (e) {
          Logger.e("GitHub", "Failed to parse contributors:", e)
          root.data.contributors = []
          root.contributors = []
        }

        // Check if both processes are done
        checkAndSaveData()
      }
    }
  }

  // --------------------------------
  function checkAndSaveData() {
    // Only save when both processes are finished
    if (!versionProcess.running && !contributorsProcess.running) {
      root.isFetchingData = false
      root.saveData()
    }
  }
}
