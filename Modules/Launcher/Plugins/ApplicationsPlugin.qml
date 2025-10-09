import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import "../../../Helpers/FuzzySort.js" as Fuzzysort

Item {
  property var launcher: null
  property string name: I18n.tr("plugins.applications")
  property bool handleSearch: true
  property var entries: []

  // Persistent usage tracking stored in cacheDir
  property string usageFilePath: Settings.cacheDir + "launcher_app_usage.json"

  // Debounced saver to avoid excessive IO
  Timer {
    id: saveTimer
    interval: 750
    repeat: false
    onTriggered: usageFile.writeAdapter()
  }

  FileView {
    id: usageFile
    path: usageFilePath
    printErrors: false
    watchChanges: false

    onLoadFailed: function (error) {
      if (error.toString().includes("No such file") || error === 2) {
        writeAdapter()
      }
    }

    onAdapterUpdated: saveTimer.start()

    JsonAdapter {
      id: usageAdapter
      // key: app id/command, value: integer count
      property var counts: ({})
    }
  }

  function init() {
    loadApplications()
  }

  function onOpened() {
    // Refresh apps when launcher opens
    loadApplications()
  }

  function loadApplications() {
    if (typeof DesktopEntries === 'undefined') {
      Logger.warn("ApplicationsPlugin", "DesktopEntries service not available")
      return
    }

    const allApps = DesktopEntries.applications.values || []
    entries = allApps.filter(app => app && !app.noDisplay).map(app => {
                                                                 // Add executable name property for search
                                                                 app.executableName = getExecutableName(app)
                                                                 return app
                                                               })
    Logger.log("ApplicationsPlugin", `Loaded ${entries.length} applications`)
  }

  function getExecutableName(app) {
    if (!app)
      return ""

    // Try to get executable name from command array
    if (app.command && Array.isArray(app.command) && app.command.length > 0) {
      const cmd = app.command[0]
      // Extract just the executable name from the full path
      const parts = cmd.split('/')
      const executable = parts[parts.length - 1]
      // Remove any arguments or parameters
      return executable.split(' ')[0]
    }

    // Try to get from exec property if available
    if (app.exec) {
      const parts = app.exec.split('/')
      const executable = parts[parts.length - 1]
      return executable.split(' ')[0]
    }

    // Fallback to app id (desktop file name without .desktop)
    if (app.id) {
      return app.id.replace('.desktop', '')
    }

    return ""
  }

  function getResults(query) {
    if (!entries || entries.length === 0)
      return []

    if (!query || query.trim() === "") {
      // Return all apps, optionally sorted by usage
      const favoriteApps = Settings.data.appLauncher.favoriteApps || []
      let sorted
      if (Settings.data.appLauncher.sortByMostUsed) {
        sorted = entries.slice().sort((a, b) => {
                                        // Favorites first
                                        const aFav = favoriteApps.includes(getAppKey(a))
                                        const bFav = favoriteApps.includes(getAppKey(b))
                                        if (aFav !== bFav)
                                        return aFav ? -1 : 1
                                        const ua = getUsageCount(a)
                                        const ub = getUsageCount(b)
                                        if (ub !== ua)
                                        return ub - ua
                                        return (a.name || "").toLowerCase().localeCompare((b.name || "").toLowerCase())
                                      })
      } else {
        sorted = entries.slice().sort((a, b) => {
                                        const aFav = favoriteApps.includes(getAppKey(a))
                                        const bFav = favoriteApps.includes(getAppKey(b))
                                        if (aFav !== bFav)
                                        return aFav ? -1 : 1
                                        return (a.name || "").toLowerCase().localeCompare((b.name || "").toLowerCase())
                                      })
      }
      return sorted.map(app => createResultEntry(app))
    }

    // Use fuzzy search if available, fallback to simple search
    if (typeof Fuzzysort !== 'undefined') {
      const fuzzyResults = Fuzzysort.go(query, entries, {
                                          "keys": ["name", "comment", "genericName", "executableName"],
                                          "threshold": -1000,
                                          "limit": 20
                                        })

      // Sort favorites first within fuzzy results while preserving fuzzysort order otherwise
      const favoriteApps = Settings.data.appLauncher.favoriteApps || []
      const fav = []
      const nonFav = []
      for (const r of fuzzyResults) {
        const app = r.obj
        if (favoriteApps.includes(getAppKey(app)))
          fav.push(r)
        else
          nonFav.push(r)
      }
      return fav.concat(nonFav).map(result => createResultEntry(result.obj))
    } else {
      // Fallback to simple search
      const searchTerm = query.toLowerCase()
      return entries.filter(app => {
                              const name = (app.name || "").toLowerCase()
                              const comment = (app.comment || "").toLowerCase()
                              const generic = (app.genericName || "").toLowerCase()
                              const executable = getExecutableName(app).toLowerCase()
                              return name.includes(searchTerm) || comment.includes(searchTerm) || generic.includes(searchTerm) || executable.includes(searchTerm)
                            }).sort((a, b) => {
                                      // Prioritize name matches, then executable matches
                                      const aName = a.name.toLowerCase()
                                      const bName = b.name.toLowerCase()
                                      const aExecutable = getExecutableName(a).toLowerCase()
                                      const bExecutable = getExecutableName(b).toLowerCase()
                                      const aStarts = aName.startsWith(searchTerm)
                                      const bStarts = bName.startsWith(searchTerm)
                                      const aExecStarts = aExecutable.startsWith(searchTerm)
                                      const bExecStarts = bExecutable.startsWith(searchTerm)

                                      // Prioritize name matches first
                                      if (aStarts && !bStarts)
                                      return -1
                                      if (!aStarts && bStarts)
                                      return 1

                                      // Then prioritize executable matches
                                      if (aExecStarts && !bExecStarts)
                                      return -1
                                      if (!aExecStarts && bExecStarts)
                                      return 1

                                      return aName.localeCompare(bName)
                                    }).slice(0, 20).map(app => createResultEntry(app))
    }
  }

  function createResultEntry(app) {
    return {
      "appId": getAppKey(app),
      "name": app.name || "Unknown",
      "description": app.genericName || app.comment || "",
      "icon": app.icon || "application-x-executable",
      "isImage": false,
      "onActivate": function () {
        // Close the launcher/NPanel immediately without any animations.
        // Ensures we are not preventing the future focusing of the app
        launcher.close()

        Logger.log("ApplicationsPlugin", `Launching: ${app.name}`)
        // Record usage and persist asynchronously
        if (Settings.data.appLauncher.sortByMostUsed)
          recordUsage(app)
        if (Settings.data.appLauncher.useApp2Unit && app.id) {
          Logger.log("ApplicationsPlugin", `Using app2unit for: ${app.id}`)
          if (app.runInTerminal)
            Quickshell.execDetached(["app2unit", "--", app.id + ".desktop"])
          else
            Quickshell.execDetached(["app2unit", "--"].concat(app.command))
        } else {
          // Fallback logic when app2unit is not used
          if (app.runInTerminal) {
            // If app.execute() fails for terminal apps, we handle it manually.
            Logger.log("ApplicationsPlugin", "Executing terminal app manually: " + app.name)
            const terminal = Settings.data.appLauncher.terminalCommand.split(" ")
            const command = terminal.concat(app.command)
            Quickshell.execDetached(command)
          } else if (app.execute) {
            // Default execution for GUI apps
            app.execute()
          } else {
            Logger.log("ApplicationsPlugin", `Could not launch: ${app.name}. No valid launch method.`)
          }
        }
      }
    }
  }

  // -------------------------
  // Usage tracking helpers
  function getAppKey(app) {
    if (app && app.id)
      return String(app.id)
    if (app && app.command && app.command.join)
      return app.command.join(" ")
    return String(app && app.name ? app.name : "unknown")
  }

  function getUsageCount(app) {
    const key = getAppKey(app)
    const m = usageAdapter && usageAdapter.counts ? usageAdapter.counts : null
    if (!m)
      return 0
    const v = m[key]
    return typeof v === 'number' && isFinite(v) ? v : 0
  }

  function recordUsage(app) {
    const key = getAppKey(app)
    if (!usageAdapter.counts)
      usageAdapter.counts = ({})
    const current = getUsageCount(app)
    usageAdapter.counts[key] = current + 1
    // Trigger save via debounced timer
    saveTimer.restart()
  }
}
