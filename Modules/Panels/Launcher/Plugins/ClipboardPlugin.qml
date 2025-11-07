import QtQuick
import Quickshell
import qs.Commons
import qs.Services

Item {
  id: root

  // Plugin metadata
  property string name: I18n.tr("plugins.clipboard")
  property var launcher: null

  // Plugin capabilities
  property bool handleSearch: false // Don't handle regular search

  // Internal state
  property bool isWaitingForData: false
  property bool gotResults: false
  property string lastSearchText: ""

  // Listen for clipboard data updates
  Connections {
    target: ClipboardService
    function onListCompleted() {
      if (gotResults && (lastSearchText === searchText)) {
        // Do not update results after the first fetch.
        // This will avoid the list resetting every 2seconds when the service updates.
        return
      }
      // Refresh results if we're waiting for data or if clipboard plugin is active
      if (isWaitingForData || (launcher && launcher.searchText.startsWith(">clip"))) {
        isWaitingForData = false
        gotResults = true
        if (launcher) {
          launcher.updateResults()
        }
      }
    }
  }

  // Initialize plugin
  function init() {
    Logger.i("ClipboardPlugin", "Initialized")
    // Pre-load clipboard data if service is active
    if (ClipboardService.active) {
      ClipboardService.list(100)
    }
  }

  // Called when launcher opens
  function onOpened() {
    isWaitingForData = true
    gotResults = false
    lastSearchText = ""

    // Refresh clipboard history when launcher opens
    if (ClipboardService.active) {
      ClipboardService.list(100)
    }
  }

  // Check if this plugin handles the command
  function handleCommand(searchText) {
    return searchText.startsWith(">clip")
  }

  // Return available commands when user types ">"
  function commands() {
    return [{
              "name": ">clip",
              "description": I18n.tr("plugins.clipboard-search-description"),
              "icon": "text-x-generic",
              "isImage": false,
              "onActivate": function () {
                launcher.setSearchText(">clip ")
              }
            }, {
              "name": ">clip clear",
              "description": I18n.tr("plugins.clipboard-clear-description"),
              "icon": "text-x-generic",
              "isImage": false,
              "onActivate": function () {
                ClipboardService.wipeAll()
                launcher.close()
              }
            }]
  }

  // Get search results
  function getResults(searchText) {
    if (!searchText.startsWith(">clip")) {
      return []
    }

    lastSearchText = searchText
    const results = []
    const query = searchText.slice(5).trim()

    // Check if clipboard service is not active
    if (!ClipboardService.active) {
      return [{
                "name": I18n.tr("plugins.clipboard-history-disabled"),
                "description": I18n.tr("plugins.clipboard-history-disabled-description"),
                "icon": "view-refresh",
                "isImage": false,
                "onActivate": function () {}
              }]
    }

    // Special command: clear
    if (query === "clear") {
      return [{
                "name": I18n.tr("plugins.clipboard-clear-history"),
                "description": I18n.tr("plugins.clipboard-clear-description-full"),
                "icon": "delete_sweep",
                "isImage": false,
                "onActivate": function () {
                  ClipboardService.wipeAll()
                  launcher.close()
                }
              }]
    }

    // Show loading state if data is being loaded
    if (ClipboardService.loading || isWaitingForData) {
      return [{
                "name": I18n.tr("plugins.clipboard-loading"),
                "description": I18n.tr("plugins.clipboard-loading-description"),
                "icon": "view-refresh",
                "isImage": false,
                "onActivate": function () {}
              }]
    }

    // Get clipboard items
    const items = ClipboardService.items || []

    // If no items and we haven't tried loading yet, trigger a load
    if (items.count === 0 && !ClipboardService.loading) {
      isWaitingForData = true
      ClipboardService.list(100)
      return [{
                "name": I18n.tr("plugins.clipboard-loading"),
                "description": I18n.tr("plugins.clipboard-loading-description"),
                "icon": "view-refresh",
                "isImage": false,
                "onActivate": function () {}
              }]
    }

    // Search clipboard items
    const searchTerm = query.toLowerCase()

    // Filter and format results
    items.forEach(function (item) {
      const preview = (item.preview || "").toLowerCase()

      // Skip if search term doesn't match
      if (searchTerm && preview.indexOf(searchTerm) === -1) {
        return
      }

      // Format the result based on type
      let entry
      if (item.isImage) {
        entry = formatImageEntry(item)
      } else {
        entry = formatTextEntry(item)
      }

      // Add activation handler
      entry.onActivate = function () {
        ClipboardService.copyToClipboard(item.id)
        launcher.close()
      }

      results.push(entry)
    })

    // Show empty state if no results
    if (results.length === 0) {
      results.push({
                     "name": searchTerm ? "No matching clipboard items" : "Clipboard is empty",
                     "description": searchTerm ? `No items containing "${query}"` : "Copy something to see it here",
                     "icon": "text-x-generic",
                     "isImage": false,
                     "onActivate": function () {// Do nothing
                     }
                   })
    }

    //Logger.i("ClipboardPlugin", `Returning ${results.length} results for query: "${query}"`)
    return results
  }

  // Helper: Format image clipboard entry
  function formatImageEntry(item) {
    const meta = parseImageMeta(item.preview)

    // The launcher's delegate will now be responsible for fetching the image data.
    // This function's role is to provide the necessary metadata for that request.
    return {
      "name": meta ? `Image ${meta.w}×${meta.h}` : "Image",
      "description": meta ? `${meta.fmt} • ${meta.size}` : item.mime || "Image data",
      "icon": "image",
      "isImage": true,
      "imageWidth": meta ? meta.w : 0,
      "imageHeight": meta ? meta.h : 0,
      "clipboardId": item.id,
      "mime": item.mime
    }
  }

  // Helper: Format text clipboard entry with preview
  function formatTextEntry(item) {
    const preview = (item.preview || "").trim()
    const lines = preview.split('\n').filter(l => l.trim())

    // Use first line as title, limit length
    let title = lines[0] || "Empty text"
    if (title.length > 60) {
      title = title.substring(0, 57) + "..."
    }

    // Use second line or character count as description
    let description = ""
    if (lines.length > 1) {
      description = lines[1]
      if (description.length > 80) {
        description = description.substring(0, 77) + "..."
      }
    } else {
      const chars = preview.length
      const words = preview.split(/\s+/).length
      description = `${chars} characters, ${words} word${words !== 1 ? 's' : ''}`
    }

    return {
      "name": title,
      "description": description,
      "icon": "text-x-generic",
      "isImage": false
    }
  }

  // Helper: Parse image metadata from preview string
  function parseImageMeta(preview) {
    const re = /\[\[\s*binary data\s+([\d\.]+\s*(?:KiB|MiB|GiB|B))\s+(\w+)\s+(\d+)x(\d+)\s*\]\]/i
    const match = (preview || "").match(re)

    if (!match) {
      return null
    }

    return {
      "size": match[1],
      "fmt": (match[2] || "").toUpperCase(),
      "w": Number(match[3]),
      "h": Number(match[4])
    }
  }

  // Public method to get image data for a clipboard item
  // This can be called by the launcher when rendering
  function getImageForItem(clipboardId) {
    return ClipboardService.getImageData ? ClipboardService.getImageData(clipboardId) : null
  }
}
