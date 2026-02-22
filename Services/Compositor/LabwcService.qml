import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1
  property var trackedToplevels: ({})

  // LabWC typically has global workspaces (shared across all outputs)
  property bool globalWorkspaces: true

  // Internal workspace state from helper
  property var workspaceData: ({})
  property int activeWorkspaceOid: -1

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  // Path to the helper script
  readonly property string helperScript: Qt.resolvedUrl("../../Scripts/python/src/compositor/labwc-workspace-helper.py").toString().replace("file://", "")

  function initialize() {
    updateWindows();
    startWorkspaceHelper();
    Logger.i("LabwcService", "Service started");
  }

  // Workspace helper process
  Process {
    id: workspaceHelper
    running: false
    command: ["python3", root.helperScript]

    stdout: SplitParser {
      onRead: function (line) {
        root.parseHelperOutput(line);
      }
    }

    stderr: SplitParser {
      onRead: function (line) {
        Logger.w("LabwcService", "Helper stderr: " + line);
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0) {
        Logger.e("LabwcService", "Workspace helper exited with code: " + exitCode);
      }
      // Restart helper after a delay if it crashes
      if (root.visible !== false) {
        restartTimer.start();
      }
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    repeat: false
    onTriggered: {
      if (!workspaceHelper.running) {
        Logger.i("LabwcService", "Restarting workspace helper...");
        startWorkspaceHelper();
      }
    }
  }

  function startWorkspaceHelper() {
    if (!workspaceHelper.running) {
      workspaceHelper.running = true;
      Logger.d("LabwcService", "Starting workspace helper: " + helperScript);
    }
  }

  function stopWorkspaceHelper() {
    if (workspaceHelper.running) {
      workspaceHelper.running = false;
    }
  }

  function parseHelperOutput(line) {
    try {
      const data = JSON.parse(line);

      if (data.type === "state") {
        processWorkspaceState(data);
      } else if (data.type === "error") {
        Logger.e("LabwcService", "Helper error: " + data.message);
      }
    } catch (e) {
      Logger.e("LabwcService", "Failed to parse helper output: " + e + " - " + line);
    }
  }

  function processWorkspaceState(data) {
    const wsList = data.workspaces || [];
    const groups = data.groups || [];
    const oldActiveOid = activeWorkspaceOid;

    // Clear and rebuild workspaces
    workspaces.clear();
    workspaceData = {};

    let newActiveOid = -1;
    let idx = 1;

    for (const ws of wsList) {
      // Skip hidden workspaces
      if (ws.isHidden) {
        continue;
      }

      // Find which outputs this workspace's group spans
      let groupOutputs = [];
      if (ws.groupOid !== undefined && ws.groupOid !== null) {
        for (const grp of groups) {
          if (grp.oid === ws.groupOid && grp.outputs && grp.outputs.length > 0) {
            groupOutputs = grp.outputs;
            break;
          }
        }
      }

      const wsEntry = {
        "id": ws.oid,
        "idx": ws.coordinates && ws.coordinates.length > 0 ? ws.coordinates[0] + 1 : idx,
        "name": ws.name || ("Workspace " + idx),
        "output": groupOutputs.length > 0 ? groupOutputs[0] : "",
        "isFocused": ws.isActive,
        "isActive": true,
        "isUrgent": ws.isUrgent,
        "isOccupied": false,
        "oid": ws.oid
      };

      workspaces.append(wsEntry);
      workspaceData[ws.oid] = wsEntry;

      if (ws.isActive) {
        newActiveOid = ws.oid;
      }

      idx++;
    }

    activeWorkspaceOid = newActiveOid;

    // Update windows with workspace info
    updateWindowWorkspaces();

    // Emit signal if workspace changed
    if (oldActiveOid !== newActiveOid || workspaces.count > 0) {
      workspaceChanged();
    }
  }

  function updateWindowWorkspaces() {
    // Update windows with active workspace ID
    // Note: ext-workspace-v1 doesn't provide window-to-workspace mapping
    // This requires ext-toplevel-workspace protocol which LabWC may not support yet
    // For now, assign all windows to the active workspace
    for (let i = 0; i < windows.length; i++) {
      if (activeWorkspaceOid > 0) {
        windows[i].workspaceId = activeWorkspaceOid;
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
    if (!toplevel || !toplevel.address)
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
    const newTracked = {};

    let focusedIdx = -1;
    let idx = 0;

    for (const toplevel of toplevels) {
      if (!toplevel)
        continue;

      const addr = toplevel.address || "";
      if (addr && !trackedToplevels[addr]) {
        connectToToplevel(toplevel);
      }
      if (addr) {
        newTracked[addr] = true;
      }

      newWindows.push({
                        "id": addr,
                        "appId": toplevel.appId || "",
                        "title": toplevel.title || "",
                        "workspaceId": activeWorkspaceOid > 0 ? activeWorkspaceOid : 1,
                        "isFocused": toplevel.activated || false,
                        "toplevel": toplevel
                      });

      if (toplevel.activated) {
        focusedIdx = idx;
      }
      idx++;
    }

    trackedToplevels = newTracked;
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
    try {
      // Use the workspace name for activation via ext-workspace protocol
      // Names are "1", "2", "3", "4" as configured in labwc rc.xml
      const wsName = workspace.name || workspace.idx?.toString() || "1";

      // Activate via ext-workspace protocol using workspace name
      Quickshell.execDetached(["python3", helperScript, "--activate", wsName]);
    } catch (e) {
      Logger.e("LabwcService", "Failed to switch workspace:", e);
    }
  }

  function turnOffMonitors() {
    try {
      Quickshell.execDetached(["wlr-randr", "--off"]);
    } catch (e) {
      Logger.e("LabwcService", "Failed to turn off monitors:", e);
    }
  }

  function logout() {
    stopWorkspaceHelper();
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

  Component.onDestruction: {
    stopWorkspaceHelper();
  }
}
