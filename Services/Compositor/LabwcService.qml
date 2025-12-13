import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1
  property var trackedToplevels: ({})

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  function initialize() {
    updateWindows();
    Logger.i("LabwcService", "Service started");
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() {
      updateWindows();
    }
  }

  function connectToToplevel(toplevel) {
    if (!toplevel || !toplevel.address) return;

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
      if (!toplevel) continue;

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
        "workspaceId": 1,
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
    Logger.w("LabwcService", "Workspace switching not supported via ToplevelManager");
  }

  function logout() {
    Logger.w("LabwcService", "Logout not directly supported");
  }

  function queryDisplayScales() {
    Logger.w("LabwcService", "Display scale queries not supported via ToplevelManager");
  }
}
