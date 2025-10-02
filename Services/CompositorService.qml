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
  property ListModel windows: ListModel {}
  property int focusedWindowIndex: -1

  // Generic events
  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged

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

    backend.activeWindowChanged.connect(() => {
                                          // Sync active window when it changes
                                          // TODO: Avoid re-syncing all windows
                                          syncWindows()
                                          // Forward the signal
                                          activeWindowChanged()
                                        })

    backend.windowListChanged.connect(() => {
                                        // Sync windows when they change
                                        syncWindows()
                                        // Forward the signal
                                        windowListChanged()
                                      })

    // Property bindings
    backend.focusedWindowIndexChanged.connect(() => {
                                                focusedWindowIndex = backend.focusedWindowIndex
                                              })

    // Initial sync
    syncWorkspaces()
    syncWindows()
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

  function syncWindows() {
    windows.clear()
    const ws = backend.windows
    for (var i = 0; i < ws.length; i++) {
      windows.append(ws[i])
    }
    // Emit signal to notify listeners that workspace list has been updated
    windowListChanged()
  }

  // Get focused window
  function getFocusedWindow() {
    if (focusedWindowIndex >= 0 && focusedWindowIndex < windows.count) {
      return windows.get(focusedWindowIndex)
    }
    return null
  }

  // Get focused window title
  function getFocusedWindowTitle() {
    if (focusedWindowIndex >= 0 && focusedWindowIndex < windows.count) {
      return windows.get(focusedWindowIndex).title || ""
    }
    return ""
  }

  // Generic workspace switching
  function switchToWorkspace(workspace) {
    if (backend && backend.switchToWorkspace) {
      backend.switchToWorkspace(workspace)
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

  // Get active workspaces
  function getActiveWorkspaces() {
    const activeWorkspaces = []
    for (var i = 0; i < workspaces.count; i++) {
      const ws = workspaces.get(i)
      if (ws.isActive) {
        activeWorkspaces.push(ws)
      }
    }
    return activeWorkspaces
  }

  // Set focused window
  function focusWindow(window) {
    if (backend && backend.focusWindow) {
      backend.focusWindow(window)
    } else {
      Logger.warn("Compositor", "No backend available for window focus")
    }
  }

  // Close window
  function closeWindow(window) {
    if (backend && backend.closeWindow) {
      backend.closeWindow(window)
    } else {
      Logger.warn("Compositor", "No backend available for window closing")
    }
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
    Quickshell.execDetached(["shutdown", "-h", "now"])
  }

  function reboot() {
    Quickshell.execDetached(["reboot"])
  }

  function suspend() {
    Quickshell.execDetached(["systemctl", "suspend"])
  }

  function lockAndSuspend() {
    try {
      if (PanelService && PanelService.lockScreen && !PanelService.lockScreen.active) {
        PanelService.lockScreen.active = true
      }
    } catch (e) {
      Logger.warn("Compositor", "Failed to activate lock screen before suspend: " + e)
    }
    // Queue suspend to the next event loop cycle to allow lock UI to render
    Qt.callLater(suspend)
  }
}
