pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Control
import qs.Services.UI

Singleton {
  id: root

  // Compositor detection
  property bool isHyprland: false
  property bool isNiri: false
  property bool isSway: false
  property bool isMango: false
  property bool isScroll: false
  property bool isLabwc: false

  // Generic workspace and window data
  property ListModel workspaces: ListModel {}
  property ListModel windows: ListModel {}
  property int focusedWindowIndex: -1

  // Display scale data
  property var displayScales: ({})
  property bool displayScalesLoaded: false

  // Overview state (Niri-specific, defaults to false for other compositors)
  property bool overviewActive: false

  // Global workspaces flag (workspaces shared across all outputs)
  // True for LabWC (stacking compositor), false for tiling WMs with per-output workspaces
  property bool globalWorkspaces: false

  // Generic events
  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged

  // Backend service loader
  property var backend: null

  Component.onCompleted: {
    Qt.callLater(() => {
      if (typeof ShellState !== 'undefined' && ShellState.isLoaded) {
        loadDisplayScalesFromState();
      }
    });

    detectCompositor();
  }

  Connections {
    target: typeof ShellState !== 'undefined' ? ShellState : null
    function onIsLoadedChanged() {
      if (ShellState.isLoaded) {
        loadDisplayScalesFromState();
      }
    }
  }

  function detectCompositor() {
    const hyprlandSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE");
    const niriSocket = Quickshell.env("NIRI_SOCKET");
    const swaySock = Quickshell.env("SWAYSOCK");
    const currentDesktop = Quickshell.env("XDG_CURRENT_DESKTOP");
    const labwcPid = Quickshell.env("LABWC_PID");

    // Scroll detection
    if (currentDesktop && currentDesktop.toLowerCase().includes("scroll")) {
      isHyprland = false;
      isNiri = false;
      isSway = false;
      isMango = false;
      isLabwc = false;
      isScroll = true;
      backendLoader.sourceComponent = scrollComponent;

    // Mango detection
    } else if (currentDesktop && currentDesktop.toLowerCase().includes("mango")) {
      isHyprland = false;
      isNiri = false;
      isSway = false;
      isMango = true;
      isLabwc = false;
      isScroll = false;
      backendLoader.sourceComponent = mangoComponent;

    } else if (labwcPid && labwcPid.length > 0) {
      isHyprland = false;
      isNiri = false;
      isSway = false;
      isMango = false;
      isLabwc = true;
      isScroll = false;
      backendLoader.sourceComponent = labwcComponent;
      Logger.i("CompositorService", "Detected LabWC with PID: " + labwcPid);

    } else if (niriSocket && niriSocket.length > 0) {
      isHyprland = false;
      isNiri = true;
      isSway = false;
      isMango = false;
      isLabwc = false;
      isScroll = false;
      backendLoader.sourceComponent = niriComponent;

    } else if (hyprlandSignature && hyprlandSignature.length > 0) {
      isHyprland = true;
      isNiri = false;
      isSway = false;
      isMango = false;
      isLabwc = false;
      isScroll = false;
      backendLoader.sourceComponent = hyprlandComponent;

    } else if (swaySock && swaySock.length > 0) {
      isHyprland = false;
      isNiri = false;
      isSway = true;
      isMango = false;
      isLabwc = false;
      isScroll = false;
      backendLoader.sourceComponent = swayComponent;

    } else {
      // Fallback to Niri
      isHyprland = false;
      isNiri = true;
      isSway = false;
      isMango = false;
      isLabwc = false;
      isScroll = false;
      backendLoader.sourceComponent = niriComponent;
    }
  }

  Loader {
    id: backendLoader
    onLoaded: {
      if (item) {
        root.backend = item;
        setupBackendConnections();
        backend.initialize();
      }
    }
  }

  function loadDisplayScalesFromState() {
    try {
      const cached = ShellState.getDisplay();
      if (cached && Object.keys(cached).length > 0) {
        displayScales = cached;
        displayScalesLoaded = true;
        Logger.d("CompositorService", "Loaded display scales from ShellState");
      } else {
        displayScalesLoaded = true;
      }
    } catch (error) {
      Logger.e("CompositorService", "Failed to load display scales:", error);
      displayScalesLoaded = true;
    }
  }

  // Hyprland backend component
  Component {
    id: hyprlandComponent
    HyprlandService { id: hyprlandBackend }
  }

  // Niri backend component
  Component {
    id: niriComponent
    NiriService { id: niriBackend }
  }

  // Sway backend component
  Component {
    id: swayComponent
    SwayService { id: swayBackend }
  }

  // Mango backend component
  Component {
    id: mangoComponent
    MangoService { id: mangoBackend }
  }

  // Scroll backend component
  Component {
    id: scrollComponent
    ScrollService { id: scrollBackend }
  }

  // Labwc backend component
  Component {
    id: labwcComponent
    LabwcService { id: labwcBackend }
  }

  function setupBackendConnections() {
    if (!backend)
      return;

    backend.workspaceChanged.connect(() => {
      syncWorkspaces();
      workspaceChanged();
    });

    backend.activeWindowChanged.connect(() => {
      syncFocusedWindow();
      activeWindowChanged();
    });

    backend.windowListChanged.connect(() => {
      syncWindows();
      windowListChanged();
    });

    backend.focusedWindowIndexChanged.connect(() => {
      focusedWindowIndex = backend.focusedWindowIndex;
    });

    if (backend.overviewActiveChanged) {
      backend.overviewActiveChanged.connect(() => {
        overviewActive = backend.overviewActive;
      });
    }

    syncWorkspaces();
    syncWindows();
    focusedWindowIndex = backend.focusedWindowIndex;

    if (backend.overviewActive !== undefined)
      overviewActive = backend.overviewActive;

    if (backend.globalWorkspaces !== undefined)
      globalWorkspaces = backend.globalWorkspaces;
  }

  function syncWorkspaces() {
    workspaces.clear();
    const ws = backend.workspaces;
    for (var i = 0; i < ws.count; i++)
      workspaces.append(ws.get(i));
    workspacesChanged();
  }

  function syncWindows() {
    windows.clear();
    const ws = backend.windows;
    for (var i = 0; i < ws.length; i++)
      windows.append(ws[i]);
    windowListChanged();
  }

  function syncFocusedWindow() {
    const newIndex = backend.focusedWindowIndex;

    for (var i = 0; i < windows.count && i < backend.windows.length; i++) {
      const backendFocused = backend.windows[i].isFocused;
      if (windows.get(i).isFocused !== backendFocused)
        windows.setProperty(i, "isFocused", backendFocused);
    }

    focusedWindowIndex = newIndex;
  }

  function updateDisplayScales() {
    if (!backend || !backend.queryDisplayScales) {
      Logger.w("CompositorService", "Backend does not support display scale queries");
      return;
    }
    backend.queryDisplayScales();
  }

  function onDisplayScalesUpdated(scales) {
    displayScales = scales;
    saveDisplayScalesToCache();
    displayScalesChanged();
    Logger.d("CompositorService", "Display scales updated");
  }

  function saveDisplayScalesToCache() {
    try {
      ShellState.setDisplay(displayScales);
      Logger.d("CompositorService", "Saved display scales to ShellState");
    } catch (error) {
      Logger.e("CompositorService", "Failed to save display scales:", error);
    }
  }

  function getDisplayScale(displayName) {
    if (!displayName || !displayScales[displayName])
      return 1.0;
    return displayScales[displayName].scale || 1.0;
  }

  function getDisplayInfo(displayName) {
    if (!displayName || !displayScales[displayName])
      return null;
    return displayScales[displayName];
  }

  function getFocusedWindow() {
    if (focusedWindowIndex >= 0 && focusedWindowIndex < windows.count)
      return windows.get(focusedWindowIndex);
    return null;
  }

  function getFocusedScreen() {
    if (backend && backend.getFocusedScreen)
      return backend.getFocusedScreen();
    return null;
  }

  function getFocusedWindowTitle() {
    if (focusedWindowIndex >= 0 && focusedWindowIndex < windows.count) {
      var title = windows.get(focusedWindowIndex).title;
      if (title !== undefined)
        title = title.replace(/(\r\n|\n|\r)/g, "");
      return title || "";
    }
    return "";
  }

  function getCleanAppName(appId, fallbackTitle) {
    var name = (appId || "").split(".").pop() || fallbackTitle || "Unknown";
    return name.charAt(0).toUpperCase() + name.slice(1);
  }

  function getWindowsForWorkspace(workspaceId) {
    var windowsInWs = [];
    for (var i = 0; i < windows.count; i++) {
      var window = windows.get(i);
      if (window.workspaceId === workspaceId)
        windowsInWs.push(window);
    }
    return windowsInWs;
  }

  function switchToWorkspace(workspace) {
    if (backend && backend.switchToWorkspace)
      backend.switchToWorkspace(workspace);
    else
      Logger.w("Compositor", "No backend available for workspace switching");
  }

  function getCurrentWorkspace() {
    for (var i = 0; i < workspaces.count; i++) {
      const ws = workspaces.get(i);
      if (ws.isFocused)
        return ws;
    }
    return null;
  }

  function getActiveWorkspaces() {
    const activeWorkspaces = [];
    for (var i = 0; i < workspaces.count; i++) {
      const ws = workspaces.get(i);
      if (ws.isActive)
        activeWorkspaces.push(ws);
    }
    return activeWorkspaces;
  }

  function focusWindow(window) {
    if (backend && backend.focusWindow)
      backend.focusWindow(window);
    else
      Logger.w("Compositor", "No backend available for window focus");
  }

  function closeWindow(window) {
    if (backend && backend.closeWindow)
      backend.closeWindow(window);
    else
      Logger.w("Compositor", "No backend available for window closing");
  }

  function spawn(command) {
    if (backend && backend.spawn)
      backend.spawn(command);
    else {
      try {
        Quickshell.execDetached(command);
      } catch (e) {
        Logger.e("Compositor", "Failed to exececute detached:", e);
      }
    }
  }

  function logout() {
    if (backend && backend.logout) {
      Logger.i("Compositor", "Logout requested");
      backend.logout();
    } else {
      Logger.w("Compositor", "No backend available for logout");
    }
  }

  function shutdown() {
    Logger.i("Compositor", "Shutdown requested");
    HooksService.executeSessionHook("shutdown", () => {
      Quickshell.execDetached(["sh", "-c", "systemctl poweroff || loginctl poweroff"]);
    });
  }

  function reboot() {
    Logger.i("Compositor", "Reboot requested");
    HooksService.executeSessionHook("reboot", () => {
      Quickshell.execDetached(["sh", "-c", "systemctl reboot || loginctl reboot"]);
    });
  }

  function suspend() {
    Logger.i("Compositor", "Suspend requested");
    Quickshell.execDetached(["sh", "-c", "systemctl suspend || loginctl suspend"]);
  }

  function hibernate() {
    Logger.i("Compositor", "Hibernate requested");
    Quickshell.execDetached(["sh", "-c", "systemctl hibernate || loginctl hibernate"]);
  }

  function cycleKeyboardLayout() {
    if (backend && backend.cycleKeyboardLayout)
      backend.cycleKeyboardLayout();
  }

  property int lockAndSuspendCheckCount: 0

  function lockAndSuspend() {
    Logger.i("Compositor", "Lock and suspend requested");

    if (PanelService && PanelService.lockScreen && PanelService.lockScreen.active) {
      Logger.i("Compositor", "Screen already locked, suspending");
      suspend();
      return;
    }

    try {
      if (PanelService && PanelService.lockScreen) {
        PanelService.lockScreen.active = true;
        lockAndSuspendCheckCount = 0;
        lockAndSuspendTimer.start();
      } else {
        Logger.w("Compositor", "Lock screen not available, suspending without lock");
        suspend();
      }
    } catch (e) {
      Logger.w("Compositor", "Failed to activate lock screen before suspend: " + e);
      suspend();
    }
  }

  Timer {
    id: lockAndSuspendTimer
    interval: 100
    repeat: true
    running: false

    onTriggered: {
      lockAndSuspendCheckCount++;

      if (PanelService && PanelService.lockScreen && PanelService.lockScreen.active) {
        if (PanelService.lockScreen.item) {
          Logger.i("Compositor", "Lock screen confirmed active, suspending");
          stop();
          lockAndSuspendCheckCount = 0;
          suspend();
        } else {
          if (lockAndSuspendCheckCount > 20) {
            Logger.w("Compositor", "Lock screen active but component not loaded, suspending anyway");
            stop();
            lockAndSuspendCheckCount = 0;
            suspend();
          }
        }
      } else {
        if (lockAndSuspendCheckCount > 30) {
          Logger.w("Compositor", "Lock screen failed to activate, suspending anyway");
          stop();
          lockAndSuspendCheckCount = 0;
          suspend();
        }
      }
    }
  }
}

