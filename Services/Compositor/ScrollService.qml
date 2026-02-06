import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  // Properties that match the facade interface
  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1

  // Signals that match the facade interface
  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  // I3-specific properties
  property bool initialized: false

  // Cache for window-to-workspace mapping
  property var windowWorkspaceMap: ({})

  // Track window usage counts per workspace to handle duplicates
  property var windowUsageCountsPerWorkspace: ({})

  // Debounce timer for updates
  Timer {
    id: updateTimer
    interval: 50
    repeat: false
    onTriggered: safeUpdate()
  }

  // Initialization
  function initialize() {
    if (initialized)
      return;
    try {
      I3.refreshWorkspaces();
      I3.dispatch('(["input"])');
      Qt.callLater(() => {
                     safeUpdateWorkspaces();
                     queryWindowWorkspaces();
                     queryDisplayScales();
                     queryKeyboardLayout();
                   });
      initialized = true;
      Logger.i("ScrollService", "Service started");
    } catch (e) {
      Logger.e("ScrollService", "Failed to initialize:", e);
    }
  }

  // Query window-to-workspace mapping via IPC
  function queryWindowWorkspaces() {
    scrollTreeProcess.running = true;
  }

  // Scroll tree process for getting window workspace information
  Process {
    id: scrollTreeProcess
    running: false
    command: ["scrollmsg", "-t", "get_tree", "-r"]

    property string accumulatedOutput: ""

    stdout: SplitParser {
      onRead: function (line) {
        scrollTreeProcess.accumulatedOutput += line;
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0 || !accumulatedOutput) {
        Logger.e("ScrollService", "Failed to query tree, exit code:", exitCode);
        accumulatedOutput = "";
        return;
      }

      try {
        const treeData = JSON.parse(accumulatedOutput);
        const newMap = {};
        const workspaceWindows = {}; // Track windows per workspace

        // Recursively find all windows and their workspaces
        function traverseTree(node, workspaceNum) {
          if (!node)
            return;

          // If this is a workspace node, update the workspace number
          if (node.type === "workspace" && node.num !== undefined) {
            workspaceNum = node.num;
            if (!workspaceWindows[workspaceNum]) {
              workspaceWindows[workspaceNum] = [];
            }
          }

          // If this is a container with app_id or class (i.e., a window)
          if (node.type === "con" && (node.app_id || node.window_properties)) {
            const appId = node.app_id || (node.window_properties ? node.window_properties.class : null);
            const title = node.name || "";
            const id = node.id;

            if (appId && workspaceNum !== undefined && workspaceNum >= 0) {
              // Store window info for this workspace
              workspaceWindows[workspaceNum].push({
                                                    appId: appId,
                                                    title: title,
                                                    id: id
                                                  });
            }
          }

          // Traverse children
          if (node.nodes && node.nodes.length > 0) {
            for (const child of node.nodes) {
              traverseTree(child, workspaceNum);
            }
          }

          // Traverse floating nodes
          if (node.floating_nodes && node.floating_nodes.length > 0) {
            for (const child of node.floating_nodes) {
              traverseTree(child, workspaceNum);
            }
          }
        }

        traverseTree(treeData, -1);

        // Now build the map with workspace-specific keys
        for (const wsNum in workspaceWindows) {
          const windows = workspaceWindows[wsNum];
          const appTitleCounts = {}; // Count occurrences of each appId:title in this workspace

          for (const win of windows) {
            const baseKey = `${win.appId}:${win.title}`;

            // Track how many times we've seen this appId:title combo in this workspace
            if (!appTitleCounts[baseKey]) {
              appTitleCounts[baseKey] = 0;
            }
            const occurrence = appTitleCounts[baseKey];
            appTitleCounts[baseKey]++;

            // Create unique key with workspace and occurrence index
            const uniqueKey = `ws${wsNum}:${baseKey}[${occurrence}]`;
            newMap[uniqueKey] = parseInt(wsNum);

            // Also store by ID if available (most reliable)
            if (win.id) {
              newMap[`id:${win.id}`] = parseInt(wsNum);
            }
          }
        }

        windowWorkspaceMap = newMap;

        // Update windows with new workspace information
        Qt.callLater(safeUpdateWindows);
      } catch (e) {
        Logger.e("ScrollService", "Failed to parse tree:", e);
      } finally {
        accumulatedOutput = "";
      }
    }
  }

  // Query display scales
  function queryDisplayScales() {
    scrollOutputsProcess.running = true;
  }

  // Scroll outputs process for display scale detection
  Process {
    id: scrollOutputsProcess
    running: false
    command: ["scrollmsg", "-t", "get_outputs", "-r"]

    property string accumulatedOutput: ""

    stdout: SplitParser {
      onRead: function (line) {
        scrollOutputsProcess.accumulatedOutput += line;
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0 || !accumulatedOutput) {
        Logger.e("ScrollService", "Failed to query outputs, exit code:", exitCode);
        accumulatedOutput = "";
        return;
      }

      try {
        const outputsData = JSON.parse(accumulatedOutput);
        const scales = {};

        for (const output of outputsData) {
          if (output.name) {
            scales[output.name] = {
              "name": output.name,
              "scale": output.scale || 1.0,
              "width": output.current_mode ? output.current_mode.width : 0,
              "height": output.current_mode ? output.current_mode.height : 0,
              "refresh_rate": output.current_mode ? output.current_mode.refresh : 0,
              "x": output.rect ? output.rect.x : 0,
              "y": output.rect ? output.rect.y : 0,
              "active": output.active || false,
              "focused": output.focused || false,
              "current_workspace": output.current_workspace || ""
            };
          }
        }

        // Notify CompositorService (it will emit displayScalesChanged)
        if (CompositorService && CompositorService.onDisplayScalesUpdated) {
          CompositorService.onDisplayScalesUpdated(scales);
        }
      } catch (e) {
        Logger.e("ScrollService", "Failed to parse outputs:", e);
      } finally {
        // Clear accumulated output for next query
        accumulatedOutput = "";
      }
    }
  }

  Timer {
    id: keyboardLayoutUpdateTimer
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      queryKeyboardLayout();
    }
  }

  function queryKeyboardLayout() {
    scrollInputsProcess.running = true;
  }
  // Scroll inputs process for keyboard layout detection
  Process {
    id: scrollInputsProcess
    running: false
    command: ["scrollmsg", "-t", "get_inputs", "-r"]

    property string accumulatedOutput: ""

    stdout: SplitParser {
      onRead: function (line) {
        // Accumulate lines instead of parsing each one
        scrollInputsProcess.accumulatedOutput += line;
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0 || !accumulatedOutput) {
        Logger.e("ScrollService", "Failed to query inputs, exit code:", exitCode);
        accumulatedOutput = "";
        return;
      }

      try {
        const inputsData = JSON.parse(accumulatedOutput);
        for (const input of inputsData) {
          if (input.type == "keyboard") {
            const layoutName = input.xkb_active_layout_name;
            KeyboardLayoutService.setCurrentLayout(layoutName);
            Logger.d("ScrollService", "Keyboard layout switched:", layoutName);
            break;
          }
        }
      } catch (e) {
        Logger.e("ScrollService", "Failed to parse inputs:", e);
      } finally {
        // Clear accumulated output for next query
        accumulatedOutput = "";
      }
    }
  }

  // Safe update wrapper
  function safeUpdate() {
    queryWindowWorkspaces();
    safeUpdateWorkspaces();
  }

  // Safe workspace update
  function safeUpdateWorkspaces() {
    try {
      workspaces.clear();

      if (!I3.workspaces || !I3.workspaces.values) {
        return;
      }

      const hlWorkspaces = I3.workspaces.values;

      for (var i = 0; i < hlWorkspaces.length; i++) {
        const ws = hlWorkspaces[i];
        if (!ws || ws.id < 1)
          continue;
        const wsData = {
          "id": i,
          "idx": ws.num,
          "name": ws.name || "",
          "output": (ws.monitor && ws.monitor.name) ? ws.monitor.name : "",
          "isActive": ws.active === true,
          "isFocused": ws.focused === true,
          "isUrgent": ws.urgent === true,
          "isOccupied": true,
          "handle": ws
        };

        workspaces.append(wsData);
      }
    } catch (e) {
      Logger.e("ScrollService", "Error updating workspaces:", e);
    }
  }

  // Safe window update
  function safeUpdateWindows() {
    try {
      const windowsList = [];

      // Reset usage counts per workspace before processing windows
      windowUsageCountsPerWorkspace = {};

      if (!ToplevelManager.toplevels || !ToplevelManager.toplevels.values) {
        windows = [];
        focusedWindowIndex = -1;
        windowListChanged();
        return;
      }

      const hlToplevels = ToplevelManager.toplevels.values;
      let newFocusedIndex = -1;

      for (var i = 0; i < hlToplevels.length; i++) {
        const toplevel = hlToplevels[i];
        if (!toplevel)
          continue;
        const windowData = extractWindowData(toplevel);
        if (windowData) {
          windowsList.push(windowData);

          if (windowData.isFocused) {
            newFocusedIndex = windowsList.length - 1;
          }
        }
      }

      windows = windowsList;

      if (newFocusedIndex !== focusedWindowIndex) {
        focusedWindowIndex = newFocusedIndex;
        activeWindowChanged();
      }

      windowListChanged();
    } catch (e) {
      Logger.e("ScrollService", "Error updating windows:", e);
    }
  }

  // Extract window data safely from a toplevel
  function extractWindowData(toplevel) {
    if (!toplevel)
      return null;

    try {
      // Safely extract properties
      const appId = getAppId(toplevel);
      const title = safeGetProperty(toplevel, "title", "");
      const focused = toplevel.activated === true;

      // Try to find workspace ID from our cached map by trying all workspaces
      let workspaceId = -1;
      let foundWorkspaceNum = -1;

      // Build base key for this window
      const baseKey = `${appId}:${title}`;

      // Try to find this window in any workspace
      for (var i = 0; i < workspaces.count; i++) {
        const ws = workspaces.get(i);
        if (!ws)
          continue;

        const wsNum = ws.idx;

        // Initialize usage count for this workspace if needed
        if (!windowUsageCountsPerWorkspace[wsNum]) {
          windowUsageCountsPerWorkspace[wsNum] = {};
        }

        // Get current usage count for this appId:title in this workspace
        if (!windowUsageCountsPerWorkspace[wsNum][baseKey]) {
          windowUsageCountsPerWorkspace[wsNum][baseKey] = 0;
        }

        const occurrence = windowUsageCountsPerWorkspace[wsNum][baseKey];
        const uniqueKey = `ws${wsNum}:${baseKey}[${occurrence}]`;

        // Check if this key exists in our map
        if (windowWorkspaceMap[uniqueKey] !== undefined) {
          foundWorkspaceNum = windowWorkspaceMap[uniqueKey];
          workspaceId = ws.id;

          // Increment the usage count for this workspace
          windowUsageCountsPerWorkspace[wsNum][baseKey]++;
          break;
        }
      }

      return {
        "title": title,
        "appId": appId,
        "isFocused": focused,
        "workspaceId": workspaceId,
        "handle": toplevel
      };
    } catch (e) {
      return null;
    }
  }

  function getAppId(toplevel) {
    if (!toplevel)
      return "";

    return toplevel.appId;
  }

  // Safe property getter
  function safeGetProperty(obj, prop, defaultValue) {
    try {
      const value = obj[prop];
      if (value !== undefined && value !== null) {
        return String(value);
      }
    } catch (e)

      // Property access failed
    {}
    return defaultValue;
  }

  function handleInputEvent(ev) {
    try {
      let beforeParenthesis;
      const parenthesisPos = ev.lastIndexOf('(');

      if (parenthesisPos === -1) {
        beforeParenthesis = ev;
      } else {
        beforeParenthesis = ev.substring(0, parenthesisPos);
      }

      const layoutNameStart = beforeParenthesis.lastIndexOf(',') + 1;
      const layoutName = ev.substring(layoutNameStart);

      KeyboardLayoutService.setCurrentLayout(layoutName);
      Logger.d("HyprlandService", "Keyboard layout switched:", layoutName);
    } catch (e) {
      Logger.e("HyprlandService", "Error handling activelayout:", e);
    }
  }

  // Connections to I3
  Connections {
    target: I3.workspaces
    enabled: initialized
    function onValuesChanged() {
      safeUpdateWorkspaces();
      workspaceChanged();
    }
  }

  Connections {
    target: ToplevelManager
    enabled: initialized
    function onActiveToplevelChanged() {
      updateTimer.restart();
    }
  }

  Connections {
    target: I3
    enabled: initialized
    function onRawEvent(event) {
      safeUpdateWorkspaces();
      workspaceChanged();
      updateTimer.restart();

      if (event.type === "output") {
        Qt.callLater(queryDisplayScales);
      }

      if (event.type == "get_inputs") {
        handleInputEvent(event.data);
      }

      // Query window workspaces on relevant events
      if (event.type === "window" || event.type === "workspace") {
        Qt.callLater(queryWindowWorkspaces);
      }
    }
  }

  // Public functions
  function switchToWorkspace(workspace) {
    try {
      workspace.handle.activate();
    } catch (e) {
      Logger.e("ScrollService", "Failed to switch workspace:", e);
    }
  }

  function focusWindow(window) {
    try {
      window.handle.activate();
    } catch (e) {
      Logger.e("ScrollService", "Failed to switch window:", e);
    }
  }

  function closeWindow(window) {
    try {
      window.handle.close();
    } catch (e) {
      Logger.e("ScrollService", "Failed to close window:", e);
    }
  }

  function logout() {
    try {
      Quickshell.execDetached(["scrollmsg", "exit"]);
    } catch (e) {
      Logger.e("ScrollService", "Failed to logout:", e);
    }
  }

  function cycleKeyboardLayout() {
    try {
      Quickshell.execDetached(["scrollmsg", "input", "type:keyboard", "xkb_switch_layout", "next"]);
    } catch (e) {
      Logger.e("ScrollService", "Failed to cycle keyboard layout:", e);
    }
  }

  function getFocusedScreen() {
    // de-activated until proper testing
    return null;

    // const i3Mon = I3.focusedMonitor;
    // if (i3Mon) {
    //   const monitorName = i3Mon.name;
    //   for (let i = 0; i < Quickshell.screens.length; i++) {
    //     if (Quickshell.screens[i].name === monitorName) {
    //       return Quickshell.screens[i];
    //     }
    //   }
    // }
    // return null;
  }

  function spawn(command) {
    try {
      Quickshell.execDetached(["scrollmsg", "exec", "--"].concat(command));
    } catch (e) {
      Logger.e("ScrollService", "Failed to spawn command:", e);
    }
  }
}
