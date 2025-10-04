import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Wayland
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

  // I3-specific properties
  property bool initialized: false

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
      I3.refreshWorkspaces()
      Qt.callLater(() => {
                     safeUpdateWorkspaces()
                     safeUpdateWindows()
                   })
      initialized = true
      Logger.log("SwayService", "Initialized successfully")
    } catch (e) {
      Logger.error("SwayService", "Failed to initialize:", e)
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

      if (!I3.workspaces || !I3.workspaces.values) {
        return
      }

      const hlWorkspaces = I3.workspaces.values

      for (var i = 0; i < hlWorkspaces.length; i++) {
        const ws = hlWorkspaces[i]
        if (!ws || ws.id < 1)
          continue

        const wsData = {
          "id": i,
          "idx": ws.id,
          "name": ws.name || "",
          "output": (ws.monitor && ws.monitor.name) ? ws.monitor.name : "",
          "isActive": ws.active === true,
          "isFocused": ws.focused === true,
          "isUrgent": ws.urgent === true,
          "isOccupied": true,
          "handle": ws
        }

        workspaces.append(wsData)
      }
    } catch (e) {
      Logger.error("SwayService", "Error updating workspaces:", e)
    }
  }

  // Safe window update
  function safeUpdateWindows() {
    try {
      const windowsList = []

      if (!ToplevelManager.toplevels || !ToplevelManager.toplevels.values) {
        windows = []
        focusedWindowIndex = -1
        return
      }

      const hlToplevels = ToplevelManager.toplevels.values
      let newFocusedIndex = -1

      for (var i = 0; i < hlToplevels.length; i++) {
        const toplevel = hlToplevels[i]
        if (!toplevel)
          continue

        const windowData = extractWindowData(toplevel)
        if (windowData) {
          windowsList.push(windowData)

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
      Logger.error("SwayService", "Error updating windows:", e)
    }
  }

  // Extract window data safely from a toplevel
  function extractWindowData(toplevel) {
    if (!toplevel)
      return null

    try {
      // Safely extract properties
      const appId = extractAppId(toplevel)
      const title = safeGetProperty(toplevel, "title", "")
      const focused = toplevel.activated === true

      return {
        "title": title,
        "appId": appId,
        "isFocused": focused,
        "handle": toplevel
      }
    } catch (e) {
      return null
    }
  }

  // Extract app ID from various possible sources
  function extractAppId(toplevel) {
    if (!toplevel)
      return ""

    return toplevel.appId;
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

  // Connections to I3
  Connections {
    target: I3.workspaces
    enabled: initialized
    function onValuesChanged() {
      safeUpdateWorkspaces()
      workspaceChanged()
    }
  }

  Connections {
    target: ToplevelManager
    enabled: initialized
    function onActiveToplevelChanged() {
      updateTimer.restart()
    }
  }

  Connections {
    target: I3
    enabled: initialized
    function onRawEvent(event) {
      safeUpdateWorkspaces()
      workspaceChanged()
      updateTimer.restart()
    }
  }

  // Public functions
  function switchToWorkspace(workspace) {
    try {
      workspace.handle.activate()
    } catch (e) {
      Logger.error("SwayService", "Failed to switch workspace:", e)
    }
  }

  function focusWindow(window) {
    try {
      window.handle.activate()
    } catch (e) {
      Logger.error("SwayService", "Failed to switch window:", e)
    }
  }

  function closeWindow(window) {
    try {
      window.handle.close()
    } catch (e) {
      Logger.error("SwayService", "Failed to close window:", e)
    }
  }

  function logout() {
    try {
      Quickshell.execDetached(["swaymsg", "exit"])
    } catch (e) {
      Logger.error("SwayService", "Failed to logout:", e)
    }
  }
}
