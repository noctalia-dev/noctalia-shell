pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services

Singleton {
  id: root

  // Compositor detection
  property bool isHyprland: false
  property bool isNiri: false

  // Generic workspace and window data
  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1

  // Generic events
  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal hibernateRequested   // <-- added signal

  // Backend service loader
  property var backend: null

  Component.onCompleted: {
    detectCompositor()
  }

  function detectCompositor() {
    const hyprlandSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    if (hyprlandSignature && hyprlandSignature.length > 0) {
      isHyprland = true
      isNiri = false
      backendLoader.sourceComponent = hyprlandComponent
    } else {
      // Default to Niri
      isHyprland = false
      isNiri = true
      backendLoader.sourceComponent = niriComponent
    }
  }

  Loader {
    id: backendLoader
    onLoaded: {
      if (item) {
        root.backend = item
        setupBackendConnections()
        backend.initialize()
      }
    }
  }

  // Hyprland backend component
  Component {
    id: hyprlandComponent
    HyprlandService {
      id: hyprlandBackend
    }
  }

  // Niri backend component
  Component {
    id: niriComponent
    NiriService {
      id: niriBackend
    }
  }

  function setupBackendConnections() {
    if (!backend)
      return

    // Connect backend signals to facade signals
    backend.workspaceChanged.connect(() => {
                                       // Sync workspaces when they change
                                       syncWorkspaces()
                                       // Forward the signal
                                       workspaceChanged()
                                     })

    backend.activeWindowChanged.connect(activeWindowChanged)
    backend.windowListChanged.connect(() => {
                                        // Sync windows when they change
                                        windows = backend.windows
                                        // Forward the signal
                                        windowListChanged()
                                      })

    // Property bindings
    backend.focusedWindowIndexChanged.connect(() => {
                                                focusedWindowIndex = backend.focusedWindowIndex
                                              })

    // Initial sync
    syncWorkspaces()
    windows = backend.windows
    focusedWindowIndex = backend.focusedWindowIndex
  }

  function syncWorkspaces() {
    workspaces.clear()
    const ws = backend.workspaces
    for (var i = 0; i < ws.count; i++) {
      workspaces.append(ws.get(i))
    }
    // Emit signal to notify listeners that workspace list has been updated
    workspacesChanged()
  }

  // Get window title for focused window
  function getFocusedWindowTitle() {
    if (focusedWindowIndex >= 0 && focusedWindowIndex < windows.length) {
      return windows[focusedWindowIndex].title || ""
    }
    return ""
  }

  // Generic workspace switching
  function switchToWorkspace(workspaceId) {
    if (backend && backend.switchToWorkspace) {
      backend.switchToWorkspace(workspaceId)
    } else {
      Logger.warn("Compositor", "No backend available for workspace switching")
    }
  }

  // Get current workspace
  function getCurrentWorkspace() {
    for (var i = 0; i < workspaces.count; i++) {
      const ws = workspaces.get(i)
      if (ws.isFocused) {
        return ws
      }
    }
    return null
  }

  // Get focused window
  function getFocusedWindow() {
    if (focusedWindowIndex >= 0 && focusedWindowIndex < windows.length) {
      return windows[focusedWindowIndex]
    }
    return null
  }

  // Session management
  function logout() {
    if (backend && backend.logout) {
      backend.logout()
    } else {
      Logger.warn("Compositor", "No backend available for logout")
    }
  }

  function shutdown() {
    Quickshell.execDetached(["systemctl", "poweroff"])
  }

  function reboot() {
    Quickshell.execDetached(["systemctl", "reboot"])
  }

  function suspend() {
    Quickshell.execDetached(["systemctl", "suspend"])
  }

  function hibernate() {
    hibernateRequested() // <-- emit signal if someone wants to listen
    Quickshell.execDetached(["systemctl", "hibernate"])
  }
}
