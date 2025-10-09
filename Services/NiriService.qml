import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  // Sorts floating windows after scrolling ones
  property int floatingWindowPosition: Number.MAX_SAFE_INTEGER

  // Properties that match the facade interface
  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1

  property bool overviewActive: false

  // Signals that match the facade interface
  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged

  // Initialization
  function initialize() {
    niriEventStream.running = true
    updateWorkspaces()
    updateWindows()
    Logger.log("NiriService", "Initialized successfully")
  }

  // Update workspaces
  function updateWorkspaces() {
    niriWorkspaceProcess.running = true
  }

  // Update windows
  function updateWindows() {
    niriWindowsProcess.running = true
  }

  // Niri workspace process
  Process {
    id: niriWorkspaceProcess
    running: false
    command: ["niri", "msg", "--json", "workspaces"]

    stdout: SplitParser {
      onRead: function (line) {
        try {
          const workspacesData = JSON.parse(line)
          const workspacesList = []

          for (const ws of workspacesData) {
            workspacesList.push({
                                  "id": ws.id,
                                  "idx": ws.idx,
                                  "name": ws.name || "",
                                  "output": ws.output || "",
                                  "isFocused": ws.is_focused === true,
                                  "isActive": ws.is_active === true,
                                  "isUrgent": ws.is_urgent === true,
                                  "isOccupied": ws.active_window_id ? true : false
                                })
          }

          // Sort workspaces by output, then by index
          workspacesList.sort((a, b) => {
                                if (a.output !== b.output) {
                                  return a.output.localeCompare(b.output)
                                }
                                return a.idx - b.idx
                              })

          // Update the workspaces ListModel
          workspaces.clear()
          for (var i = 0; i < workspacesList.length; i++) {
            workspaces.append(workspacesList[i])
          }

          workspaceChanged()
        } catch (e) {
          Logger.error("NiriService", "Failed to parse workspaces:", e, line)
        }
      }
    }
  }

  // Niri windows process (for initial load)
  Process {
    id: niriWindowsProcess
    running: false
    command: ["niri", "msg", "--json", "windows"]

    stdout: SplitParser {
      onRead: function (line) {
        try {
          const windowsData = JSON.parse(line)
          recollectWindows(windowsData)
        } catch (e) {
          Logger.error("NiriService", "Failed to parse windows:", e, line)
        }
      }
    }
  }

  // Niri event stream process
  Process {
    id: niriEventStream
    running: false
    command: ["niri", "msg", "--json", "event-stream"]

    stdout: SplitParser {
      onRead: data => {
                try {
                  const event = JSON.parse(data.trim())

                  if (event.WorkspacesChanged) {
                    updateWorkspaces()
                  } else if (event.WindowOpenedOrChanged) {
                    handleWindowOpenedOrChanged(event.WindowOpenedOrChanged)
                  } else if (event.WindowClosed) {
                    handleWindowClosed(event.WindowClosed)
                  } else if (event.WindowsChanged) {
                    handleWindowsChanged(event.WindowsChanged)
                  } else if (event.WorkspaceActivated) {
                    updateWorkspaces()
                  } else if (event.WindowFocusChanged) {
                    handleWindowFocusChanged(event.WindowFocusChanged)
                  } else if (event.WindowLayoutsChanged) {
                    handleWindowLayoutsChanged(event.WindowLayoutsChanged)
                  } else if (event.OverviewOpenedOrClosed) {
                    handleOverviewOpenedOrClosed(event.OverviewOpenedOrClosed)
                  }
                } catch (e) {
                  Logger.error("NiriService", "Error parsing event stream:", e, data)
                }
              }
    }
  }

  // Utility functions
  function getWindowPosition(layout) {
    if (layout.pos_in_scrolling_layout) {
      return {
        "x": layout.pos_in_scrolling_layout[0],
        "y": layout.pos_in_scrolling_layout[1]
      }
    } else {
      return {
        "x": floatingWindowPosition,
        "y": floatingWindowPosition
      }
    }
  }

  function getWindowOutput(win) {
    for (var i = 0; i < workspaces.count; i++) {
      if (workspaces.get(i).id === win.workspace_id) {
        return workspaces.get(i).output
      }
    }
    return null
  }

  function getWindowData(win) {
    return {
      "id": win.id,
      "title": win.title || "",
      "appId": win.app_id || "",
      "workspaceId": win.workspace_id || -1,
      "isFocused": win.is_focused === true,
      "output": getWindowOutput(win) || "",
      "position": getWindowPosition(win.layout)
    }
  }

  // Sort windows
  // 1. by workspace ID
  // 2. by position X
  // 3. by position Y
  function compareWindows(a, b) {
    if (a.workspaceId !== b.workspaceId) {
      return a.workspaceId - b.workspaceId
    }
    if (a.position.x !== b.position.x) {
      return a.position.x - b.position.x
    }
    return a.position.y - b.position.y
  }

  function recollectWindows(windowsData) {
    const windowsList = []
    for (const win of windowsData) {
      windowsList.push(getWindowData(win))
    }
    windowsList.sort(compareWindows)
    windows = windowsList
    windowListChanged()

    focusedWindowIndex = -1
    for (var i = 0; i < windowsList.length; i++) {
      if (windowsList[i].isFocused) {
        focusedWindowIndex = i
        break
      }
    }
    activeWindowChanged()
  }

  // Event handlers
  function handleWindowOpenedOrChanged(eventData) {
    try {
      const windowData = eventData.window
      const existingIndex = windows.findIndex(w => w.id === windowData.id)
      const newWindow = getWindowData(windowData)

      if (existingIndex >= 0) {
        // Update existing window
        windows[existingIndex] = newWindow
      } else {
        // Add new window
        windows.push(newWindow)
      }
      windows.sort(compareWindows)

      // Update focused window index if this window is focused
      if (newWindow.isFocused) {
        const oldFocusedIndex = focusedWindowIndex
        focusedWindowIndex = windows.findIndex(w => w.id === windowData.id)

        // Only emit activeWindowChanged if the focused window actually changed
        if (oldFocusedIndex !== focusedWindowIndex) {
          if (oldFocusedIndex >= 0 && oldFocusedIndex < windows.length) {
            windows[oldFocusedIndex].isFocused = false
          }
          activeWindowChanged()
        }
      }

      windowListChanged()
    } catch (e) {
      Logger.error("NiriService", "Error handling WindowOpenedOrChanged:", e)
    }
  }

  function handleWindowClosed(eventData) {
    try {
      const windowId = eventData.id
      const windowIndex = windows.findIndex(w => w.id === windowId)

      if (windowIndex >= 0) {
        // If this was the focused window, clear focus
        if (windowIndex === focusedWindowIndex) {
          focusedWindowIndex = -1
          activeWindowChanged()
        } else if (focusedWindowIndex > windowIndex) {
          // Adjust focused window index if needed
          focusedWindowIndex--
        }

        // Remove the window
        windows.splice(windowIndex, 1)
        windowListChanged()
      }
    } catch (e) {
      Logger.error("NiriService", "Error handling WindowClosed:", e)
    }
  }

  function handleWindowsChanged(eventData) {
    try {
      const windowsData = eventData.windows
      recollectWindows(windowsData)
    } catch (e) {
      Logger.error("NiriService", "Error handling WindowsChanged:", e)
    }
  }

  function handleWindowFocusChanged(eventData) {
    try {
      const focusedId = eventData.id

      if (windows[focusedWindowIndex]) {
        windows[focusedWindowIndex].isFocused = false
      }

      if (focusedId) {
        const newIndex = windows.findIndex(w => w.id === focusedId)

        if (newIndex >= 0 && newIndex < windows.length) {
          windows[newIndex].isFocused = true
        }

        focusedWindowIndex = newIndex >= 0 ? newIndex : -1
      } else {
        focusedWindowIndex = -1
      }

      activeWindowChanged()
    } catch (e) {
      Logger.error("NiriService", "Error handling WindowFocusChanged:", e)
    }
  }

  function handleWindowLayoutsChanged(eventData) {
    try {
      for (const change of eventData.changes) {
        const windowId = change[0]
        const layout = change[1]
        const window = windows.find(w => w.id === windowId)
        if (window) {
          window.position = getWindowPosition(layout)
        }
      }

      windows.sort(compareWindows)

      windowListChanged()
    } catch (e) {
      Logger.error("NiriService", "Error handling WindowLayoutChanged:", e)
    }
  }

  function handleOverviewOpenedOrClosed(eventData) {
    try {
      overviewActive = eventData.is_open
      Logger.log("NiriService", "Overview opened or closed:", eventData.is_open)
    } catch (e) {
      Logger.error("NiriService", "Error handling OverviewOpenedOrClosed:", e)
    }
  }

  // Public functions
  function switchToWorkspace(workspace) {
    try {
      Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", workspace.idx.toString()])
    } catch (e) {
      Logger.error("NiriService", "Failed to switch workspace:", e)
    }
  }

  function focusWindow(window) {
    try {
      Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", window.id.toString()])
    } catch (e) {
      Logger.error("NiriService", "Failed to switch window:", e)
    }
  }

  function closeWindow(window) {
    try {
      Quickshell.execDetached(["niri", "msg", "action", "close-window", "--id", window.id.toString()])
    } catch (e) {
      Logger.error("NiriService", "Failed to close window:", e)
    }
  }

  function logout() {
    try {
      Quickshell.execDetached(["niri", "msg", "action", "quit", "--skip-confirmation"])
    } catch (e) {
      Logger.error("NiriService", "Failed to logout:", e)
    }
  }
}
