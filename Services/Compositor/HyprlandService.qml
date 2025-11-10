import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons

Item {
  id: root

  // Properties that match the facade interface
  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1

  // Signals that match the facade interface
  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  // Hyprland-specific properties
  property bool initialized: false
  property var workspaceCache: ({})
  property var windowCache: ({})

  // Debounce timer for updates
  Timer {
    id: updateTimer
    interval: 50
    repeat: false
    onTriggered: safeUpdate()
  }

  // Initialization
  function initialize() {
    if (initialized)
      return

    try {
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
      Qt.callLater(() => {
                     safeUpdateWorkspaces()
                     safeUpdateWindows()
                     queryDisplayScales()
                   })
      initialized = true
      Logger.i("HyprlandService", "Service started")
    } catch (e) {
      Logger.e("HyprlandService", "Failed to initialize:", e)
    }
  }

  // Query display scales
  function queryDisplayScales() {
    hyprlandMonitorsProcess.running = true
  }

  // Hyprland monitors process for display scale detection
  // Hyprland monitors process for display scale detection
  Process {
    id: hyprlandMonitorsProcess
    running: false
    command: ["hyprctl", "monitors", "-j"]

    property string accumulatedOutput: ""

    stdout: SplitParser {
      onRead: function (line) {
        // Accumulate lines instead of parsing each one
        hyprlandMonitorsProcess.accumulatedOutput += line
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0 || !accumulatedOutput) {
        Logger.e("HyprlandService", "Failed to query monitors, exit code:", exitCode)
        accumulatedOutput = ""
        return
      }

      try {
        const monitorsData = JSON.parse(accumulatedOutput)
        const scales = {}

        for (const monitor of monitorsData) {
          if (monitor.name) {
            scales[monitor.name] = {
              "name": monitor.name,
              "scale": monitor.scale || 1.0,
              "width": monitor.width || 0,
              "height": monitor.height || 0,
              "refresh_rate": monitor.refreshRate || 0,
              "x": monitor.x || 0,
              "y": monitor.y || 0,
              "active_workspace": monitor.activeWorkspace ? monitor.activeWorkspace.id : -1,
              "vrr": monitor.vrr || false,
              "focused": monitor.focused || false
            }
          }
        }

        // Notify CompositorService (it will emit displayScalesChanged)
        if (CompositorService && CompositorService.onDisplayScalesUpdated) {
          CompositorService.onDisplayScalesUpdated(scales)
        }
      } catch (e) {
        Logger.e("HyprlandService", "Failed to parse monitors:", e)
      } finally {
        // Clear accumulated output for next query
        accumulatedOutput = ""
      }
    }
  }
  // Safe update wrapper
  function safeUpdate() {
    safeUpdateWindows()
    safeUpdateWorkspaces()
    windowListChanged()
  }

  // Safe workspace update
  function safeUpdateWorkspaces() {
    try {
      workspaces.clear()
      workspaceCache = {}

      if (!Hyprland.workspaces || !Hyprland.workspaces.values) {
        return
      }

      const hlWorkspaces = Hyprland.workspaces.values
      const occupiedIds = getOccupiedWorkspaceIds()

      for (var i = 0; i < hlWorkspaces.length; i++) {
        const ws = hlWorkspaces[i]
        if (!ws || ws.id < 1)
          continue

        const wsData = {
          "id": ws.id,
          "idx": ws.id,
          "name": ws.name || "",
          "output": (ws.monitor && ws.monitor.name) ? ws.monitor.name : "",
          "isActive": ws.active === true,
          "isFocused": ws.focused === true,
          "isUrgent": ws.urgent === true,
          "isOccupied": occupiedIds[ws.id] === true
        }

        workspaceCache[ws.id] = wsData
        workspaces.append(wsData)
      }
    } catch (e) {
      Logger.e("HyprlandService", "Error updating workspaces:", e)
    }
  }

  // Get occupied workspace IDs safely
  function getOccupiedWorkspaceIds() {
    const occupiedIds = {}

    try {
      if (!Hyprland.toplevels || !Hyprland.toplevels.values) {
        return occupiedIds
      }

      const hlToplevels = Hyprland.toplevels.values
      for (var i = 0; i < hlToplevels.length; i++) {
        const toplevel = hlToplevels[i]
        if (!toplevel)
          continue

        try {
          const wsId = toplevel.workspace ? toplevel.workspace.id : null
          if (wsId !== null && wsId !== undefined) {
            occupiedIds[wsId] = true
          }
        } catch (e) {

          // Ignore individual toplevel errors
        }
      }
    } catch (e) {

      // Return empty if we can't determine occupancy
    }

    return occupiedIds
  }

  // Safe window update
  function safeUpdateWindows() {
    try {
      const windowsList = []
      windowCache = {}

      if (!Hyprland.toplevels || !Hyprland.toplevels.values) {
        windows = []
        focusedWindowIndex = -1
        return
      }

      const hlToplevels = Hyprland.toplevels.values
      let newFocusedIndex = -1

      for (var i = 0; i < hlToplevels.length; i++) {
        const toplevel = hlToplevels[i]
        if (!toplevel)
          continue

        const windowData = extractWindowData(toplevel)
        if (windowData) {
          windowsList.push(windowData)
          windowCache[windowData.id] = windowData

          if (windowData.isFocused) {
            newFocusedIndex = windowsList.length - 1
          }
        }
      }

      windows = windowsList

      if (newFocusedIndex !== focusedWindowIndex) {
        focusedWindowIndex = newFocusedIndex
        activeWindowChanged()
      }
    } catch (e) {
      Logger.e("HyprlandService", "Error updating windows:", e)
    }
  }

  // Extract window data safely from a toplevel
  function extractWindowData(toplevel) {
    if (!toplevel)
      return null

    try {
      // Safely extract properties
      const windowId = safeGetProperty(toplevel, "address", "")
      if (!windowId)
        return null

      const appId = getAppId(toplevel)
      const title = getAppTitle(toplevel)
      const wsId = toplevel.workspace ? toplevel.workspace.id : null
      const focused = toplevel.activated === true
      const output = toplevel.monitor?.name || ""

      return {
        "id": windowId,
        "title": title,
        "appId": appId,
        "workspaceId": wsId || -1,
        "isFocused": focused,
        "output": output
      }
    } catch (e) {
      return null
    }
  }

  function getAppTitle(toplevel) {
    try {
      var title = toplevel.wayland.title
      if (title)
        return title
    } catch (e) {

    }

    return safeGetProperty(toplevel, "title", "")
  }

  function getAppId(toplevel) {
    if (!toplevel)
      return ""

    var appId = ""

    // Try the wayland object first!
    // From my (Lemmy) testing it works fine so we could probably get rid of all the other attempts below.
    // Leaving them in for now, just in case...
    try {
      appId = toplevel.wayland.appId
      if (appId)
        return appId
    } catch (e) {

    }

    // Try direct properties
    appId = safeGetProperty(toplevel, "class", "")
    if (appId)
      return appId

    appId = safeGetProperty(toplevel, "initialClass", "")
    if (appId)
      return appId

    appId = safeGetProperty(toplevel, "appId", "")
    if (appId)
      return appId

    // Try lastIpcObject
    try {
      const ipcData = toplevel.lastIpcObject
      if (ipcData) {
        return String(ipcData.class || ipcData.initialClass || ipcData.appId || ipcData.wm_class || "")
      }
    } catch (e) {

    }

    return ""
  }

  // Safe property getter
  function safeGetProperty(obj, prop, defaultValue) {
    try {
      const value = obj[prop]
      if (value !== undefined && value !== null) {
        return String(value)
      }
    } catch (e) {

      // Property access failed
    }
    return defaultValue
  }

  // Connections to Hyprland
  Connections {
    target: Hyprland.workspaces
    enabled: initialized
    function onValuesChanged() {
      safeUpdateWorkspaces()
      workspaceChanged()
    }
  }

  Connections {
    target: Hyprland.toplevels
    enabled: initialized
    function onValuesChanged() {
      updateTimer.restart()
    }
  }

  Connections {
    target: Hyprland
    enabled: initialized
    function onRawEvent(event) {
      Hyprland.refreshWorkspaces()
      safeUpdateWorkspaces()
      workspaceChanged()
      updateTimer.restart()

      const monitorsEvents = ["configreloaded", "monitoradded", "monitorremoved", "monitoraddedv2", "monitorremovedv2"]
      if (monitorsEvents.includes(event.name)) {
        Qt.callLater(queryDisplayScales)
      }
    }
  }

  // Public functions
  function switchToWorkspace(workspace) {
    try {
      Hyprland.dispatch(`workspace ${workspace.idx}`)
    } catch (e) {
      Logger.e("HyprlandService", "Failed to switch workspace:", e)
    }
  }

  function focusWindow(window) {
    try {
      Hyprland.dispatch(`focuswindow address:0x${window.id.toString()}`)
    } catch (e) {
      Logger.e("HyprlandService", "Failed to switch window:", e)
    }
  }

  function closeWindow(window) {
    try {
      Hyprland.dispatch(`killwindow address:0x${window.id}`)
    } catch (e) {
      Logger.e("HyprlandService", "Failed to close window:", e)
    }
  }

  function logout() {
    try {
      Quickshell.execDetached(["hyprctl", "dispatch", "exit"])
    } catch (e) {
      Logger.e("HyprlandService", "Failed to logout:", e)
    }
  }
}
