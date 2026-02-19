import QtQuick
import Quickshell
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

    // Tag states per output: Map<OutputName, Array<TagState>>
    // TagState: { id, state, clients, focused }
    property var tagStates: ({})

    // Active tag per output: Map<OutputName, TagID>
    property var activeTags: ({})

    // Focused window metadata from mmsg
    property string focusedTitle: ""
    property string focusedAppId: ""
    property string focusedOutput: ""

    // Window-to-tag persistence: Map<UniqueID, TagID>
    property var windowTagMap: ({})

    // Window-to-output persistence: Map<UniqueID, OutputName>
    property var windowOutputMap: ({})

    // Toplevel-to-ID mapping: Map<ToplevelObject, UniqueID>
    // This assigns each toplevel a stable ID on first encounter
    property var toplevelIdMap: new Map()
    property int windowIdCounter: 0

    // Output name to index mapping for unique workspace IDs
    property var outputIndices: ({})
    property int outputCounter: 0

    // Monitor scales: Map<OutputName, scale>
    property var monitorScales: ({})

    // Keyboard layout
    property string currentKbLayout: ""

    // Stream buffer for mmsg -w output
    property string streamBuffer: ""

    // Window signature for change detection
    property string lastWindowSignature: ""

    // ===== REGEX PATTERNS =====

    readonly property var patterns: QtObject {
      // Detailed tag format: "OUTPUT tag N STATE CLIENTS FOCUSED"
      readonly property var tagDetail: /^(\S+)\s+tag\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$/

                                       // Binary tag format: "OUTPUT tags <occ> <sel> <urg>"
                                       readonly property var tagBinary: /^(\S+)\s+tags\s+([01]+)\s+([01]+)\s+([01]+)$/

                                       // Layout: "OUTPUT layout SYMBOL"
                                       readonly property var layout: /^(\S+)\s+layout\s+(\S+)$/

                                       // Metadata: "OUTPUT title TEXT" or "OUTPUT appid TEXT"
                                       readonly property var metadata: /^(\S+)\s+(title|appid)\s+(.*)$/

                                       // Keyboard layout: "OUTPUT kb_layout NAME"
                                       readonly property var kbLayout: /^(\S+)\s+kb_layout\s+(.*)$/

                                       // Scale: "OUTPUT scale_factor FLOAT"
                                       readonly property var scale: /^(\S+)\s+scale_factor\s+(\d+(?:\.\d+)?)$/

                                       // Selected monitor: "OUTPUT selmon 1"
                                       readonly property var selmon: /^(\S+)\s+selmon\s+1$/
    }

    // ===== PROCESS TAG DATA =====

    function processTagData(output) {
      const lines = output.trim().split('\n');
      const newTagStates = {};
      const newActiveTags = {};
      const detailedOutputTags = {};  // Track which output+tag combinations we've seen in detailed format

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line) {
          continue;
        }

        // 1. Detailed tag format (preferred - has client counts)
        const detailMatch = line.match(patterns.tagDetail);
        if (detailMatch) {
          const outputName = detailMatch[1];
          const tagId = parseInt(detailMatch[2]);
          const state = parseInt(detailMatch[3]);
          const clients = parseInt(detailMatch[4]);
          const focused = parseInt(detailMatch[5]);

          if (!newTagStates[outputName]) {
            newTagStates[outputName] = [];
          }

          // Track that we've seen this specific tag in detailed format
          const key = `${outputName}-${tagId}`;
          detailedOutputTags[key] = true;

          const isActive = (state & 1) !== 0;
          const isUrgent = (state & 2) !== 0;

          if (isActive) {
            newActiveTags[outputName] = tagId;
          }

          newTagStates[outputName].push({
                                          id: tagId,
                                          state: state,
                                          clients: clients,
                                          focused: focused,
                                          isActive: isActive,
                                          isUrgent: isUrgent
                                        });
          continue;
        }

        // 2. Binary tag format (fallback - only use for tags we haven't seen in detailed format)
        const binaryMatch = line.match(patterns.tagBinary);
        if (binaryMatch) {
          const outputName = binaryMatch[1];

          const occ = binaryMatch[2];  // occupied tags
          const sel = binaryMatch[3];  // selected tags
          const urg = binaryMatch[4];  // urgent tags

          if (!newTagStates[outputName]) {
            newTagStates[outputName] = [];
          }

          // Parse binary strings (right-to-left indexing)
          for (let j = 0; j < occ.length; j++) {
            const tagId = j + 1;
            const charIdx = occ.length - 1 - j;

            // Skip if we already processed this tag in detailed format
            const key = `${outputName}-${tagId}`;
            if (detailedOutputTags[key]) {
              continue;
            }

            const isOccupied = occ[charIdx] === '1';
            const isActive = sel[charIdx] === '1';
            const isUrgent = urg[charIdx] === '1';

            if (isActive) {
              newActiveTags[outputName] = tagId;
            }

            newTagStates[outputName].push({
                                            id: tagId,
                                            state: (isActive ? 1 : 0) | (isUrgent ? 2 : 0),
                                            clients: isOccupied ? 1 : 0  // Approximate: 1 if occupied, 0 otherwise
                                                                  ,
                                            focused: 0,
                                            isActive: isActive,
                                            isUrgent: isUrgent
                                          });
          }
          continue;
        }

        // 3. Metadata (focused window title/appId)
        const metaMatch = line.match(patterns.metadata);
        if (metaMatch) {
          const outputName = metaMatch[1];
          const prop = metaMatch[2];
          const val = metaMatch[3];

          if (prop === "title") {
            internal.focusedTitle = val;
            internal.focusedOutput = outputName;
          } else if (prop === "appid") {
            internal.focusedAppId = val;
          }
          continue;
        }

        // 4. Layout
        const layoutMatch = line.match(patterns.layout);
        if (layoutMatch) {
          root.currentLayoutSymbol = layoutMatch[2];
          continue;
        }

        // 5. Keyboard layout
        const kbMatch = line.match(patterns.kbLayout);
        if (kbMatch) {
          const kbName = kbMatch[2];
          if (kbName !== internal.currentKbLayout) {
            internal.currentKbLayout = kbName;
            if (KeyboardLayoutService) {
              KeyboardLayoutService.setCurrentLayout(kbName);
            }
          }
          continue;
        }

        // 6. Selected monitor
        const selmonMatch = line.match(patterns.selmon);
        if (selmonMatch) {
          root.selectedMonitor = selmonMatch[1];
          continue;
        }
      }

      // Update state - MERGE instead of REPLACE to preserve other outputs' data
      for (const outputName in newTagStates) {
        internal.tagStates[outputName] = newTagStates[outputName];
      }
      for (const outputName in newActiveTags) {
        internal.activeTags[outputName] = newActiveTags[outputName];
      }

      // Rebuild workspaces
      internal.rebuildWorkspaces();

      // Update windows
      internal.updateWindows();
    }

    // ===== REBUILD WORKSPACES =====

    function rebuildWorkspaces() {
      const workspaceList = [];

      // Assign stable indices to new outputs
      for (const outputName in internal.tagStates) {
        if (internal.outputIndices[outputName] === undefined) {
          internal.outputIndices[outputName] = internal.outputCounter++;
          // Logger.d("MangoService", "Assigned index", internal.outputIndices[outputName], "to output", outputName);
        }
      }

      for (const outputName in internal.tagStates) {
        const tags = internal.tagStates[outputName];
        const outputIdx = internal.outputIndices[outputName];

        // Logger.d("MangoService", "Building workspaces for output", outputName, "- index:", outputIdx, "- tags:", tags.length);

        for (let i = 0; i < tags.length; i++) {
          const tag = tags[i];
          const isFocused = tag.isActive && (tag.focused === 1 || outputName === root.selectedMonitor);

          // Create unique workspace ID: outputIndex * 100 + tagId
          // This ensures each output's tags have non-overlapping IDs
          const uniqueId = outputIdx * 100 + tag.id;

          // Logger.d("MangoService", "  Workspace:", outputName, "tag", tag.id, "→ uniqueId:", uniqueId, "active:", tag.isActive, "occupied:", tag.clients > 0);

          workspaceList.push({
                               id: uniqueId,
                               idx: tag.id  // Keep original tag ID for switching
                                    ,
                               name: tag.id.toString(),
                               output: outputName,
                               isActive: tag.isActive,
                               isFocused: isFocused,
                               isUrgent: tag.isUrgent,
                               isOccupied: tag.clients > 0
                             });
        }
      }

      // Sort by tag ID, then by output name
      workspaceList.sort((a, b) => {
                           if (a.id !== b.id) {
                             return a.id - b.id;
                           }
                           return a.output.localeCompare(b.output);
                         });

      // Update ListModel
      root.workspaces.clear();
      for (let k = 0; k < workspaceList.length; k++) {
        root.workspaces.append(workspaceList[k]);
      }

      root.workspaceChanged();
    }

    // ===== UPDATE WINDOWS =====

    function updateWindows() {
      if (!ToplevelManager.toplevels) {
        return;
      }

      const toplevels = ToplevelManager.toplevels.values;
      const windowList = [];
      let newFocusedIdx = -1;
      const currentWindows = new Set();

      // Logger.d("MangoService", "updateWindows: Processing", toplevels.length, "toplevels");

      // Ensure all outputs seen in toplevels have indices assigned
      // This is needed because updateWindows() can be called before processTagData()
      for (let i = 0; i < toplevels.length; i++) {
        const toplevel = toplevels[i];
        if (!toplevel || toplevel.outliers) {
          continue;
        }

        if (toplevel.outputs && toplevel.outputs.length > 0) {
          const outputName = toplevel.outputs[0].name;
          if (internal.outputIndices[outputName] === undefined) {
            internal.outputIndices[outputName] = internal.outputCounter++;
            // Logger.d("MangoService", "updateWindows: Assigned index", internal.outputIndices[outputName], "to new output", outputName);
          }
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

        // Get or assign a unique ID for this toplevel window
        // Use a Map to track toplevel objects and assign stable IDs
        let windowId;
        if (internal.toplevelIdMap.has(toplevel)) {
          windowId = internal.toplevelIdMap.get(toplevel);
        } else {
          windowId = `win-${internal.windowIdCounter++}`;
          internal.toplevelIdMap.set(toplevel, windowId);
        }

        currentWindows.add(windowId);

        // Determine output using priority:
        // 1. Focused window with mmsg metadata (most reliable)
        // 2. Remembered output from previous focus
        // 3. toplevel.outputs (least reliable but still useful)
        let outputName;
        let outputSource = "unknown";

        // Priority 1: Currently focused with mmsg metadata
        if (isFocused && title === internal.focusedTitle && appId === internal.focusedAppId && internal.focusedOutput) {
          outputName = internal.focusedOutput;
          outputSource = "mmsg-focused";
          // Store this for future
          internal.windowOutputMap[windowId] = internal.focusedOutput;
          // Logger.d("MangoService", "    Storing output", internal.focusedOutput, "for", appId);
        } else
          // Priority 2: Previously remembered output (from past focus)
          if (internal.windowOutputMap[windowId]) {
            outputName = internal.windowOutputMap[windowId];
            outputSource = "remembered";
          } else
            // Priority 3: toplevel.outputs
            if (toplevel.outputs && toplevel.outputs.length > 0) {
              outputName = toplevel.outputs[0].name;
              outputSource = "toplevel.outputs";
            } else
              // Fallback: selected monitor
            {
              outputName = root.selectedMonitor || "DP-1";
              outputSource = "fallback";
            }

        // Logger.d("MangoService", "    Output for", appId, "=", outputName, "(source:", outputSource + ")");

        // Determine tag ID (not unique workspace ID yet)
        let tagId = null;  // null means unknown
        let tagSource = "unknown";

        if (isFocused && title === internal.focusedTitle && appId === internal.focusedAppId) {
          // This is the focused window - assign to active tag and remember it
          tagId = internal.activeTags[outputName] || 1;
          internal.windowTagMap[windowId] = tagId;
          tagSource = "focused";
        } else if (internal.windowTagMap[windowId] !== undefined) {
          // Window has a known tag - use it
          tagId = internal.windowTagMap[windowId];
          tagSource = "remembered";
        } else {
          // Unknown window - skip it (don't show in taskbar until we know its tag)
          continue;
        }

        // Convert to unique workspace ID using output index
        // We ensure outputIndices is populated above, so this should never be undefined
        const outputIdx = internal.outputIndices[outputName];
        if (outputIdx === undefined) {
          Logger.e("MangoService", "ERROR: No output index for", outputName, "- this should not happen!");
          continue;  // Skip this window
        }
        const workspaceId = outputIdx * 100 + tagId;

        // Logger.d("MangoService", "  Window:", appId, "on", outputName, "tag", tagId, "→ workspaceId:", workspaceId, "outputIdx:", outputIdx);

        const windowObj = {
          id: `${outputName}:${appId}:${title}:${i}`  // Unique ID using index
              ,
          title: title,
          appId: appId,
          class: appId,
          workspaceId: workspaceId,
          isFocused: isFocused,
          output: outputName,
          handle: toplevel,
          fullscreen: toplevel.fullscreen || false,
          floating: toplevel.maximized === false && toplevel.fullscreen === false
        };

        windowList.push(windowObj);

        if (isFocused) {
          newFocusedIdx = windowList.length - 1;
        }
      }

      // Clean up stale window tracking (keep map size reasonable)
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

        // Logger.d("MangoService", "===== FINAL WINDOW LIST (", windowList.length, "windows) =====");
        // for (let i = 0; i < windowList.length; i++) {
        //   const w = windowList[i];
        //   Logger.d("MangoService", "  [" + i + "]", w.appId, "output:", w.output, "workspaceId:", w.workspaceId);
        // }

        root.windows = windowList;
        root.windowListChanged();
      }

      // Update focused window index
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
        const match = line.match(patterns.scale);

        if (match) {
          const outputName = match[1];
          const scale = parseFloat(match[2]);
          internal.monitorScales[outputName] = scale;
        }
      }

      // Notify CompositorService
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

  // ===== PROCESSES =====

  // Event stream (mmsg -w)
  property QtObject _eventStream: Process {
    id: eventStream
    running: false
    command: ["mmsg", "-w"]

    stdout: SplitParser {
      onRead: line => {
                internal.streamBuffer += line + "\n";

                // Process frame when we get a binary tag line (signals end of frame)
                if (line.match(internal.patterns.tagBinary)) {
                  internal.processTagData(internal.streamBuffer);
                  internal.streamBuffer = "";
                }
              }
    }

    onExited: code => {
                if (code !== 0) {
                  restartTimer.start();
                }
              }
  }

  property QtObject _restartTimer: Timer {
    id: restartTimer
    interval: 1000
    onTriggered: {
      if (root.initialized) {
        eventStream.running = true;
      }
    }
  }

  // Initial tag query (mmsg -g -t)
  property QtObject _initialQuery: Process {
    id: initialQuery
    command: ["mmsg", "-g", "-t"]

    stdout: SplitParser {
      onRead: line => {
                internal.streamBuffer += line + "\n";
              }
    }

    onExited: code => {
                if (code === 0) {
                  internal.processTagData(internal.streamBuffer);
                  internal.streamBuffer = "";
                }
              }
  }

  // Scale query (mmsg -g -A)
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

  // Periodic update (safety net for missed events)
  property QtObject _updateTimer: Timer {
    interval: 500
    running: root.initialized
    repeat: true
    onTriggered: internal.updateWindows()
  }

  // ===== PUBLIC FUNCTIONS =====

  function initialize() {
    if (initialized) {
      return;
    }

    Logger.i("MangoService", "Initializing MangoWC/DWL compositor integration");

    // Start queries
    scaleQuery.running = true;
    initialQuery.running = true;
    eventStream.running = true;

    // Query monitors
    Quickshell.execDetached(["mmsg", "-g", "-o"]);

    initialized = true;
  }

  function queryDisplayScales() {
    scaleQuery.running = true;
  }

  function switchToWorkspace(workspace) {
    const tagId = workspace.idx || workspace.id || 1;
    const output = workspace.output || root.selectedMonitor || "";

    const cmd = ["mmsg", "-s", "-t", tagId.toString()];

    // Add output if multi-monitor
    if (output && Object.keys(internal.monitorScales).length > 1) {
      cmd.push("-o", output);
    }

    Quickshell.execDetached(cmd);
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

  function logout() {
    Quickshell.execDetached(["mmsg", "-s", "-q"]);
  }

  function cycleKeyboardLayout() {
    Logger.w("MangoService", "Keyboard layout cycling not supported");
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

  function spawn(command) {
    try {
      Quickshell.execDetached(["mmsg", "-s", "-d", "spawn_shell," + command.join(" ")]);
    } catch (e) {
      Logger.e("MangoService", "Failed to spawn command:", e);
    }
  }
}
