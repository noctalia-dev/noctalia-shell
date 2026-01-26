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
                     safeUpdateWindows();
                     queryDisplayScales();
                     queryKeyboardLayout();
                   });
      initialized = true;
      Logger.i("SwayService", "Service started");
    } catch (e) {
      Logger.e("SwayService", "Failed to initialize:", e);
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
    command: ["swaymsg", "-t", "get_outputs", "-r"]

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
    command: ["swaymsg", "-t", "get_inputs", "-r"]

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
    safeUpdateWindows();
    safeUpdateWorkspaces();
    windowListChanged();
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

      if (!ToplevelManager.toplevels || !ToplevelManager.toplevels.values) {
        windows = [];
        focusedWindowIndex = -1;
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

      return {
        "title": title,
        "appId": appId,
        "isFocused": focused,
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

  function logout() {
    try {
      Quickshell.execDetached(["swaymsg", "exit"]);
    } catch (e) {
      Logger.e("SwayService", "Failed to logout:", e);
    }
  }

  function cycleKeyboardLayout() {
    try {
      Quickshell.execDetached(["swaymsg", "input", "type:keyboard", "xkb_switch_layout", "next"]);
    } catch (e) {
      Logger.e("SwayService", "Failed to cycle keyboard layout:", e);
    }
  }

  function getFocusedScreen() {
    const i3Mon = I3.focusedMonitor;
    if (i3Mon) {
      const monitorName = i3Mon.name;
      for (let i = 0; i < Quickshell.screens.length; i++) {
        if (Quickshell.screens[i].name === monitorName) {
          return Quickshell.screens[i];
        }
      }
    }
    return null;
  }
}
