import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  // Configurable IPC command name (overridden to "scrollmsg" for Scroll)
  property string msgCommand: "swaymsg"

  // Properties that match the facade interface
  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1

  function _normalizeRefreshMilli(refresh) {
    const r = Number(refresh);
    if (!isFinite(r) || r <= 0)
      return 60000;
    // Sway reports refresh in mHz; tolerate Hz-style values defensively.
    return r < 1000 ? Math.round(r * 1000) : Math.round(r);
  }

  function _transformFromSway(transform) {
    const tMap = {
      "normal": "Normal",
      "90": "90",
      "180": "180",
      "270": "270",
      "flipped": "Flipped",
      "flipped-90": "Flipped90",
      "flipped-180": "Flipped180",
      "flipped-270": "Flipped270"
    };
    return tMap[String(transform || "normal")] || "Normal";
  }

  function _transformToSway(transform) {
    const tMap = {
      "normal": "normal",
      "Normal": "normal",
      "90": "90",
      "180": "180",
      "270": "270",
      "flipped": "flipped",
      "Flipped": "flipped",
      "flipped-90": "flipped-90",
      "Flipped90": "flipped-90",
      "flipped-180": "flipped-180",
      "Flipped180": "flipped-180",
      "flipped-270": "flipped-270",
      "Flipped270": "flipped-270"
    };
    return tMap[String(transform || "normal")] || "normal";
  }

  function _modeStrToSway(modeStr) {
    const raw = String(modeStr || "").trim();
    if (raw === "")
      return "preferred";

    const at = raw.split("@");
    if (at.length !== 2)
      return raw;

    const hz = Number(at[1]);
    if (!isFinite(hz) || hz <= 0)
      return raw;
    return at[0] + "@" + hz.toFixed(3) + "Hz";
  }

  function _isAdaptiveSyncEnabled(output) {
    if (!output)
      return false;

    const status = output.adaptive_sync_status;
    if (typeof status === "boolean")
      return status;
    if (status !== undefined && status !== null) {
      const s = String(status).toLowerCase();
      return s === "enabled" || s === "on" || s === "true";
    }
    return output.adaptive_sync === true;
  }

  property var displayBackend: ({
    generateRevertCmds: function (snap, curSnap) {
      let pending = [];
      let onOffCmds = [];

      for (const outputName in snap) {
        const s = snap[outputName];
        const cur = curSnap[outputName] || {};

        if (s.enabled !== cur.enabled) {
          onOffCmds.push([root.msgCommand, "output", outputName, s.enabled ? "enable" : "disable"]);
        }

        if (s.enabled === false)
          continue;

        if (s.modeStr && s.modeStr !== cur.modeStr) {
          pending.push([root.msgCommand, "output", outputName, "mode", root._modeStrToSway(s.modeStr)]);
        }
        if (Math.abs((s.scale || 1.0) - (cur.scale || 1.0)) > 0.01) {
          pending.push([root.msgCommand, "output", outputName, "scale", String(s.scale)]);
        }
        if (s.transform !== cur.transform) {
          pending.push([root.msgCommand, "output", outputName, "transform", root._transformToSway(s.transform)]);
        }
        if (Math.round(s.x || 0) !== Math.round(cur.x || 0) || Math.round(s.y || 0) !== Math.round(cur.y || 0)) {
          pending.push([root.msgCommand, "output", outputName, "position", String(Math.round(s.x || 0)), String(Math.round(s.y || 0))]);
        }
        if (s.vrr_enabled !== cur.vrr_enabled) {
          pending.push([root.msgCommand, "output", outputName, "adaptive_sync", s.vrr_enabled ? "on" : "off"]);
        }
      }

      return onOffCmds.concat(pending);
    },

    parseFetch: function (rawData) {
      const data = {};
      const outputs = Array.isArray(rawData) ? rawData : [];

      for (let i = 0; i < outputs.length; i++) {
        const mon = outputs[i];
        if (!mon || !mon.name)
          continue;

        const isEnabled = mon.active === true || mon.enabled === true;
        const currentMode = mon.current_mode || {};
        const modes = [];
        let currentModeIdx = 0;

        for (let j = 0; j < (mon.modes || []).length; j++) {
          const m = mon.modes[j];
          if (!m)
            continue;

          const modeEntry = {
            width: Number(m.width) || 0,
            height: Number(m.height) || 0,
            refresh_rate: root._normalizeRefreshMilli(m.refresh),
            is_preferred: m.preferred === true
          };
          modes.push(modeEntry);

          const sameAsCurrent = modeEntry.width === (Number(currentMode.width) || 0)
                                && modeEntry.height === (Number(currentMode.height) || 0)
                                && Math.abs(modeEntry.refresh_rate - root._normalizeRefreshMilli(currentMode.refresh)) < 2;
          if (m.current === true || sameAsCurrent) {
            currentModeIdx = modes.length - 1;
          }
        }

        if (modes.length === 0 && Number(currentMode.width) > 0 && Number(currentMode.height) > 0) {
          modes.push({
                       width: Number(currentMode.width),
                       height: Number(currentMode.height),
                       refresh_rate: root._normalizeRefreshMilli(currentMode.refresh)
                     });
          currentModeIdx = 0;
        }

        const scale = Number(mon.scale) > 0 ? Number(mon.scale) : 1.0;
        const transform = root._transformFromSway(mon.transform);
        const applyRot = ["90", "270", "Flipped90", "Flipped270"].includes(transform);

        const modeW = modes[currentModeIdx] ? modes[currentModeIdx].width : 1920;
        const modeH = modes[currentModeIdx] ? modes[currentModeIdx].height : 1080;
        const rotatedW = applyRot ? modeH : modeW;
        const rotatedH = applyRot ? modeW : modeH;

        const rect = mon.rect || {};
        const logicalWidth = Number(rect.width) > 0 ? Number(rect.width) : Math.floor(rotatedW / scale);
        const logicalHeight = Number(rect.height) > 0 ? Number(rect.height) : Math.floor(rotatedH / scale);

        data[mon.name] = {
          name: mon.name,
          enabled: isEnabled,
          make: mon.make || "",
          model: mon.model || "",
          vrr_enabled: root._isAdaptiveSyncEnabled(mon),
          current_mode: currentModeIdx,
          modes: modes,
          logical: {
            x: Number(rect.x) || 0,
            y: Number(rect.y) || 0,
            width: logicalWidth,
            height: logicalHeight,
            scale: scale,
            transform: transform
          }
        };
      }

      return data;
    },

    buildSetModeCmd: function (outputName, cfg) {
      return [[root.msgCommand, "output", outputName, "mode", root._modeStrToSway(cfg.modeStr)]];
    },

    buildSetScaleCmd: function (outputName, cfg) {
      return [[root.msgCommand, "output", outputName, "scale", String(cfg.scale)]];
    },

    buildSetTransformCmd: function (outputName, cfg) {
      return [[root.msgCommand, "output", outputName, "transform", root._transformToSway(cfg.transform)]];
    },

    buildSetVrrCmd: function (outputName, cfg) {
      return [[root.msgCommand, "output", outputName, "adaptive_sync", cfg.vrr_enabled ? "on" : "off"]];
    },

    buildToggleOutputCmd: function (outputName, enabled) {
      return [[root.msgCommand, "output", outputName, enabled ? "enable" : "disable"]];
    },

    buildPositionsCmds: function (targetConfig) {
      let pending = [];
      for (const outputName in targetConfig) {
        const cfg = targetConfig[outputName];
        if (!cfg || cfg.enabled === false)
          continue;
        pending.push([root.msgCommand, "output", outputName, "position", String(Math.round(cfg.x || 0)), String(Math.round(cfg.y || 0))]);
      }
      return pending;
    }
  })

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
      Qt.callLater(() => {
                     safeUpdateWorkspaces();
                     queryWindowWorkspaces();
                     queryDisplayScales();
                     queryKeyboardLayout();
                   });
      initialized = true;
      Logger.i("SwayService", "Service started");
    } catch (e) {
      Logger.e("SwayService", "Failed to initialize:", e);
    }
  }

  // Query window-to-workspace mapping via IPC
  function queryWindowWorkspaces() {
    swayTreeProcess.running = true;
  }

  // Sway tree process for getting window workspace information
  Process {
    id: swayTreeProcess
    running: false
    command: [msgCommand, "-t", "get_tree", "-r"]

    property string accumulatedOutput: ""

    stdout: SplitParser {
      onRead: function (line) {
        swayTreeProcess.accumulatedOutput += line;
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0 || !accumulatedOutput) {
        Logger.e("SwayService", "Failed to query tree, exit code:", exitCode);
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

          // If this is a regular or floating container with app_id/class (i.e., a window)
          if ((node.type === "con" || node.type === "floating_con") && (node.app_id || node.window_properties)) {
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
        Logger.e("SwayService", "Failed to parse tree:", e);
      } finally {
        accumulatedOutput = "";
      }
    }
  }

  // Query display scales
  function queryDisplayScales() {
    swayOutputsProcess.running = true;
  }

  // Sway outputs process for display scale detection
  Process {
    id: swayOutputsProcess
    running: false
    command: [msgCommand, "-t", "get_outputs", "-r"]

    property string accumulatedOutput: ""

    stdout: SplitParser {
      onRead: function (line) {
        swayOutputsProcess.accumulatedOutput += line;
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0 || !accumulatedOutput) {
        Logger.e("SwayService", "Failed to query outputs, exit code:", exitCode);
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
        Logger.e("SwayService", "Failed to parse outputs:", e);
      } finally {
        // Clear accumulated output for next query
        accumulatedOutput = "";
      }
    }
  }

  function queryKeyboardLayout() {
    swayInputsProcess.running = true;
  }
  // Sway inputs process for keyboard layout detection
  Process {
    id: swayInputsProcess
    running: false
    command: [msgCommand, "-t", "get_inputs", "-r"]

    property string accumulatedOutput: ""

    stdout: SplitParser {
      onRead: function (line) {
        // Accumulate lines instead of parsing each one
        swayInputsProcess.accumulatedOutput += line;
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0 || !accumulatedOutput) {
        Logger.e("SwayService", "Failed to query inputs, exit code:", exitCode);
        accumulatedOutput = "";
        return;
      }

      try {
        const inputsData = JSON.parse(accumulatedOutput);
        for (const input of inputsData) {
          if (input.type == "keyboard") {
            const layoutName = input.xkb_active_layout_name;
            KeyboardLayoutService.setCurrentLayout(layoutName);
            Logger.d("SwayService", "Keyboard layout switched:", layoutName);
            break;
          }
        }
      } catch (e) {
        Logger.e("SwayService", "Failed to parse inputs:", e);
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
      Logger.e("SwayService", "Error updating workspaces:", e);
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
      Logger.e("SwayService", "Error updating windows:", e);
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
      const eventData = JSON.parse(ev);
      if (eventData.change == "xkb_layout" && eventData.input != null) {
        const input = eventData.input;
        if (input.type == "keyboard" && input.xkb_active_layout_name != null) {
          const layoutName = input.xkb_active_layout_name;
          KeyboardLayoutService.setCurrentLayout(layoutName);
          Logger.d("SwayService", "Keyboard layout switched:", layoutName);
        }
      }
    } catch (e) {
      Logger.e("SwayService", "Error handling input event:", e);
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

  // Some programs change title of window dependent on content
  Connections {
    target: ToplevelManager ? ToplevelManager.activeToplevel : null
    enabled: initialized
    function onTitleChanged() {
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
    }
  }

  I3IpcListener {
    subscriptions: ["input"]
    onIpcEvent: function (event) {
      handleInputEvent(event.data);
    }
  }

  // Public functions
  function switchToWorkspace(workspace) {
    try {
      workspace.handle.activate();
    } catch (e) {
      Logger.e("SwayService", "Failed to switch workspace:", e);
    }
  }

  function focusWindow(window) {
    try {
      window.handle.activate();
    } catch (e) {
      Logger.e("SwayService", "Failed to switch window:", e);
    }
  }

  function closeWindow(window) {
    try {
      window.handle.close();
    } catch (e) {
      Logger.e("SwayService", "Failed to close window:", e);
    }
  }

  function turnOffMonitors() {
    try {
      Quickshell.execDetached([msgCommand, "output", "*", "dpms", "off"]);
    } catch (e) {
      Logger.e("SwayService", "Failed to turn off monitors:", e);
    }
  }

  function turnOnMonitors() {
    try {
      Quickshell.execDetached([msgCommand, "output", "*", "dpms", "on"]);
    } catch (e) {
      Logger.e("SwayService", "Failed to turn on monitors:", e);
    }
  }

  function logout() {
    try {
      Quickshell.execDetached([msgCommand, "exit"]);
    } catch (e) {
      Logger.e("SwayService", "Failed to logout:", e);
    }
  }

  function cycleKeyboardLayout() {
    try {
      Quickshell.execDetached([msgCommand, "input", "type:keyboard", "xkb_switch_layout", "next"]);
    } catch (e) {
      Logger.e("SwayService", "Failed to cycle keyboard layout:", e);
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
      Quickshell.execDetached([msgCommand, "exec", "--"].concat(command));
    } catch (e) {
      Logger.e("SwayService", "Failed to spawn command:", e);
    }
  }
}
