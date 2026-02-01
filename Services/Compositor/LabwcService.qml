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
    try {
      const workspaceNum = workspace.idx || workspace.id || 1;
      // LabWC does not support direct IPC for workspace switching.
      // Workspace switching is done through keybindings configured in rc.xml.
      // As a workaround, we simulate Super+[number] keypress using ydotool or wtype.
      // This assumes the user has configured GoToDesktop keybindings like:
      // <keybind key="W-1"><action name="GoToDesktop" to="1" /></keybind>
      const keyCode = workspaceNum + 1; // ydotool: 2=1, 3=2, etc.
      Quickshell.execDetached(["sh", "-c", `ydotool key 125:1 ${keyCode}:1 ${keyCode}:0 125:0 2>/dev/null || wtype -M logo -P ${workspaceNum} -m logo 2>/dev/null`]);
    } catch (e) {
      Logger.e("LabwcService", "Failed to switch workspace:", e);
      Logger.w("LabwcService", "Workspace switching requires ydotool or wtype and configured keybindings in rc.xml");
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

    // const activeToplevel = ToplevelManager.activeToplevel;
    // if (activeToplevel && activeToplevel.screens && activeToplevel.screens.length > 0) {
    //   return activeToplevel.screens[0];
    // }
    // return null;
  }
}
