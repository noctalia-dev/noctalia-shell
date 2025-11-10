pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Core state
  property var events: ([])
  property bool loading: false
  property bool available: false
  property string lastError: ""
  property var calendars: ([])

  // Persistent cache
  property string cacheFile: Settings.cacheDir + "calendar.json"

  // Python scripts
  readonly property string checkCalendarAvailableScript: Quickshell.shellDir + '/Bin/check-calendar.py'
  readonly property string listCalendarsScript: Quickshell.shellDir + '/Bin/list-calendars.py'
  readonly property string calendarEventsScript: Quickshell.shellDir + '/Bin/calendar-events.py'

  // Cache file handling
  FileView {
    id: cacheFileView
    path: root.cacheFile
    printErrors: false

    JsonAdapter {
      id: cacheAdapter
      property var cachedEvents: ([])
      property var cachedCalendars: ([])
      property string lastUpdate: ""
    }

    onLoadFailed: {
      cacheAdapter.cachedEvents = ([])
      cacheAdapter.cachedCalendars = ([])
      cacheAdapter.lastUpdate = ""
    }

    onLoaded: {
      loadFromCache()
    }
  }

  Component.onCompleted: {
    Logger.i("Calendar", "Service started")
    loadFromCache()
    checkAvailability()
  }

  // Save cache with debounce
  Timer {
    id: saveDebounce
    interval: 1000
    onTriggered: cacheFileView.writeAdapter()
  }

  function saveCache() {
    saveDebounce.restart()
  }

  // Load events and calendars from cache
  function loadFromCache() {
    if (cacheAdapter.cachedEvents && cacheAdapter.cachedEvents.length > 0) {
      root.events = cacheAdapter.cachedEvents
      Logger.d("Calendar", `Loaded ${cacheAdapter.cachedEvents.length} cached event(s)`)
    }

    if (cacheAdapter.cachedCalendars && cacheAdapter.cachedCalendars.length > 0) {
      root.calendars = cacheAdapter.cachedCalendars
      Logger.d("Calendar", `Loaded ${cacheAdapter.cachedCalendars.length} cached calendar(s)`)
    }

    if (cacheAdapter.lastUpdate) {
      Logger.d("Calendar", `Cache last updated: ${cacheAdapter.lastUpdate}`)
    }
  }

  // Auto-refresh timer (every 5 minutes)
  Timer {
    id: refreshTimer
    interval: 300000
    running: true
    repeat: true
    onTriggered: loadEvents()
  }

  // Core functions
  function checkAvailability() {
    if (Settings.data.location.showCalendarEvents) {
      availabilityCheckProcess.running = true
    } else {
      root.available = false
    }
  }

  function loadCalendars() {
    listCalendarsProcess.running = true
  }

  function loadEvents(daysAhead = 31, daysBehind = 14) {
    if (!Settings.data.location.showCalendarEvents) {
      root.loading = false
      root.events = []
      return
    }
    if (loading)
      return

    loading = true
    lastError = ""

    const now = new Date()
    const startDate = new Date(now.getTime() - (daysBehind * 24 * 60 * 60 * 1000))
    const endDate = new Date(now.getTime() + (daysAhead * 24 * 60 * 60 * 1000))

    loadEventsProcess.startTime = Math.floor(startDate.getTime() / 1000)
    loadEventsProcess.endTime = Math.floor(endDate.getTime() / 1000)
    loadEventsProcess.running = true

    Logger.d("Calendar", `Loading events (${daysBehind} days behind, ${daysAhead} days ahead): ${startDate.toLocaleDateString()} to ${endDate.toLocaleDateString()}`)
  }

  // Helper to format date/time
  function formatDateTime(timestamp) {
    const date = new Date(timestamp * 1000)
    return Qt.formatDateTime(date, "yyyy-MM-dd hh:mm")
  }

  // Process to check for evolution-data-server libraries
  Process {
    id: availabilityCheckProcess
    running: false
    command: ["sh", "-c", "command -v python3 >/dev/null 2>&1 && python3 " + root.checkCalendarAvailableScript + " || echo 'unavailable: python3 not installed'"]

    stdout: StdioCollector {
      onStreamFinished: {
        const result = text.trim()
        root.available = result === "available"

        if (root.available) {
          Logger.i("Calendar", "EDS libraries available")
          loadCalendars()
        } else {
          Logger.w("Calendar", "EDS libraries not available: " + result)
          root.lastError = "Evolution Data Server libraries not installed"
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.d("Calendar", "Availability check error: " + text)
          root.available = false
          root.lastError = "Failed to check library availability"
        }
      }
    }
  }

  // Process to list available calendars
  Process {
    id: listCalendarsProcess
    running: false
    command: ["python3", root.listCalendarsScript]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const result = JSON.parse(text.trim())
          root.calendars = result
          cacheAdapter.cachedCalendars = result
          saveCache()

          Logger.d("Calendar", `Found ${result.length} calendar(s)`)

          // Auto-load events after discovering calendars
          // Only load if we have calendars and no cached events
          if (result.length > 0 && root.events.length === 0) {
            loadEvents()
          } else if (result.length > 0) {
            // If we already have cached events, load in background
            loadEvents()
          }
        } catch (e) {
          Logger.d("Calendar", "Failed to parse calendars: " + e)
          root.lastError = "Failed to parse calendar list"
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.d("Calendar", "List calendars error: " + text)
          root.lastError = text.trim()
        }
      }
    }
  }

  // Process to load events
  Process {
    id: loadEventsProcess
    running: false
    property int startTime: 0
    property int endTime: 0

    command: ["python3", root.calendarEventsScript, startTime.toString(), endTime.toString()]

    stdout: StdioCollector {
      onStreamFinished: {
        root.loading = false

        try {
          const result = JSON.parse(text.trim())
          root.events = result
          cacheAdapter.cachedEvents = result
          cacheAdapter.lastUpdate = new Date().toISOString()
          saveCache()

          Logger.d("Calendar", `Loaded ${result.length} event(s)`)
        } catch (e) {
          Logger.d("Calendar", "Failed to parse events: " + e)
          root.lastError = "Failed to parse events"

          // Fall back to cached events if available
          if (cacheAdapter.cachedEvents.length > 0) {
            root.events = cacheAdapter.cachedEvents
            Logger.d("Calendar", "Using cached events")
          }
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.loading = false

        if (text.trim()) {
          Logger.d("Calendar", "Load events error: " + text)
          root.lastError = text.trim()

          // Fall back to cached events if available
          if (cacheAdapter.cachedEvents.length > 0) {
            root.events = cacheAdapter.cachedEvents
            Logger.d("Calendar", "Using cached events due to error")
          }
        }
      }
    }
  }
}
