import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.WindowManager
import qs.Commons

Item {
  id: root

  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1
  property var trackedToplevels: new Set()

  // LabWC typically has global workspaces (shared across all outputs)
  property bool globalWorkspaces: true

  // Map from native workspace id to the native Workspace object for activation
  property var nativeWorkspaceMap: ({})

  // Set of workspace objects we've already connected signals to
  property var connectedWorkspaces: ({})

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  function initialize() {
    updateWindows();
    connectWorkspaceSignals();
    syncWorkspaces();
    Logger.i("LabwcService", "Service started (native ext-workspace-v1)");
  }

  // Watch for workspaces being added/removed from the model
  Connections {
    target: WindowManager.workspaces

    function onValuesChanged() {
      root.connectWorkspaceSignals();
      Qt.callLater(root.syncWorkspaces);
    }
  }

  // Connect to property change signals on each native workspace object
  function connectWorkspaceSignals() {
    const nativeWs = WindowManager.workspaces.values;
    const newConnected = {};

    for (const ws of nativeWs) {
      const key = ws.id || ws.toString();
      newConnected[key] = true;

      if (connectedWorkspaces[key])
        continue;

      ws.activeChanged.connect(() => {
                                 Qt.callLater(root.syncWorkspaces);
                               });

      ws.urgentChanged.connect(() => {
                                 Qt.callLater(root.syncWorkspaces);
                               });

      ws.shouldDisplayChanged.connect(() => {
                                        Qt.callLater(root.syncWorkspaces);
                                      });

      ws.nameChanged.connect(() => {
                               Qt.callLater(root.syncWorkspaces);
                             });
    }

    connectedWorkspaces = newConnected;
  }

  function syncWorkspaces() {
    const nativeWs = WindowManager.workspaces.values;
    const groups = WindowManager.workspaceGroups.values;

    workspaces.clear();
    nativeWorkspaceMap = {};

    let idx = 1;

    for (const ws of nativeWs) {
      // Skip hidden workspaces (shouldDisplay = false means hidden)
      if (!ws.shouldDisplay) {
        continue;
      }

      // Find which outputs this workspace's group spans
      let outputName = "";
      if (ws.group) {
        const groupScreens = ws.group.screens;
        if (groupScreens && groupScreens.length > 0) {
          outputName = groupScreens[0].name || "";
        }
      }

      const wsEntry = {
        "id": ws.id || idx.toString(),
        "idx": idx,
        "name": ws.name || ("Workspace " + idx),
        "output": outputName,
        "isFocused": ws.active,
        "isActive": true,
        "isUrgent": ws.urgent,
        "isOccupied": false,
        "oid": ws.id || idx.toString()
      };

      workspaces.append(wsEntry);
      nativeWorkspaceMap[wsEntry.id] = ws;

      idx++;
    }

    // Update windows with workspace info
    updateWindowWorkspaces();
    workspaceChanged();
  }

  function updateWindowWorkspaces() {
    // ext-workspace-v1 doesn't provide window-to-workspace mapping
    // Assign all windows to the active workspace
    let activeId = "";
    for (let i = 0; i < workspaces.count; i++) {
      const ws = workspaces.get(i);
      if (ws.isFocused) {
        activeId = ws.id;
        break;
      }
    }

    for (let i = 0; i < windows.length; i++) {
      if (activeId) {
        windows[i].workspaceId = activeId;
      }
    }
    windowListChanged();
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() {
      updateWindows();
    }
  }

  function connectToToplevel(toplevel) {
    if (!toplevel)
      return;

    toplevel.activatedChanged.connect(() => {
                                        Qt.callLater(onToplevelActivationChanged);
                                      });

    toplevel.titleChanged.connect(() => {
                                    Qt.callLater(updateWindows);
                                  });
  }

  function onToplevelActivationChanged() {
    updateWindows();
    activeWindowChanged();
  }

  function updateWindows() {
    const newWindows = [];
    const toplevels = ToplevelManager.toplevels?.values || [];

    let focusedIdx = -1;
    let idx = 0;

    // Find active workspace id
    let activeId = "";
    for (let i = 0; i < workspaces.count; i++) {
      const ws = workspaces.get(i);
      if (ws.isFocused) {
        activeId = ws.id;
        break;
      }
    }

    for (const toplevel of toplevels) {
      if (!toplevel)
        continue;

      if (!trackedToplevels.has(toplevel)) {
        connectToToplevel(toplevel);
        trackedToplevels.add(toplevel);
      }

      // Get output name from toplevel's screen list
      const output = (toplevel.screens && toplevel.screens.length > 0) ? (toplevel.screens[0].name || "") : "";

      // Use appId + title as a stable id since Toplevel has no address property
      const windowId = (toplevel.appId || "") + ":" + idx;

      newWindows.push({
                        "id": windowId,
                        "appId": toplevel.appId || "",
                        "title": toplevel.title || "",
                        "output": output,
                        "workspaceId": activeId || "1",
                        "isFocused": toplevel.activated || false,
                        "toplevel": toplevel
                      });

      if (toplevel.activated) {
        focusedIdx = idx;
      }
      idx++;
    }
    windows = newWindows;
    focusedWindowIndex = focusedIdx;

    windowListChanged();
  }

  function focusWindow(window) {
    if (window.toplevel && typeof window.toplevel.activate === "function") {
      window.toplevel.activate();
    }
  }

  function closeWindow(window) {
    if (window.toplevel && typeof window.toplevel.close === "function") {
      window.toplevel.close();
    }
  }

  function switchToWorkspace(workspace) {
    // Find the native Workspace object and activate it directly
    const nativeWs = nativeWorkspaceMap[workspace.id] || nativeWorkspaceMap[workspace.oid];
    if (nativeWs && nativeWs.canActivate) {
      nativeWs.activate();
    } else {
      Logger.w("LabwcService", "Cannot activate workspace: " + (workspace.name || workspace.id));
    }
  }

  function turnOffMonitors() {
    try {
      Quickshell.execDetached(["wlr-randr", "--off"]);
    } catch (e) {
      Logger.e("LabwcService", "Failed to turn off monitors:", e);
    }
  }

  function turnOnMonitors() {
    try {
      Quickshell.execDetached(["wlr-randr", "--on"]);
    } catch (e) {
      Logger.e("LabwcService", "Failed to turn on monitors:", e);
    }
  }

  function logout() {
    try {
      // Exit labwc by sending SIGTERM to $LABWC_PID or using --exit flag
      Quickshell.execDetached(["sh", "-c", "labwc --exit || kill -s SIGTERM $LABWC_PID"]);
    } catch (e) {
      Logger.e("LabwcService", "Failed to logout:", e);
    }
  }

  function cycleKeyboardLayout() {
    Logger.w("LabwcService", "Keyboard layout cycling not supported");
  }

  function queryDisplayScales() {
    Logger.w("LabwcService", "Display scale queries not supported via ToplevelManager");
  }

  function getFocusedScreen() {
    // de-activated until proper testing
    return null;
  }
}
