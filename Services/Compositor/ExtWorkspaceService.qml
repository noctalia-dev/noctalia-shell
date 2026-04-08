import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.WindowManager
import qs.Commons

// Generic ext-workspace-v1 + toplevel handling
Item {
  id: root

  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1
  property var trackedToplevels: new Set()

  property bool globalWorkspaces: false

  property var nativeWorkspaceMap: ({})
  property var connectedWorkspaces: ({})

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  function initialize() {
    updateWindows();
    connectWorkspaceSignals();
    syncWorkspaces();
    Logger.i("ExtWorkspaceService", "Service started (generic ext-workspace-v1)");
  }

  Connections {
    target: WindowManager

    function onWindowsetsChanged() {
      root.connectWorkspaceSignals();
      Qt.callLater(root.syncWorkspaces);
    }

    function onWindowsetProjectionsChanged() {
      Qt.callLater(root.syncWorkspaces);
    }
  }

  Timer {
    interval: 500
    running: true
    repeat: false
    onTriggered: {
      if (WindowManager.windowsets.length > 0) {
        root.connectWorkspaceSignals();
        root.syncWorkspaces();
      }
    }
  }

  function connectWorkspaceSignals() {
    const nativeWs = WindowManager.windowsets;
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
    const nativeWs = WindowManager.windowsets;

    workspaces.clear();
    nativeWorkspaceMap = {};

    /* Per-output (projection) index: compositors expose one workspace group per
    * monitor with names "1"…"9". A single global idx produced 10–18 on the
    * second head because all windowsets were merged into one list. */
    const perOutputNextIdx = {};

    for (const ws of nativeWs) {
      if (!ws.shouldDisplay) {
        continue;
      }

      let outputName = "";
      if (ws.projection) {
        const projScreens = ws.projection.screens;
        if (projScreens && projScreens.length > 0) {
          outputName = projScreens[0].name || "";
        }
      }

      const groupKey = outputName || "_";
      let idx;
      const numericName = ws.name && /^\d+$/.test(String(ws.name)) ? parseInt(ws.name, 10) : NaN;
      if (!isNaN(numericName) && numericName >= 1) {
        idx = numericName;
      } else {
        if (perOutputNextIdx[groupKey] === undefined) {
          perOutputNextIdx[groupKey] = 1;
        }
        idx = perOutputNextIdx[groupKey]++;
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
    }

    updateWindowWorkspaces();
    workspaceChanged();
  }

  function updateWindowWorkspaces() {
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

      const output = (toplevel.screens && toplevel.screens.length > 0) ? (toplevel.screens[0].name || "") : "";

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
    const nativeWs = nativeWorkspaceMap[workspace.id] || nativeWorkspaceMap[workspace.oid];
    if (nativeWs && nativeWs.canActivate) {
      nativeWs.activate();
    } else {
      Logger.w("ExtWorkspaceService", "Cannot activate workspace: " + (workspace.name || workspace.id));
    }
  }

  function turnOffMonitors() {
    try {
      Quickshell.execDetached(["wlr-randr", "--off"]);
    } catch (e) {
      Logger.e("ExtWorkspaceService", "Failed to turn off monitors:", e);
    }
  }

  function turnOnMonitors() {
    try {
      Quickshell.execDetached(["wlr-randr", "--on"]);
    } catch (e) {
      Logger.e("ExtWorkspaceService", "Failed to turn on monitors:", e);
    }
  }

  function logout() {
    const sid = Quickshell.env("XDG_SESSION_ID");
    try {
      if (sid && sid.length > 0) {
        Quickshell.execDetached(["loginctl", "terminate-session", sid]);
      } else {
        Logger.w("ExtWorkspaceService", "logout: XDG_SESSION_ID unset; use session menu custom command or compositor-specific backend");
      }
    } catch (e) {
      Logger.e("ExtWorkspaceService", "Failed to logout:", e);
    }
  }

  function cycleKeyboardLayout() {
    Logger.w("ExtWorkspaceService", "Keyboard layout cycling not supported");
  }

  function queryDisplayScales() {
    Logger.w("ExtWorkspaceService", "Display scale queries not supported via ToplevelManager");
  }

  function getFocusedScreen() {
    return null;
  }
}
