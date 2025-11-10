pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Compositor detection
  property bool isHyprland: false
  property bool isNiri: false
  property bool isSway: false

  // Generic workspace and window data
  property ListModel workspaces: ListModel {}
  property ListModel windows: ListModel {}
  property int focusedWindowIndex: -1

  // Display scale data
  property var displayScales: ({})
  property bool displayScalesLoaded: false

  // Generic events
  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged

  // Backend service loader
  property var backend: null

  // Cache file path
  property string displayCachePath: ""

  Component.onCompleted: {
    // Setup cache path (needs Settings to be available)
    Qt.callLater(() => {
                   if (typeof Settings !== 'undefined' && Settings.cacheDir) {
                     displayCachePath = Settings.cacheDir + "display.json"
                     displayCacheFileView.path = displayCachePath
                   }
                 })

    detectCompositor()
  }

  function detectCompositor() {
    const hyprlandSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    const niriSocket = Quickshell.env("NIRI_SOCKET")
    const swaySock = Quickshell.env("SWAYSOCK")
    if (niriSocket && niriSocket.length > 0) {
      isHyprland = false
      isNiri = true
      isSway = false
      backendLoader.sourceComponent = niriComponent
    } else if (hyprlandSignature && hyprlandSignature.length > 0) {
      isHyprland = true
      isNiri = false
      isSway = false
      backendLoader.sourceComponent = hyprlandComponent
    } else if (swaySock && swaySock.length > 0) {
      isHyprland = false
      isNiri = false
      isSway = true
      backendLoader.sourceComponent = swayComponent
    } else {
      // Always fallback to Niri
      isHyprland = false
      isNiri = true
      isSway = false
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

  // Cache FileView for display scales
  FileView {
    id: displayCacheFileView
    printErrors: false
    watchChanges: false

    adapter: JsonAdapter {
      id: displayCacheAdapter
      property var displays: ({})
    }

    onLoaded: {
      // Load cached display scales
      displayScales = displayCacheAdapter.displays || {}
      displayScalesLoaded = true
      // Logger.i("CompositorService", "Loaded display scales from cache:", JSON.stringify(displayScales))
    }

    onLoadFailed: {
      // Cache doesn't exist yet, will be created on first update
      displayScalesLoaded = true
      // Logger.i("CompositorService", "No display cache found, will create on first update")
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

  // Sway backend component
  Component {
    id: swayComponent
    SwayService {
      id: swayBackend
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

  // Update display scales from backend
  function updateDisplayScales() {
    if (!backend || !backend.queryDisplayScales) {
      Logger.w("CompositorService", "Backend does not support display scale queries")
      return
    }

    backend.queryDisplayScales()
  }

  // Called by backend when display scales are ready
  function onDisplayScalesUpdated(scales) {
    displayScales = scales
    saveDisplayScalesToCache()
    displayScalesChanged()
    Logger.i("CompositorService", "Display scales updated")
  }

  // Save display scales to cache
  function saveDisplayScalesToCache() {
    if (!displayCachePath) {
      return
    }

    displayCacheAdapter.displays = displayScales
    displayCacheFileView.writeAdapter()
  }

  // Public function to get scale for a specific display
  function getDisplayScale(displayName) {
    if (!displayName || !displayScales[displayName]) {
      return 1.0
    }
    return displayScales[displayName].scale || 1.0
  }

  // Public function to get all display info for a specific display
  function getDisplayInfo(displayName) {
    if (!displayName || !displayScales[displayName]) {
      return null
    }
    return displayScales[displayName]
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
      var title = windows.get(focusedWindowIndex).title
      if (title !== undefined) {
        title = title.replace(/(\r\n|\n|\r)/g, "")
      }
      return title || ""
    }
    return ""
  }

  function getWindowsForWorkspace(workspaceId) {
    var windowsInWs = []
    for (var i = 0; i < windows.count; i++) {
      var window = windows.get(i)
      if (window.workspaceId === workspaceId) {
        windowsInWs.push(window)
      }
    }
    return windowsInWs
  }

  // Generic workspace switching
  function switchToWorkspace(workspace) {
    if (backend && backend.switchToWorkspace) {
      backend.switchToWorkspace(workspace)
    } else {
      Logger.w("Compositor", "No backend available for workspace switching")
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
      Logger.w("Compositor", "No backend available for window focus")
    }
  }

  // Close window
  function closeWindow(window) {
    if (backend && backend.closeWindow) {
      backend.closeWindow(window)
    } else {
      Logger.w("Compositor", "No backend available for window closing")
    }
  }

  // Session management
  function logout() {
    if (backend && backend.logout) {
      Logger.i("Compositor", "Logout requested")
      backend.logout()
    } else {
      Logger.w("Compositor", "No backend available for logout")
    }
  }

  function shutdown() {
    Logger.i("Compositor", "Shutdown requested")
    Quickshell.execDetached(["sh", "-c", "systemctl poweroff || loginctl poweroff"])
  }

  function reboot() {
    Logger.i("Compositor", "Reboot requested")
    Quickshell.execDetached(["sh", "-c", "systemctl reboot || loginctl reboot"])
  }

  function suspend() {
    Logger.i("Compositor", "Suspend requested")
    Quickshell.execDetached(["sh", "-c", "systemctl suspend || loginctl suspend"])
  }

  function lockAndSuspend() {
    Logger.i("Compositor", "Lock and suspend requested")
    try {
      if (PanelService && PanelService.lockScreen && !PanelService.lockScreen.active) {
        PanelService.lockScreen.active = true
      }
    } catch (e) {
      Logger.w("Compositor", "Failed to activate lock screen before suspend: " + e)
    }
    // Queue suspend to the next event loop cycle to allow lock UI to render
    Qt.callLater(suspend)
  }
}
