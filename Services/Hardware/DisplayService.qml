pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Hardware
import qs.Services.Compositor

Singleton
{
  id: root

  property bool awaitingConfirmation: false
  property string compositor: "niri"
  property string error: ""
  property bool loading: false

  property var outputs: ({})
  property var outputsList: []

  property var targetConfig: ({})

  property var pendingRevert: null
  property int revertCountdown: 0
  readonly property int revertTimeoutSec: 15

  property var commandQueue: []

  property bool edidLoading: false
  property string edidOutputName: ""
  property string edidHex: ""
  property string edidDecoded: ""
  property string edidError: ""
  property string edidDecodeError: ""
  property var edidSummary: ({})
  property int edidRequestId: 0

  function _getDisplayBackendHint() {
    if (typeof CompositorService === "undefined") return "fallback";
    if (CompositorService.isHyprland) return "hyprland";
    if (CompositorService.isNiri) return "niri";
    if (CompositorService.isSway) return "sway";
    return "fallback";
  }

  function _buildFetchScript() {
    const hint = _getDisplayBackendHint();
    const readonlyScript = _buildReadonlyFetchDataScript();

    if (hint === "hyprland") {
      return 'if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && command -v hyprctl >/dev/null 2>&1; then printf \'{"compositor":"hyprland", "data":%s}\\n\' "$(hyprctl monitors all -j)"; else printf \'{"compositor":"hyprland", "data":[]}\\n\'; fi';
    }

    if (hint === "niri") {
      return 'if [ -n "$NIRI_SOCKET" ] && command -v niri >/dev/null 2>&1; then printf \'{"compositor":"niri", "data":%s}\\n\' "$(niri msg --json outputs)"; else printf \'{"compositor":"niri", "data":[]}\\n\'; fi';
    }

    if (hint === "sway") {
      return 'if [ -n "$SWAYSOCK" ]; then msg="swaymsg"; desk=$(printf "%s" "${XDG_CURRENT_DESKTOP:-}" | tr "[:upper:]" "[:lower:]"); if printf "%s" "$desk" | grep -q "scroll" && command -v scrollmsg >/dev/null 2>&1; then msg="scrollmsg"; fi; if command -v "$msg" >/dev/null 2>&1; then printf \'{"compositor":"sway", "data":%s}\\n\' "$("$msg" -t get_outputs -r)"; else printf \'{"compositor":"sway", "data":[]}\\n\'; fi; else printf \'{"compositor":"sway", "data":[]}\\n\'; fi';
    }

    if (hint === "wlroots") {
      return 'if command -v wlr-randr >/dev/null 2>&1 && wlr-randr --json >/dev/null 2>&1; then printf \'{"compositor":"wlroots", "data":%s}\\n\' "$(wlr-randr --json)"; else printf \'{"compositor":"wlroots", "data":[]}\\n\'; fi';
    }

    if (hint === "readonly") {
      return readonlyScript;
    }

    // Fallback: try generic wlroots tooling, then readonly fallback.
    return 'if command -v wlr-randr >/dev/null 2>&1 && wlr-randr --json >/dev/null 2>&1; then printf \'{"compositor":"wlroots", "data":%s}\\n\' "$(wlr-randr --json)"; else ' + readonlyScript + ' fi';
  }

  function _buildReadonlyFetchDataScript() {
    return 'outputs="["; for dev in /sys/class/drm/card*-*; do if [ -e "$dev/status" ] && grep -q "^connected$" "$dev/status" 2>/dev/null; then name=$(basename "$dev" | cut -d"-" -f2-); mode=""; width=0; height=0; if [ -r "$dev/modes" ]; then mode=$(head -n1 "$dev/modes" 2>/dev/null | tr -d "\\r"); fi; case "$mode" in [0-9]*x[0-9]*) width=${mode%x*}; height=${mode#*x};; esac; outputs+="{\\"name\\":\\"$name\\",\\"enabled\\":true,\\"width\\":$width,\\"height\\":$height},"; fi; done; outputs="${outputs%,}]"; if [ "$outputs" = "]" ]; then outputs="[]"; fi; printf \'{"compositor":"readonly", "data":%s}\\n\' "$outputs";';
  }

  function _getScreenByOutputName(outputName) {
    const screens = Quickshell.screens || [];
    for (let i = 0; i < screens.length; i++) {
      const screen = screens[i];
      if (screen && screen.name === outputName)
        return screen;
    }
    return null;
  }

  function _getDdcModelByOutputName(outputName) {
    if (typeof BrightnessService === "undefined" || !BrightnessService.ddcMonitors)
      return "";

    const ddc = BrightnessService.ddcMonitors;
    for (let i = 0; i < ddc.length; i++) {
      const entry = ddc[i];
      if (entry && entry.connector === outputName && entry.model)
        return String(entry.model);
    }
    return "";
  }

  // Compositor Backends Layer
  property var _wlrootsBackend: ({
    _buildFullWlrCmd: function (targetConfig) {
      let cmd = ["wlr-randr"];
      for (const name in targetConfig) {
        const cfg = targetConfig[name];

        cmd.push("--output");
        cmd.push(name);

        if (cfg.enabled === false) {
          cmd.push("--off");
          continue;
        } else {
          cmd.push("--on");
        }

        if (cfg.modeStr) {
          cmd.push("--mode");
          cmd.push(cfg.modeStr);
        }
        if (cfg.scale !== undefined) {
          cmd.push("--scale");
          cmd.push(String(cfg.scale));
        }
        if (cfg.transform) {
          const tMap = {
            "Normal": "normal",
            "normal": "normal",
            "90": "90",
            "180": "180",
            "270": "270",
            "Flipped": "flipped",
            "flipped": "flipped",
            "Flipped90": "flipped-90",
            "flipped-90": "flipped-90",
            "Flipped180": "flipped-180",
            "flipped-180": "flipped-180",
            "Flipped270": "flipped-270",
            "flipped-270": "flipped-270"
          };
          cmd.push("--transform");
          cmd.push(tMap[cfg.transform] || "normal");
        }
        if (cfg.x !== undefined && cfg.y !== undefined) {
          cmd.push("--pos");
          cmd.push(Math.round(cfg.x) + "," + Math.round(cfg.y));
        }
        if (cfg.vrr_enabled !== undefined) {
          cmd.push("--adaptive-sync");
          cmd.push(cfg.vrr_enabled ? "enabled" : "disabled");
        }
      }
      return cmd.length > 1 ? [cmd] : [];
    },
    generateRevertCmds: function (snap) {
      return this._buildFullWlrCmd(snap);
    },
    parseFetch: function (rawData) {
      let data = {};
      for (let i = 0; i < rawData.length; i++) {
        const mon = rawData[i];

        let outData = {
          name: mon.name,
          enabled: mon.enabled !== false,
          make: mon.make || "",
          model: mon.model || "",
          vrr_enabled: mon.adaptive_sync === true,
          current_mode: 0,
          modes: []
        };

        let curWidth = 1920, curHeight = 1080;
        for (let j = 0; j < (mon.modes || []).length; j++) {
          const m = mon.modes[j];
          outData.modes.push({
            width: m.width,
            height: m.height,
            refresh_rate: Math.round(m.refresh * 1000)
          });
          if (m.current) {
            outData.current_mode = j;
            curWidth = m.width;
            curHeight = m.height;
          }
        }

        let applyRot = ["90", "270", "flipped-90", "flipped-270"].includes(mon.transform);
        let physW = applyRot ? curHeight : curWidth;
        let physH = applyRot ? curWidth : curHeight;

        outData.logical = {
          x: mon.position ? mon.position.x : 0,
          y: mon.position ? mon.position.y : 0,
          width: Math.floor(physW / (mon.scale || 1.0)),
          height: Math.floor(physH / (mon.scale || 1.0)),
          scale: mon.scale || 1.0
        };
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
        outData.logical.transform = tMap[mon.transform] || "Normal";

        data[mon.name] = outData;
      }
      return data;
    },
    buildSetModeCmd: function () {
      return this._buildFullWlrCmd(root.targetConfig);
    },
    buildSetScaleCmd: function () {
      return this._buildFullWlrCmd(root.targetConfig);
    },
    buildSetTransformCmd: function () {
      return this._buildFullWlrCmd(root.targetConfig);
    },
    buildSetVrrCmd: function () {
      return this._buildFullWlrCmd(root.targetConfig);
    },
    buildToggleOutputCmd: function () {
      return this._buildFullWlrCmd(root.targetConfig);
    },
    buildPositionsCmds: function (targetConfig) {
      return this._buildFullWlrCmd(targetConfig);
    }
  })

  property var _readonlyBackend: ({
    parseFetch: function (rawData) {
      let data = {};
      for (let i = 0; i < rawData.length; i++) {
        const mon = rawData[i];
        const screen = root._getScreenByOutputName(mon.name);
        const ddcModel = root._getDdcModelByOutputName(mon.name);

        let logicalWidth = parseInt(mon.width);
        let logicalHeight = parseInt(mon.height);
        if (isNaN(logicalWidth) || logicalWidth <= 0)
          logicalWidth = screen && screen.width ? screen.width : 1920;
        if (isNaN(logicalHeight) || logicalHeight <= 0)
          logicalHeight = screen && screen.height ? screen.height : 1080;

        const model = (screen && screen.model ? String(screen.model) : "") || ddcModel || "Display";
        data[mon.name] = {
          name: mon.name,
          enabled: mon.enabled !== false,
          make: "Unknown",
          model: model,
          vrr_supported: false,
          modes: [{width: logicalWidth, height: logicalHeight, refresh_rate: 60000}],
          current_mode: 0,
          logical: {x: 0, y: 0, width: logicalWidth, height: logicalHeight, scale: 1.0, transform: "Normal"}
        };
      }
      return data;
    },
    generateRevertCmds: function () {
      return [];
    },
    buildSetModeCmd: function () {
      return [];
    },
    buildSetScaleCmd: function () {
      return [];
    },
    buildSetTransformCmd: function () {
      return [];
    },
    buildSetVrrCmd: function () {
      return [];
    },
    buildToggleOutputCmd: function () {
      return [];
    },
    buildPositionsCmds: function () {
      return [];
    }
  })

  function getBackend() {
    const compositorBackend = typeof CompositorService !== "undefined" && CompositorService.getDisplayBackend ? CompositorService.getDisplayBackend() : null;
    if (compositorBackend)
      return compositorBackend;
    return root.compositor === "wlroots" ? _wlrootsBackend : _readonlyBackend;
  }

  // Geometry & Data Model Logic
  function _clampRange(desired, otherPos, otherSize, dragSize) {
    return Math.max(otherPos - dragSize + 1, Math.min(desired, otherPos + otherSize - 1));
  }

  function _isTouching(ax, ay, aw, ah, bx, by, bw, bh) {
    const tol = 5;
    if (Math.abs(ax + aw - bx) <= tol && ay < by + bh && ay + ah > by) return true;
    if (Math.abs(ax - (bx + bw)) <= tol && ay < by + bh && ay + ah > by) return true;
    if (Math.abs(ay + ah - by) <= tol && ax < bx + bw && ax + aw > bx) return true;
    if (Math.abs(ay - (by + bh)) <= tol && ax < bx + bw && ax + aw > bx) return true;
    return false;
  }

  function _getPredictedSizes(config) {
    const sizes = {};
    for (const out of root.outputsList) {
      const name = out.name;
      const cfg = config[name] || {};

      let physW = 1920, physH = 1080;
      if (cfg.enabled === false) {
        sizes[name] = {w: 0, h: 0};
        continue;
      }
      if (cfg.modeStr) {
        const parts = cfg.modeStr.split('@')[0].split('x');
        if (parts.length === 2) {
          physW = parseInt(parts[0]);
          physH = parseInt(parts[1]);
        }
      } else if (out.modes && out.modes[out.current_mode]) {
        physW = out.modes[out.current_mode].width;
        physH = out.modes[out.current_mode].height;
      }

      const t = cfg.transform || (out.logical ? out.logical.transform : "Normal");
      const applyRot = ["90", "270", "Flipped90", "Flipped270"].includes(t);
      const w = applyRot ? physH : physW;
      const h = applyRot ? physW : physH;

      const s = cfg.scale || (out.logical ? out.logical.scale : 1.0);
      sizes[name] = {w: Math.floor(w / s), h: Math.floor(h / s)};
    }
    return sizes;
  }

  function _normalizeLayoutEnforceAdjacency() {
    // Predict per-output logical sizes after pending mode/scale/transform changes.
    const sizes = _getPredictedSizes(root.targetConfig);
    const positions = {};
    const names = [];
    for (const name in root.targetConfig) {
      if (root.targetConfig[name] && root.targetConfig[name].enabled !== false) {
        positions[name] = {x: root.targetConfig[name].x, y: root.targetConfig[name].y};
        names.push(name);
      }
    }

    if (names.length <= 1) return;

    let changed = true;
    let iter = 0;
    // Reconnect disconnected components by moving the smallest-distance component edge.
    while (changed && iter < 5) {
      changed = false;
      iter++;

      let components = [];
      for (const name of names) {
        let foundComps = [];
        for (let i = 0; i < components.length; i++) {
          for (const other of components[i]) {
            if (_isTouching(positions[name].x, positions[name].y, sizes[name].w, sizes[name].h,
                positions[other].x, positions[other].y, sizes[other].w, sizes[other].h)) {
              foundComps.push(i);
              break;
            }
          }
        }
        if (foundComps.length === 0) {
          components.push([name]);
        } else {
          let targetComp = components[foundComps[0]];
          targetComp.push(name);
          for (let j = 1; j < foundComps.length; j++) {
            for (const item of components[foundComps[j]]) targetComp.push(item);
            components[foundComps[j]] = [];
          }
          components = components.filter(c => c.length > 0);
        }
      }

      if (components.length > 1) {
        const mainComp = components[0];
        let bestDist = Infinity;
        let bestMove = null;

        for (let i = 1; i < components.length; i++) {
          const comp = components[i];
          for (const target of comp) {
            for (const mainNode of mainComp) {
              const dp = positions[target];
              const ds = sizes[target];
              const op = positions[mainNode];
              const os = sizes[mainNode];

              const candidates = [
                {x: op.x + os.w, y: _clampRange(dp.y, op.y, os.h, ds.h)},
                {x: op.x - ds.w, y: _clampRange(dp.y, op.y, os.h, ds.h)},
                {x: _clampRange(dp.x, op.x, os.w, ds.w), y: op.y + os.h},
                {x: _clampRange(dp.x, op.x, os.w, ds.w), y: op.y - ds.h}
              ];

              for (const c of candidates) {
                const dist = Math.pow(c.x - dp.x, 2) + Math.pow(c.y - dp.y, 2);
                if (dist < bestDist) {
                  bestDist = dist;
                  bestMove = {compIdx: i, dx: c.x - dp.x, dy: c.y - dp.y};
                }
              }
            }
          }
        }

        if (bestMove) {
          const idx = bestMove.compIdx;
          for (const node of components[idx]) {
            positions[node].x += bestMove.dx;
            positions[node].y += bestMove.dy;
          }
          changed = true;
        }
      }
    }

    let minX = Infinity, minY = Infinity;
    for (const name in positions) {
      minX = Math.min(minX, positions[name].x);
      minY = Math.min(minY, positions[name].y);
    }

    // Rebase the layout so the top-left visible output starts at (0, 0).
    let newConfig = {};
    for (const name in root.targetConfig) {
      newConfig[name] = Object.assign({}, root.targetConfig[name]);
      if (positions[name]) {
        newConfig[name].x = Math.round(positions[name].x - minX);
        newConfig[name].y = Math.round(positions[name].y - minY);
      }
      if (sizes[name]) {
        newConfig[name].logicalWidth = sizes[name].w;
        newConfig[name].logicalHeight = sizes[name].h;
      }
    }
    root.targetConfig = newConfig;
  }

  function _applyTopologyChange(snap, cmds) {
    if (!_hasChangesComparedToCurrent()) {
      Logger.i("DisplayManager", "Topology change resulted in no actual changes. Ignoring.");
      return;
    }

    let allCmds = [];
    for (const c of cmds) allCmds.push(c);

    // Hyprland monitor transform keywords already carry position updates.
    const hasHyprTransformCmd = root.compositor === "hyprland" && allCmds.some(c => c && c.length >= 4 && c[0] === "hyprctl" && c[1] === "keyword" && c[2] === "monitor" && String(c[3]).indexOf(",transform,") >= 0);

    if (root.compositor !== "wlroots" && !hasHyprTransformCmd) {
      // For non-wlroots backends, append explicit position commands once per unique command.
      const posCmds = getBackend().buildPositionsCmds(root.targetConfig);
      for (const pc of posCmds) {
        let duplicate = false;
        for (const c of allCmds) {
          if (c.join(" ") === pc.join(" ")) {
            duplicate = true;
            break;
          }
        }
        if (!duplicate) allCmds.push(pc);
      }
    }

    for (const c of allCmds) enqueueCommand(c, snap);
  }

  function _countEnabledOutputs(config) {
    let count = 0;
    if (!config) return count;
    for (const name in config) {
      const cfg = config[name];
      if (cfg && cfg.enabled !== false) count++;
    }
    return count;
  }

  function _buildCurrentState(previousState) {
    const snap = {};
    for (const outputName in root.outputs) {
      const out = root.outputs[outputName];
      const prev = previousState && previousState[outputName] ? previousState[outputName] : null;
      let modeStr = null;
      if (out.modes && out.modes[out.current_mode]) {
        const m = out.modes[out.current_mode];
        modeStr = m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3);
      }
      if (!modeStr && prev && prev.modeStr) modeStr = prev.modeStr;

      const logical = out.logical || {};
      snap[outputName] = {
        modeStr: modeStr,
        enabled: out.enabled !== false,
        scale: logical.scale !== undefined ? logical.scale : (prev ? prev.scale : 1.0),
        transform: logical.transform !== undefined ? logical.transform : (prev ? prev.transform : "Normal"),
        x: logical.x !== undefined ? logical.x : (prev ? prev.x : 0),
        y: logical.y !== undefined ? logical.y : (prev ? prev.y : 0),
        logicalWidth: logical.width !== undefined ? logical.width : (prev ? prev.logicalWidth : 1920),
        logicalHeight: logical.height !== undefined ? logical.height : (prev ? prev.logicalHeight : 1080),
        vrr_enabled: out.vrr_enabled !== undefined ? out.vrr_enabled : (prev ? prev.vrr_enabled : false)
      };
    }
    return snap;
  }

  function snapshotAllOutputs() {
    return _buildCurrentState();
  }

  function _hasChangesComparedToCurrent() {
    const cur = _buildCurrentState();
    for (const name in cur) {
      const sc = cur[name];
      const tc = root.targetConfig[name];
      if (!tc) continue;
      if (sc.enabled !== tc.enabled) return true;
      if (sc.modeStr !== tc.modeStr) return true;
      if (Math.abs(sc.scale - tc.scale) > 0.01) return true;
      if (sc.transform !== tc.transform) return true;
      if (Math.round(sc.x) !== Math.round(tc.x)) return true;
      if (Math.round(sc.y) !== Math.round(tc.y)) return true;
      if (sc.vrr_enabled !== tc.vrr_enabled) return true;
    }
    return false;
  }

  // Snapshot & Revert Logic
  function startConfirmation(snapshot) {
    if (!root.awaitingConfirmation) {
      root.pendingRevert = snapshot;
      root.revertCountdown = root.revertTimeoutSec;
      root.awaitingConfirmation = true;
    }
  }

  function confirmChange() {
    root.awaitingConfirmation = false;
    root.pendingRevert = null;
    root.revertCountdown = 0;
  }

  function doRevert() {
    root.awaitingConfirmation = false;
    root.revertCountdown = 0;
    const snap = root.pendingRevert;
    root.pendingRevert = null;
    if (!snap) return;

    Logger.i("DisplayManager", "Reverting all outputs to previous snapshot");

    root.commandQueue = [];

    const curSnap = snapshotAllOutputs();
    const cmds = getBackend().generateRevertCmds(snap, curSnap);
    for (const cmd of cmds) {
      enqueueCommand(cmd, null);
    }
  }

  Timer {
    id: revertTimer
    interval: 1000
    repeat: true
    running: root.awaitingConfirmation
    onTriggered: {
      root.revertCountdown--;
      if (root.revertCountdown <= 0) {
        root.doRevert();
      }
    }
  }

  // Action Queue
  function enqueueCommand(cmd, snapshot) {
    if (cmd === null || cmd === undefined) return;
    let q = root.commandQueue;
    q.push(cmd);
    root.commandQueue = q;

    if (snapshot) startConfirmation(snapshot);
    root.processNextCommand();
  }

  Timer {
    id: queueSleepTimer
    repeat: false
    onTriggered: {
      root.processNextCommand();
    }
  }

  function processNextCommand() {
    if (!applyCommandProcess.running && !queueSleepTimer.running && root.commandQueue.length > 0) {
      let q = root.commandQueue;
      const nextCmd = q.shift();
      root.commandQueue = q;

      if (typeof nextCmd === "number") {
        queueSleepTimer.interval = nextCmd;
        queueSleepTimer.start();
      } else if (nextCmd && nextCmd.length > 0) {
        Logger.i("DisplayManager", "Queuing:", nextCmd.join(" "));
        applyCommandProcess.cmd = nextCmd;
        applyCommandProcess.running = true;
      } else {
        root.processNextCommand();
      }
    }
  }

  Timer {
    id: finishTimer
    interval: 50
    repeat: false
    onTriggered: {
      if (root.commandQueue.length > 0) {
        root.processNextCommand();
      } else {
        revertRefreshTimer.start();
      }
    }
  }

  Timer {
    id: revertRefreshTimer
    interval: 300
    repeat: false
    onTriggered: root.refresh()
  }

  Process {
    id: applyCommandProcess
    property var cmd: []
    command: cmd
    running: false

    onRunningChanged: {
      if (!running) {
        finishTimer.start();
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.e("DisplayManager", "Apply error:", text);
          root.error = text.trim();
          root.commandQueue = []; // HALT ON ERROR
        }
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        Logger.i("DisplayManager", "Apply output:", text);
      }
    }
  }

  // Public APIs
  function refresh() {
    root.loading = true;
    root.error = "";
    fetchProcess.running = true;
  }

  function _makeEmptyEdidSummary(outputName) {
    return {
      output: String(outputName || ""),
      source: "",
      parseStatus: "idle",
      monitorName: "",
      manufacturerId: "",
      productCode: "",
      serialText: "",
      serialNumber: "",
      week: null,
      year: null,
      version: "",
      inputType: "",
      sizeCm: {width: null, height: null},
      preferredMode: "",
      warnings: []
    };
  }

  function _extractEdidField(text, patterns) {
    for (let i = 0; i < patterns.length; i++) {
      const m = String(text || "").match(patterns[i]);
      if (!m) continue;
      for (let j = 1; j < m.length; j++) {
        if (m[j] !== undefined && String(m[j]).trim() !== "")
          return String(m[j]).trim();
      }
    }
    return "";
  }

  function _splitDecodedEdidOutput(rawText) {
    const marker = "__EDID_SOURCE__:";
    const full = String(rawText || "").trim();
    if (full.indexOf(marker) !== 0)
      return {source: "", text: full};

    const lines = full.split("\n");
    const firstLine = lines.shift() || "";
    return {
      source: firstLine.slice(marker.length).trim(),
      text: lines.join("\n").trim()
    };
  }

  function _buildEdidSummary(decodedText, outputName, source, parseStatus) {
    const text = String(decodedText || "");
    const summary = _makeEmptyEdidSummary(outputName);
    summary.source = String(source || "");
    summary.parseStatus = String(parseStatus || "decoded");

    if (text.trim() === "")
      return summary;

    summary.monitorName = _extractEdidField(text, [
      /Display Product Name:\s*([^\n\r]+)/i,
      /Monitor name:\s*([^\n\r]+)/i,
      /ModelName\s+"([^"]+)"/i
    ]);
    summary.manufacturerId = _extractEdidField(text, [
      /Manufacturer:\s*([A-Za-z0-9]{3})\b/i,
      /VendorName\s+"([^"]+)"/i
    ]);
    summary.productCode = _extractEdidField(text, [
      /Product(?:\s+ID|\s+Code)\s*:\s*([^\n\r]+)/i,
      /Model:\s*([^\n\r]+)/i,
      /Model\s+0x([0-9a-f]+)/i
    ]);
    summary.serialText = _extractEdidField(text, [
      /Display Product Serial Number:\s*([^\n\r]+)/i,
      /Serial Number:\s*([^\n\r]+)/i,
      /Serial Number\s+"([^"]+)"/i,
      /Identifier\s+"([^"]+)"/i
    ]);
    summary.serialNumber = _extractEdidField(text, [
      /Serial number:\s*([^\n\r]+)/i
    ]);
    summary.version = _extractEdidField(text, [
      /EDID(?:\s+Version)?\s*:?\s*([0-9]+\.[0-9]+)/i
    ]);
    summary.inputType = _extractEdidField(text, [
      /Input type:\s*([^\n\r]+)/i
    ]);
    summary.preferredMode = _extractEdidField(text, [
      /Preferred\s+timing[^\n\r]*?:\s*([^\n\r]+)/i,
      /Preferred mode:\s*([^\n\r]+)/i,
      /DTD\s+1:\s*([^\n\r]+)/i,
      /Modeline\s+"([^"]+)"/i
    ]);

    const madeMatch = text.match(/Made\s+in:\s+week\s+([0-9]+)\s+of\s+([0-9]{4})/i);
    if (madeMatch) {
      const weekNum = parseInt(madeMatch[1], 10);
      const yearNum = parseInt(madeMatch[2], 10);
      summary.week = isNaN(weekNum) ? null : weekNum;
      summary.year = isNaN(yearNum) ? null : yearNum;
    } else {
      const weekNum = parseInt(_extractEdidField(text, [/Manufacture\s+week:\s*([0-9]+)/i]), 10);
      const yearNum = parseInt(_extractEdidField(text, [/Manufacture\s+year:\s*([0-9]{4})/i]), 10);
      summary.week = isNaN(weekNum) ? null : weekNum;
      summary.year = isNaN(yearNum) ? null : yearNum;
    }

    const sizeCm = text.match(/Maximum\s+image\s+size:\s*([0-9]+)\s*cm\s*x\s*([0-9]+)\s*cm/i);
    if (sizeCm) {
      summary.sizeCm.width = parseInt(sizeCm[1], 10);
      summary.sizeCm.height = parseInt(sizeCm[2], 10);
    } else {
      const sizeMm = text.match(/DisplaySize\s+([0-9]+)\s+([0-9]+)/i);
      if (sizeMm) {
        const widthMm = parseInt(sizeMm[1], 10);
        const heightMm = parseInt(sizeMm[2], 10);
        if (!isNaN(widthMm) && !isNaN(heightMm)) {
          summary.sizeCm.width = Math.round(widthMm / 10);
          summary.sizeCm.height = Math.round(heightMm / 10);
        }
      }
    }

    const warnings = [];
    const lines = text.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line !== "" && /(warning|fail)/i.test(line)) {
        warnings.push(line);
        if (warnings.length >= 5)
          break;
      }
    }
    summary.warnings = warnings;

    return summary;
  }

  function _startEdidDecode(rawHex, outputName, requestId) {
    const normalizedHex = String(rawHex || "").replace(/\s+/g, "").toLowerCase();
    root.edidDecoded = "";
    root.edidDecodeError = "";
    root.edidSummary = _makeEmptyEdidSummary(outputName);
    root.edidSummary.parseStatus = "decoding";

    if (normalizedHex === "") {
      root.edidDecodeError = "Empty EDID payload";
      root.edidSummary.parseStatus = "decode_error";
      root.edidLoading = false;
      return;
    }

    if (edidDecodeProcess.running)
      edidDecodeProcess.running = false;

    edidDecodeProcess.requestId = requestId;
    edidDecodeProcess.outputName = outputName;
    edidDecodeProcess.decodedStdout = "";
    edidDecodeProcess.decodeStderr = "";
    edidDecodeProcess.command = [
      "bash",
      "-c",
      'hex=$(printf "%s" "$1" | tr -d "[:space:]"); if [ -z "$hex" ]; then echo "Empty EDID hex payload" >&2; exit 1; fi; tmp=$(mktemp); cleanup(){ rm -f "$tmp"; }; trap cleanup EXIT; if command -v xxd >/dev/null 2>&1; then if ! printf "%s" "$hex" | xxd -r -p > "$tmp" 2>/dev/null; then echo "Failed to decode EDID hex" >&2; exit 2; fi; elif command -v python3 >/dev/null 2>&1; then if ! python3 - "$hex" "$tmp" <<"PY"\nimport pathlib\nimport sys\nhex_data = sys.argv[1].strip()\nout_path = pathlib.Path(sys.argv[2])\ntry:\n    out_path.write_bytes(bytes.fromhex(hex_data))\nexcept ValueError:\n    sys.exit(1)\nPY\n then echo "Failed to decode EDID hex" >&2; exit 2; fi; else echo "Need xxd or python3 to decode EDID hex" >&2; exit 3; fi; if command -v edid-decode >/dev/null 2>&1; then echo "__EDID_SOURCE__:edid-decode"; edid-decode "$tmp"; elif command -v parse-edid >/dev/null 2>&1; then echo "__EDID_SOURCE__:parse-edid"; parse-edid < "$tmp"; else echo "No external EDID decoder found (install edid-decode or parse-edid)" >&2; exit 127; fi',
      "sh",
      normalizedHex
    ];
    edidDecodeProcess.running = true;
  }

  function readEdid(outputName) {
    const out = String(outputName || "").trim();
    if (out === "") {
      root.edidError = "Invalid output name";
      root.edidHex = "";
      root.edidDecoded = "";
      root.edidDecodeError = "";
      root.edidSummary = _makeEmptyEdidSummary("");
      root.edidSummary.parseStatus = "read_error";
      root.edidLoading = false;
      return;
    }

    root.edidRequestId++;
    const requestId = root.edidRequestId;

    root.edidOutputName = out;
    root.edidHex = "";
    root.edidDecoded = "";
    root.edidError = "";
    root.edidDecodeError = "";
    root.edidSummary = _makeEmptyEdidSummary(out);
    root.edidSummary.parseStatus = "loading";
    root.edidLoading = true;

    if (edidReadProcess.running)
      edidReadProcess.running = false;
    if (edidDecodeProcess.running)
      edidDecodeProcess.running = false;

    edidReadProcess.requestId = requestId;
    edidReadProcess.outputName = out;
    edidReadProcess.rawHex = "";
    edidReadProcess.readStderr = "";
    edidReadProcess.command = [
      "bash",
      "-c",
      'name="$1"; path=""; for p in /sys/class/drm/card*-"$name"/edid; do if [ -r "$p" ]; then path="$p"; break; fi; done; if [ -z "$path" ]; then echo "EDID file not found for output: $name" >&2; exit 1; fi; if command -v xxd >/dev/null 2>&1; then xxd -p -c 32 "$path"; elif command -v hexdump >/dev/null 2>&1; then hexdump -ve "1/1 \"%02x\"" "$path"; else od -An -tx1 -v "$path" | tr -d " \n"; fi',
      "sh",
      out
    ];
    edidReadProcess.running = true;
  }

  function setMode(outputName, modeStr) {
    if (!root.targetConfig[outputName]) return;
    const snap = root.pendingRevert ? root.pendingRevert : snapshotAllOutputs();
    root.targetConfig[outputName].modeStr = modeStr;
    _normalizeLayoutEnforceAdjacency();
    const cmds = getBackend().buildSetModeCmd(outputName, root.targetConfig[outputName]);
    _applyTopologyChange(snap, cmds);
  }

  function setPositionNormalized(draggedOutput, newX, newY) {
    if (_countEnabledOutputs(root.targetConfig) <= 1) {
      return;
    }

    const outputs = root.outputsList;
    if (!outputs || outputs.length === 0) return;

    // Build a temporary topology using current logical rectangles plus dragged target.
    const positions = {};
    const sizes = {};
    for (const out of outputs) {
      const lw = out.logical ? out.logical.width : 1920;
      const lh = out.logical ? out.logical.height : 1080;
      sizes[out.name] = {w: lw, h: lh};
      if (out.name === draggedOutput) {
        positions[out.name] = {x: Math.round(newX), y: Math.round(newY)};
      } else {
        positions[out.name] = {x: out.logical ? out.logical.x : 0, y: out.logical ? out.logical.y : 0};
      }
    }

    if (Object.keys(positions).length > 1) {
      const dp = positions[draggedOutput];
      const ds = sizes[draggedOutput];
      let touching = false;

      for (const name in positions) {
        if (name === draggedOutput) continue;
        if (_isTouching(dp.x, dp.y, ds.w, ds.h, positions[name].x, positions[name].y, sizes[name].w, sizes[name].h)) {
          touching = true;
          break;
        }
      }

      // If detached, snap the dragged output to the nearest touching edge of any sibling.
      if (!touching) {
        let bestDist = Infinity;
        let bestPos = {x: dp.x, y: dp.y};

        for (const name in positions) {
          if (name === draggedOutput) continue;
          const op = positions[name];
          const os = sizes[name];

          const candidates = [
            {x: op.x + os.w, y: _clampRange(dp.y, op.y, os.h, ds.h)},
            {x: op.x - ds.w, y: _clampRange(dp.y, op.y, os.h, ds.h)},
            {x: _clampRange(dp.x, op.x, os.w, ds.w), y: op.y + os.h},
            {x: _clampRange(dp.x, op.x, os.w, ds.w), y: op.y - ds.h}
          ];

          for (const c of candidates) {
            const dist = Math.pow(c.x - dp.x, 2) + Math.pow(c.y - dp.y, 2);
            if (dist < bestDist) {
              bestDist = dist;
              bestPos = c;
            }
          }
        }

        positions[draggedOutput] = {x: Math.round(bestPos.x), y: Math.round(bestPos.y)};
        Logger.i("DisplayManager", "Adjacency enforced: moved", draggedOutput, "to", bestPos.x, bestPos.y);
      }
    }

    // Normalize all coordinates back into a non-negative layout space.
    let minX = Infinity, minY = Infinity;
    for (const name in positions) {
      minX = Math.min(minX, positions[name].x);
      minY = Math.min(minY, positions[name].y);
    }

    // Apply global minimum constraints and update target model
    let newConfig = {};
    for (const name in root.targetConfig) {
      newConfig[name] = Object.assign({}, root.targetConfig[name]);
      if (positions[name]) {
        newConfig[name].x = positions[name].x - minX;
        newConfig[name].y = positions[name].y - minY;
      }
      if (sizes[name]) {
        newConfig[name].logicalWidth = sizes[name].w;
        newConfig[name].logicalHeight = sizes[name].h;
      }
    }
    root.targetConfig = newConfig;

    if (!_hasChangesComparedToCurrent()) {
      Logger.i("DisplayManager", "Position normalization resulted in no changes.");
      return;
    }

    const snap = root.pendingRevert ? root.pendingRevert : snapshotAllOutputs();
    const cmds = getBackend().buildPositionsCmds(root.targetConfig);
    for (const c of cmds) enqueueCommand(c, snap);

    if (root.compositor === "hyprland" || root.compositor === "wlroots") {
      enqueueCommand(250, null);
      for (const c of cmds) enqueueCommand(c, null);
    }
  }

  function setScale(outputName, scale) {
    if (!root.targetConfig[outputName]) return;
    const snap = root.pendingRevert ? root.pendingRevert : snapshotAllOutputs();
    root.targetConfig[outputName].scale = scale;
    _normalizeLayoutEnforceAdjacency();
    const cmds = getBackend().buildSetScaleCmd(outputName, root.targetConfig[outputName]);
    _applyTopologyChange(snap, cmds);
  }

  function setTransform(outputName, transform) {
    if (!root.targetConfig[outputName]) return;
    const snap = root.pendingRevert ? root.pendingRevert : snapshotAllOutputs();
    root.targetConfig[outputName].transform = transform;
    _normalizeLayoutEnforceAdjacency();
    const cmds = getBackend().buildSetTransformCmd(outputName, root.targetConfig[outputName]);
    _applyTopologyChange(snap, cmds);
  }

  function setVrr(outputName, enabled) {
    if (!root.targetConfig[outputName]) return;
    const snap = root.pendingRevert ? root.pendingRevert : snapshotAllOutputs();
    root.targetConfig[outputName].vrr_enabled = enabled;
    const cmds = getBackend().buildSetVrrCmd(outputName, root.targetConfig[outputName]);
    for (const c of cmds) enqueueCommand(c, snap);
  }

  function toggleOutput(outputName, enabled) {
    if (!root.targetConfig[outputName]) return;
    if (!enabled && root.targetConfig[outputName].enabled !== false && _countEnabledOutputs(root.targetConfig) <= 1) {
      Logger.w("DisplayManager", "Refusing to disable the last enabled output:", outputName);
      return;
    }
    const snap = root.pendingRevert ? root.pendingRevert : snapshotAllOutputs();
    root.targetConfig[outputName].enabled = enabled;
    _normalizeLayoutEnforceAdjacency();
    const cmds = getBackend().buildToggleOutputCmd(outputName, enabled);
    _applyTopologyChange(snap, cmds);
  }

  Process {
    id: edidReadProcess
    property int requestId: 0
    property string outputName: ""
    property string rawHex: ""
    property string readStderr: ""
    command: []
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        if (edidReadProcess.requestId !== root.edidRequestId)
          return;

        const raw = String(text || "").replace(/\s+/g, "").toLowerCase();
        if (raw.length > 0) {
          edidReadProcess.rawHex = raw;
          root.edidError = "";
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (edidReadProcess.requestId !== root.edidRequestId)
          return;

        const err = text.trim();
        if (err.length > 0)
          edidReadProcess.readStderr = err;
      }
    }

    onExited: function (exitCode) {
      if (edidReadProcess.requestId !== root.edidRequestId)
        return;

      const raw = String(edidReadProcess.rawHex || "").trim();
      if (exitCode !== 0 || raw === "") {
        root.edidError = edidReadProcess.readStderr !== "" ? edidReadProcess.readStderr : "Failed to read EDID";
        root.edidHex = "";
        root.edidDecoded = "";
        root.edidDecodeError = "";
        root.edidSummary = _makeEmptyEdidSummary(edidReadProcess.outputName);
        root.edidSummary.parseStatus = "read_error";
        root.edidLoading = false;
        return;
      }

      root.edidHex = raw;
      root.edidError = "";
      root._startEdidDecode(raw, edidReadProcess.outputName, edidReadProcess.requestId);
    }
  }

  Process {
    id: edidDecodeProcess
    property int requestId: 0
    property string outputName: ""
    property string decodedStdout: ""
    property string decodeStderr: ""
    command: []
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        if (edidDecodeProcess.requestId !== root.edidRequestId)
          return;
        edidDecodeProcess.decodedStdout = text;
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (edidDecodeProcess.requestId !== root.edidRequestId)
          return;
        const err = text.trim();
        if (err.length > 0)
          edidDecodeProcess.decodeStderr = err;
      }
    }

    onExited: function (exitCode) {
      if (edidDecodeProcess.requestId !== root.edidRequestId)
        return;

      if (exitCode === 0) {
        const payload = root._splitDecodedEdidOutput(edidDecodeProcess.decodedStdout);
        const decoded = String(payload.text || "").trim();
        root.edidDecoded = decoded;
        root.edidDecodeError = "";
        root.edidSummary = root._buildEdidSummary(
          decoded,
          edidDecodeProcess.outputName,
          payload.source,
          decoded !== "" ? "decoded" : "decoded_empty"
        );
      } else {
        const errText = String(edidDecodeProcess.decodeStderr || "").trim();
        const decodeError = errText !== "" ? errText : "Failed to decode EDID";
        root.edidDecoded = "";
        root.edidDecodeError = decodeError;
        root.edidSummary = root._buildEdidSummary(
          "",
          edidDecodeProcess.outputName,
          "",
          exitCode === 127 ? "decoder_unavailable" : "decode_error"
        );
        root.edidSummary.warnings = [decodeError];
      }

      root.edidLoading = false;
    }
  }

  Component.onCompleted: {
    Logger.i("DisplayService", "Service started with backend:", root._getDisplayBackendHint());
    refresh();
  }

  Connections {
    target: typeof CompositorService !== "undefined" ? CompositorService : null

    function onBackendChanged() {
      if (root.loading) return;
      root.refresh();
    }
  }

  Process {
    id: fetchProcess
    command: ["bash", "-c", root._buildFetchScript()]
    running: false

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.e("DisplayManager", "Error fetching outputs:", text);
          root.error = text.trim();
        }
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          // Keep previous target values as fallback when backend omits fields transiently.
          const previousTarget = root.targetConfig;
          const payload = JSON.parse(text);
          root.compositor = payload.compositor || "niri";
          // root.compositor = "readonly";
          const data = getBackend().parseFetch(payload.data);

          root.outputs = data;
          const list = [];
          for (const key in data) {
            const out = data[key];
            out._key = key;
            list.push(out);
          }
          list.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
          root.outputsList = list;
          root.targetConfig = root._buildCurrentState(previousTarget);
        } catch (e) {
          Logger.e("DisplayManager", "Failed to parse outputs:", e, "Text:", text);
          root.error = "Failed to parse output data";
        } finally {
          root.loading = false;
        }
      }
    }
  }

}
