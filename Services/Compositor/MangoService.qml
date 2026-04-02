import QtQuick
import Quickshell
import Quickshell.DWL
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  // ===== PUBLIC INTERFACE (CompositorService compatibility) =====

  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1
  property bool initialized: false

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  // ===== MANGOSERVICE-SPECIFIC PROPERTIES =====

  property string selectedMonitor: ""
  property string currentLayoutSymbol: ""

  // ===== INTERNAL STATE =====

  QtObject {
    id: internal

    // Window-to-tag persistence: Map<UniqueID, TagID>
    property var windowTagMap: ({})

    // Window-to-output persistence: Map<UniqueID, OutputName>
    property var windowOutputMap: ({})

    // Toplevel-to-ID mapping: Map<ToplevelObject, UniqueID>
    property var toplevelIdMap: new Map()
    property int windowIdCounter: 0

    // Output name to index mapping for unique workspace IDs
    property var outputIndices: ({})
    property int outputCounter: 0

    // Monitor scales: Map<OutputName, scale>
    property var monitorScales: ({})

    // Window signature for change detection
    property string lastWindowSignature: ""

    // Scale regex
    readonly property var scalePattern: /^(\S+)\s+scale_factor\s+(\d+(?:\.\d+)?)$/

                                        // Get all screen names mapped to their DwlIpcOutput
                                        function getOutputMap() {
                                          const map = {};
                                          const screens = Quickshell.screens;
                                          for (let i = 0; i < screens.length; i++) {
                                            const name = screens[i].name;
                                            const dwlOutput = DwlIpc.outputForName(name);
                                            if (dwlOutput) {
                                              map[name] = dwlOutput;
                                            }
                                          }
                                          return map;
                                        }

    // ===== REBUILD WORKSPACES FROM DWL =====

    function rebuildWorkspaces() {
      if (!DwlIpc.available) {
        return;
      }

      const outputMap = getOutputMap();
      const workspaceList = [];

      for (const outputName in outputMap) {
        const output = outputMap[outputName];

        // Assign stable index to output
        if (internal.outputIndices[outputName] === undefined) {
          internal.outputIndices[outputName] = internal.outputCounter++;
        }
        const outputIdx = internal.outputIndices[outputName];

        // Track selected monitor and layout
        if (output.active) {
          root.selectedMonitor = outputName;
          root.currentLayoutSymbol = output.layoutSymbol;
        }

        const tags = output.tags;
        for (let ti = 0; ti < tags.length; ti++) {
          const tag = tags[ti];
          const tagId = tag.index + 1; // DwlTag.index is zero-based, our IDs are 1-based
          const uniqueId = outputIdx * 100 + tagId;

          workspaceList.push({
                               id: uniqueId,
                               idx: tagId,
                               name: tagId.toString(),
                               output: outputName,
                               isActive: tag.active,
                               isFocused: tag.active && output.active,
                               isUrgent: tag.urgent,
                               isOccupied: tag.clientCount > 0
                             });
        }
      }

      // Sort by unique ID
      workspaceList.sort((a, b) => a.id - b.id);

      root.workspaces.clear();
      for (let k = 0; k < workspaceList.length; k++) {
        root.workspaces.append(workspaceList[k]);
      }

      root.workspaceChanged();
    }

    // ===== UPDATE WINDOWS =====

    function updateWindows() {
      if (!ToplevelManager.toplevels || !DwlIpc.available) {
        return;
      }

      const outputMap = getOutputMap();
      const toplevels = ToplevelManager.toplevels.values;
      const windowList = [];
      let newFocusedIdx = -1;
      const currentWindows = new Set();

      // Build per-output state from DWL
      // Map<outputName, { title, appId, activeTagId }>
      // Always populated (activeTagId needed for visible-window inference),
      // title/appId may be empty if no window is focused.
      const outputState = {};
      for (const outputName in outputMap) {
        const output = outputMap[outputName];

        // Find active tag for this output
        let activeTagId = 1;
        const tags = output.tags;
        for (let ti = 0; ti < tags.length; ti++) {
          if (tags[ti].active) {
            activeTagId = tags[ti].index + 1;
            break;
          }
        }

        outputState[outputName] = {
          title: output.title || "",
          appId: output.appId || "",
          activeTagId: activeTagId
        };

        // Ensure output index exists
        if (internal.outputIndices[outputName] === undefined) {
          internal.outputIndices[outputName] = internal.outputCounter++;
        }
      }

      for (let i = 0; i < toplevels.length; i++) {
        const toplevel = toplevels[i];
        if (!toplevel || toplevel.outliers) {
          continue;
        }

        const appId = toplevel.appId || toplevel.wayland?.appId || "";
        const title = toplevel.title || toplevel.wayland?.title || "";
        const isFocused = toplevel.activated;

        // Get or assign a stable ID
        let windowId;
        if (internal.toplevelIdMap.has(toplevel)) {
          windowId = internal.toplevelIdMap.get(toplevel);
        } else {
          windowId = `win-${internal.windowIdCounter++}`;
          internal.toplevelIdMap.set(toplevel, windowId);
        }

        currentWindows.add(windowId);

        // Determine output
        let outputName;

        // Priority 1: Focused window matched to DWL output metadata
        if (isFocused && (title || appId)) {
          for (const oName in outputState) {
            const os = outputState[oName];
            if ((os.title || os.appId) && title === os.title && appId === os.appId) {
              outputName = oName;
              internal.windowOutputMap[windowId] = oName;
              break;
            }
          }
        }

        // Priority 2: Remembered output
        if (!outputName && internal.windowOutputMap[windowId]) {
          outputName = internal.windowOutputMap[windowId];
        }

        // Priority 3: toplevel.screens (wlr-foreign-toplevel visible screens)
        if (!outputName && toplevel.screens && toplevel.screens.length > 0) {
          outputName = toplevel.screens[0].name;
        }

        // Fallback: selected monitor
        if (!outputName) {
          outputName = root.selectedMonitor || "DP-1";
        }

        // Determine tag
        let tagId = null;

        const os = outputState[outputName];
        if (isFocused && os && !os.consumed && (os.title || os.appId) && title === os.title && appId === os.appId) {
          // Focused window: assign to the active tag from DWL metadata
          tagId = os.activeTagId;
          internal.windowTagMap[windowId] = tagId;
          // Consume so a second toplevel with identical title+appId cannot also claim focus
          os.consumed = true;
        } else if (internal.windowTagMap[windowId] !== undefined) {
          // Previously seen window: use remembered tag
          tagId = internal.windowTagMap[windowId];
        }

        if (tagId === null) {
          // DWL only reports the focused window per output, so we can't
          // determine the tag for unfocused windows until they gain focus.
          continue;
        }

        // Convert to unique workspace ID
        const outputIdx = internal.outputIndices[outputName];
        if (outputIdx === undefined) {
          Logger.e("MangoService", "No output index for", outputName);
          continue;
        }
        const workspaceId = outputIdx * 100 + tagId;

        windowList.push({
                          id: `${outputName}:${appId}:${title}:${i}`,
                          title: title,
                          appId: appId,
                          class: appId,
                          workspaceId: workspaceId,
                          isFocused: isFocused,
                          output: outputName,
                          handle: toplevel,
                          fullscreen: toplevel.fullscreen || false,
                          floating: toplevel.maximized === false && toplevel.fullscreen === false
                        });

        if (isFocused) {
          newFocusedIdx = windowList.length - 1;
        }
      }

      // Clean up stale window tracking
      if (Object.keys(internal.windowTagMap).length > toplevels.length + 20) {
        const newTagMap = {};
        const newOutputMap = {};
        for (const windowId of currentWindows) {
          if (internal.windowTagMap[windowId] !== undefined) {
            newTagMap[windowId] = internal.windowTagMap[windowId];
          }
          if (internal.windowOutputMap[windowId] !== undefined) {
            newOutputMap[windowId] = internal.windowOutputMap[windowId];
          }
        }
        internal.windowTagMap = newTagMap;
        internal.windowOutputMap = newOutputMap;
      }

      // Check if window list changed
      const signature = JSON.stringify(windowList.map(w => w.id + w.workspaceId + w.isFocused));
      if (signature !== internal.lastWindowSignature) {
        internal.lastWindowSignature = signature;
        root.windows = windowList;
        root.windowListChanged();
      }

      if (newFocusedIdx !== root.focusedWindowIndex) {
        root.focusedWindowIndex = newFocusedIdx;
        root.activeWindowChanged();
      }
    }

    // ===== PROCESS SCALES =====

    function processScales(output) {
      const lines = output.trim().split('\n');

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        const match = line.match(scalePattern);

        if (match) {
          const outputName = match[1];
          const scale = parseFloat(match[2]);
          internal.monitorScales[outputName] = scale;
        }
      }

      const scalesMap = {};
      for (const name in internal.monitorScales) {
        scalesMap[name] = {
          name: name,
          scale: internal.monitorScales[name] || 1.0,
          width: 0,
          height: 0,
          x: 0,
          y: 0
        };
      }

      if (CompositorService && CompositorService.onDisplayScalesUpdated) {
        CompositorService.onDisplayScalesUpdated(scalesMap);
      }

      root.displayScalesChanged();
    }
  }

  // ===== DWL CONNECTIONS =====

  // React to DWL frame events on each output (atomic state updates)
  Instantiator {
    model: DwlIpc.outputs
    delegate: Connections {
      required property DwlIpcOutput modelData
      target: modelData

      function onFrame() {
        internal.rebuildWorkspaces();
        internal.updateWindows();
      }

      function onKbLayoutChanged() {
        if (KeyboardLayoutService) {
          KeyboardLayoutService.setCurrentLayout(modelData.kbLayout);
        }
      }
    }
  }

  // ===== PROCESSES =====

  // Scale query (mmsg -g -A) - DWL doesn't provide scale info
  property QtObject _scaleQuery: Process {
    id: scaleQuery
    command: ["mmsg", "-g", "-A"]

    property string buffer: ""

    stdout: SplitParser {
      onRead: line => {
                scaleQuery.buffer += line + "\n";
              }
    }

    onExited: code => {
                if (code === 0) {
                  internal.processScales(scaleQuery.buffer);
                  scaleQuery.buffer = "";
                }
              }
  }

  // ===== TOPLEVEL MANAGER CONNECTION =====

  property QtObject _toplevelConnection: Connections {
    target: ToplevelManager.toplevels

    function onValuesChanged() {
      internal.updateWindows();
    }
  }

  // ===== PUBLIC FUNCTIONS =====

  function initialize() {
    if (initialized) {
      return;
    }

    Logger.i("MangoService", "Initializing MangoWC/DWL compositor integration (DWL protocol)");

    // Query display scales (only thing still needing mmsg)
    scaleQuery.running = true;

    // Initial build from DWL state
    if (DwlIpc.available && DwlIpc.outputs.length > 0) {
      internal.rebuildWorkspaces();
      internal.updateWindows();
    }

    initialized = true;
  }

  function queryDisplayScales() {
    scaleQuery.running = true;
  }

  function switchToWorkspace(workspace) {
    const tagId = workspace.idx || workspace.id || 1;
    const outputName = workspace.output || root.selectedMonitor || "";

    // Use DWL protocol to switch tags
    const dwlOutput = DwlIpc.outputForName(outputName);
    if (dwlOutput) {
      dwlOutput.setTags(1 << (tagId - 1)); // tagId is 1-based, bitmask is 0-based
    } else {
      // Fallback to mmsg
      const cmd = ["mmsg", "-s", "-t", tagId.toString()];
      if (outputName && Object.keys(internal.monitorScales).length > 1) {
        cmd.push("-o", outputName);
      }
      Quickshell.execDetached(cmd);
    }
  }

  function focusWindow(window) {
    if (window && window.handle) {
      window.handle.activate();
    } else if (window.workspaceId) {
      switchToWorkspace({
                          id: window.workspaceId,
                          output: window.output
                        });
    }
  }

  function closeWindow(window) {
    if (window && window.handle) {
      window.handle.close();
    } else {
      Quickshell.execDetached(["mmsg", "-s", "-d", "killclient"]);
    }
  }

  function turnOffMonitors() {
    const screens = Quickshell.screens;
    const cmds = [];
    for (let i = 0; i < screens.length; i++) {
      cmds.push("mmsg -s -d disable_monitor," + screens[i].name);
    }
    if (cmds.length > 0) {
      Quickshell.execDetached(["sh", "-c", cmds.join(" && ")]);
    }
  }

  function turnOnMonitors() {
    const screens = Quickshell.screens;
    const cmds = [];
    for (let i = 0; i < screens.length; i++) {
      cmds.push("mmsg -s -d enable_monitor," + screens[i].name);
    }
    if (cmds.length > 0) {
      Quickshell.execDetached(["sh", "-c", cmds.join(" && ")]);
    }
  }

  function logout() {
    Quickshell.execDetached(["mmsg", "-s", "-q"]);
  }

  function cycleKeyboardLayout() {
    Logger.w("MangoService", "Keyboard layout cycling not supported");
  }

  function getFocusedScreen() {
    return null;
  }

  function spawn(command) {
    try {
      Quickshell.execDetached(["mmsg", "-s", "-d", "spawn_shell," + command.join(" ")]);
    } catch (e) {
      Logger.e("MangoService", "Failed to spawn command:", e);
    }
  }
}
