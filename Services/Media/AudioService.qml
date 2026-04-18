pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Services.System

Singleton {
  id: root

  // Rate limiting for volume feedback (minimum 100ms between sounds)
  property var lastVolumeFeedbackTime: 0
  readonly property int minVolumeFeedbackInterval: 100

  // Track the last sink that produced volume feedback so we can suppress the
  // initial onVolumeChanged that fires on startup and device switches.
  property PwNode _lastFeedbackSink: null

  // Devices
  readonly property var sink: Pipewire.ready ? Pipewire.defaultAudioSink : null
  readonly property var source: validatedSource
  readonly property bool hasInput: !!source
  readonly property list<PwNode> sinks: deviceNodes.sinks
  readonly property list<PwNode> sources: deviceNodes.sources
  readonly property real maxVolume: Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
  readonly property real epsilon: 0.005

  // Fallback state sourced from wpctl when PipeWire node values go stale.
  property bool wpctlAvailable: false
  property bool wpctlStateValid: false
  property real wpctlOutputVolume: 0
  property bool wpctlOutputMuted: true
  property bool wpctlInputStateValid: false
  property real wpctlInputVolume: 0
  property bool wpctlInputMuted: true

  signal volumeAtMaximum
  signal volumeAtMinimum

  function clampOutputVolume(vol: real): real {
    if (vol === undefined || isNaN(vol)) {
      return 0;
    }
    return Math.max(0, Math.min(root.maxVolume, vol));
  }

  function refreshWpctlOutputState(): void {
    if (!wpctlAvailable || wpctlStateProcess.running) {
      return;
    }
    wpctlStateProcess.command = ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"];
    wpctlStateProcess.running = true;
  }

  function refreshWpctlInputState(): void {
    if (!wpctlAvailable || wpctlInputStateProcess.running) {
      return;
    }
    wpctlInputStateProcess.command = ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"];
    wpctlInputStateProcess.running = true;
  }

  function applyWpctlOutputState(raw: string): bool {
    const text = String(raw || "").trim();
    const match = text.match(/Volume:\s*([0-9]*\.?[0-9]+)/i);
    if (!match || match.length < 2) {
      return false;
    }

    const parsedVolume = Number(match[1]);
    if (isNaN(parsedVolume)) {
      return false;
    }

    wpctlOutputVolume = clampOutputVolume(parsedVolume);
    wpctlOutputMuted = /\[MUTED\]/i.test(text);
    wpctlStateValid = true;
    return true;
  }

  function applyWpctlInputState(raw: string): bool {
    const text = String(raw || "").trim();
    const match = text.match(/Volume:\s*([0-9]*\.?[0-9]+)/i);
    if (!match || match.length < 2) {
      return false;
    }

    const parsedVolume = Number(match[1]);
    if (isNaN(parsedVolume)) {
      return false;
    }

    wpctlInputVolume = Math.max(0, Math.min(root.maxVolume, parsedVolume));
    wpctlInputMuted = /\[MUTED\]/i.test(text);
    wpctlInputStateValid = true;
    return true;
  }

  // Output volume (prefer wpctl state when available)
  readonly property real volume: {
    if (wpctlAvailable && wpctlStateValid) {
      return clampOutputVolume(wpctlOutputVolume);
    }

    if (!sink?.audio) {
      return 0;
    }
    return clampOutputVolume(sink.audio.volume);
  }
  readonly property bool muted: {
    if (wpctlAvailable && wpctlStateValid) {
      return wpctlOutputMuted;
    }
    return sink?.audio?.muted ?? true;
  }

  // Input volume (prefer wpctl state when available — matches set-volume % round-trip)
  readonly property real inputVolume: {
    if (wpctlAvailable && wpctlInputStateValid) {
      return Math.max(0, Math.min(root.maxVolume, wpctlInputVolume));
    }
    if (!source?.audio) {
      return 0;
    }
    const vol = source.audio.volume;
    if (vol === undefined || isNaN(vol)) {
      return 0;
    }
    return Math.max(0, Math.min(root.maxVolume, vol));
  }
  readonly property bool inputMuted: {
    if (wpctlAvailable && wpctlInputStateValid) {
      return wpctlInputMuted;
    }
    return source?.audio?.muted ?? true;
  }

  // Allow callers to skip the next OSD notification when they are already
  // presenting volume state (e.g. the Audio Panel UI). We track this as a short
  // time window so suppression applies to every monitor, not just the first one
  // that receives the signal.
  property double outputOSDSuppressedUntilMs: 0
  property double inputOSDSuppressedUntilMs: 0

  function suppressOutputOSD(durationMs = 400) {
    const target = Date.now() + durationMs;
    outputOSDSuppressedUntilMs = Math.max(outputOSDSuppressedUntilMs, target);
  }

  function suppressInputOSD(durationMs = 400) {
    const target = Date.now() + durationMs;
    inputOSDSuppressedUntilMs = Math.max(inputOSDSuppressedUntilMs, target);
  }

  function consumeOutputOSDSuppression(): bool {
    return Date.now() < outputOSDSuppressedUntilMs;
  }

  function consumeInputOSDSuppression(): bool {
    return Date.now() < inputOSDSuppressedUntilMs;
  }

  readonly property real stepVolume: Settings.data.audio.volumeStep / 100.0

  // Filtered device nodes (non-stream sinks and sources)
  readonly property var deviceNodes: Pipewire.ready ? Pipewire.nodes.values.reduce((acc, node) => {
                                                                                     if (!node.isStream) {
                                                                                       // Filter out quickshell nodes (unlikely to be devices, but for consistency)
                                                                                       const name = node.name || "";
                                                                                       const mediaName = (node.properties && node.properties["media.name"]) || "";
                                                                                       if (name === "quickshell" || mediaName === "quickshell") {
                                                                                         return acc;
                                                                                       }

                                                                                       if (node.isSink) {
                                                                                         acc.sinks.push(node);
                                                                                       } else if (node.audio) {
                                                                                         acc.sources.push(node);
                                                                                       }
                                                                                     }
                                                                                     return acc;
                                                                                   }, {
                                                                                     "sources": [],
                                                                                     "sinks": []
                                                                                   }) : {
                                                        "sources": [],
                                                        "sinks": []
                                                      }

  // Validated source (ensures it's a proper audio source, not a sink)
  readonly property var validatedSource: {
    if (!Pipewire.ready) {
      return null;
    }
    const raw = Pipewire.defaultAudioSource;
    if (!raw || raw.isSink || !raw.audio) {
      return null;
    }
    // Optional: check type if available (type reflects media.class per docs)
    if (raw.type && typeof raw.type === "string" && !raw.type.startsWith("Audio/Source")) {
      return null;
    }
    return raw;
  }

  // Internal state for feedback loop prevention
  property bool isSettingOutputVolume: false
  property bool isSettingInputVolume: false

  // Bind default sink and source to ensure their properties are available
  PwObjectTracker {
    id: sinkTracker
    objects: root.sink ? [root.sink] : []
  }

  PwObjectTracker {
    id: sourceTracker
    objects: root.source ? [root.source] : []
  }

  // Track links to the default sink to find active streams
  PwNodeLinkTracker {
    id: sinkLinkTracker
  }

  onSinkChanged: {
    if (root.sink) {
      sinkLinkTracker.node = root.sink;
    }
  }

  // Track all streams globally to prevent binding loops for filtered out streams
  readonly property var streamNodes: Pipewire.ready ? Pipewire.nodes.values.filter(n => n && n.isStream) : []

  // Find application streams that are connected to the default sink
  readonly property var appStreams: {
    if (!Pipewire.ready || !root.sink) {
      return [];
    }

    var connectedStreamIds = {};
    var connectedStreams = [];

    // Use PwNodeLinkTracker to get properly bound link groups
    if (!sinkLinkTracker.linkGroups) {
      return [];
    }

    var linkGroupsCount = 0;
    if (sinkLinkTracker.linkGroups.length !== undefined) {
      linkGroupsCount = sinkLinkTracker.linkGroups.length;
    } else if (sinkLinkTracker.linkGroups.count !== undefined) {
      linkGroupsCount = sinkLinkTracker.linkGroups.count;
    } else {
      return [];
    }

    if (linkGroupsCount === 0) {
      return [];
    }

    var intermediateNodeIds = {};
    var nodesToCheck = [];

    for (var i = 0; i < linkGroupsCount; i++) {
      var linkGroup;
      if (sinkLinkTracker.linkGroups.get) {
        linkGroup = sinkLinkTracker.linkGroups.get(i);
      } else {
        linkGroup = sinkLinkTracker.linkGroups[i];
      }

      if (!linkGroup || !linkGroup.source) {
        continue;
      }

      var sourceNode = linkGroup.source;

      // Filter out quickshell
      const name = sourceNode.name || "";
      const mediaName = (sourceNode.properties && sourceNode.properties["media.name"]) || "";
      if (name === "quickshell" || mediaName === "quickshell") {
        continue;
      }

      // Filter out filter (intermediate) streams
      const isVirtual = (sourceNode.properties && sourceNode.properties["node.virtual"]) || "";
      // If it's an application stream node, add it directly
      if (sourceNode.isStream && sourceNode.audio && !isVirtual) {
        if (!connectedStreamIds[sourceNode.id]) {
          connectedStreamIds[sourceNode.id] = true;
          connectedStreams.push(sourceNode);
        }
      } else {
        // Not a stream - this is an intermediate node, track it
        intermediateNodeIds[sourceNode.id] = true;
        nodesToCheck.push(sourceNode);
      }
    }

    // If we found intermediate nodes, we need to find streams connected to them
    if (nodesToCheck.length > 0 || connectedStreams.length === 0) {
      try {
        var allNodes = Pipewire.nodes.values || [];

        // Find all stream nodes
        for (var j = 0; j < allNodes.length; j++) {
          var node = allNodes[j];
          if (!node || !node.isStream || !node.audio) {
            continue;
          }

          // Filter out quickshell
          const nodeName = node.name || "";
          const nodeMediaName = (node.properties && node.properties["media.name"]) || "";
          if (nodeName === "quickshell" || nodeMediaName === "quickshell") {
            continue;
          }

          // Filter out filter streams
          const nodeIsVirtual = (node.properties && node.properties["node.virtual"]) || "";
          if (nodeIsVirtual) {
            continue;
          }

          var streamId = node.id;
          if (connectedStreamIds[streamId]) {
            continue;
          }

          if (Object.keys(intermediateNodeIds).length > 0) {
            connectedStreamIds[streamId] = true;
            connectedStreams.push(node);
          } else if (connectedStreams.length === 0) {
            connectedStreamIds[streamId] = true;
            connectedStreams.push(node);
          }
        }
      } catch (e) {}
    }

    return connectedStreams;
  }

  // Bind all devices to ensure their properties are available
  PwObjectTracker {
    objects: [...root.sinks, ...root.sources]
  }

  // Per-stream volume overrides (app + media identity) so concurrent streams do not share one entry.
  property var appVolumeOverrides: ({})
  // Panel sticky: single stream per process base → store by base (survives track / node churn).
  // Multiple streams same base → store by full stream key; base-only locks migrate when n grows.
  property var panelAppVolumeByBase: ({})
  property var panelAppMutedByBase: ({})
  property var panelAppVolumeByStreamKey: ({})
  property var panelAppMutedByStreamKey: ({})
  property var _knownAppStreamIds: ({})
  property bool _isApplyingAppOverride: false

  PwObjectTracker {
    objects: root.streamNodes
  }

  // PipeWire → override sync (skipped while we are applying our own overrides).
  Item {
    width: 0
    height: 0
    visible: false

    Repeater {
      model: root.appStreams

      delegate: Item {
        required property var modelData

        Connections {
          target: modelData?.audio ?? null

          function onVolumeChanged() {
            if (root._isApplyingAppOverride || !modelData?.audio) {
              return;
            }
            if (root._skipPipewireVolumeSyncForNode(modelData)) {
              return;
            }
            var key = root.getAppKey(modelData);
            if (key) {
              root.setAppStreamVolume(key, modelData.audio.volume);
            }
          }

          function onMutedChanged() {
            if (root._isApplyingAppOverride || !modelData?.audio) {
              return;
            }
            if (root._skipPipewireMuteSyncForNode(modelData)) {
              return;
            }
            var key = root.getAppKey(modelData);
            if (key) {
              root.setAppStreamMuted(key, modelData.audio.muted);
            }
          }
        }
      }
    }
  }

  function getAppBaseKey(node): string {
    if (!node || !node.properties) {
      return "";
    }
    var props = node.properties;
    var base = "";
    var binary = props["application.process.binary"] || "";
    if (binary) {
      var parts = binary.split("/");
      base = parts[parts.length - 1].toLowerCase();
    }
    if (!base) {
      var appName = props["application.name"] || "";
      if (appName) {
        base = appName.toLowerCase();
      }
    }
    if (!base) {
      var appId = props["application.id"] || "";
      if (appId) {
        base = appId.toLowerCase();
      }
    }
    return base;
  }

  function _concurrentStreamsForSameBase(base: string): int {
    if (!base) {
      return 0;
    }
    var streams = root.appStreams;
    if (!streams) {
      return 0;
    }
    var n = 0;
    for (var i = 0; i < streams.length; i++) {
      var s = streams[i];
      if (s && getAppBaseKey(s) === base) {
        n++;
      }
    }
    return n;
  }

  function getAppKey(node): string {
    if (!node || !node.properties) {
      return "";
    }
    var props = node.properties;
    var base = root.getAppBaseKey(node);
    if (!base) {
      return "";
    }

    var mediaName = (props["media.name"] || "").trim().toLowerCase();
    var mediaRole = (props["media.role"] || "").trim().toLowerCase();
    var tagParts = [];
    if (mediaName) {
      tagParts.push(mediaName);
    }
    if (mediaRole) {
      tagParts.push(mediaRole);
    }
    if (tagParts.length > 0) {
      return base + "\u001f" + tagParts.join("\u001e");
    }
    return base + "\u001f" + String(node.id);
  }

  function setPanelAppStreamVolume(node, volume: real): void {
    _writePanelStickyVolume(node, volume);
    var key = getAppKey(node);
    if (key) {
      setAppStreamVolume(key, volume);
    }
  }

  function setPanelAppStreamMuted(node, muted: bool): void {
    _writePanelStickyMute(node, muted);
    var key = getAppKey(node);
    if (key) {
      setAppStreamMuted(key, muted);
    }
  }

  function setAppStreamVolume(appKey: string, volume: real): void {
    if (!appKey) {
      return;
    }
    var o = appVolumeOverrides;
    if (!o[appKey]) {
      o[appKey] = {};
    }

    o[appKey].volume = volume;
    appVolumeOverrides = o;
  }

  function setAppStreamMuted(appKey: string, muted: bool): void {
    if (!appKey) {
      return;
    }
    var o = appVolumeOverrides;
    if (!o[appKey]) {
      o[appKey] = {};
    }
    o[appKey].muted = muted;
    appVolumeOverrides = o;
  }

  function getAppVolumeOverride(appKey: string) {
    return appKey ? (appVolumeOverrides[appKey] || null) : null;
  }

  function _cloneStrMap(m) {
    var d = {};
    for (var k in m) {
      if (Object.prototype.hasOwnProperty.call(m, k)) {
        d[k] = m[k];
      }
    }
    return d;
  }

  function _cloneOverrideMap(ovSrc) {
    var out = {};
    for (var ok in ovSrc) {
      if (!Object.prototype.hasOwnProperty.call(ovSrc, ok)) {
        continue;
      }
      var inner = ovSrc[ok];
      out[ok] = inner ? {
                          "volume": inner.volume,
                          "muted": inner.muted
                        } : {};
    }
    return out;
  }

  function _ensureOverrideSlot(o, key) {
    if (!o[key]) {
      o[key] = {};
    }
    return o[key];
  }

  function _panelStickyVolume(key, base) {
    if (key && panelAppVolumeByStreamKey[key] !== undefined) {
      return panelAppVolumeByStreamKey[key];
    }
    if (base && panelAppVolumeByBase[base] !== undefined) {
      return panelAppVolumeByBase[base];
    }
    return undefined;
  }

  function _panelStickyMute(key, base) {
    if (key && panelAppMutedByStreamKey[key] !== undefined) {
      return panelAppMutedByStreamKey[key];
    }
    if (base && panelAppMutedByBase[base] !== undefined) {
      return panelAppMutedByBase[base];
    }
    return undefined;
  }

  function _writePanelStickyVolume(node, volume: real): void {
    var base = getAppBaseKey(node);
    var key = getAppKey(node);
    if (_concurrentStreamsForSameBase(base) > 1 && key) {
      var psk = panelAppVolumeByStreamKey;
      psk[key] = volume;
      panelAppVolumeByStreamKey = psk;
    } else if (base) {
      var pvb = panelAppVolumeByBase;
      pvb[base] = volume;
      panelAppVolumeByBase = pvb;
    }
  }

  function _writePanelStickyMute(node, muted: bool): void {
    var base = getAppBaseKey(node);
    var key = getAppKey(node);
    if (_concurrentStreamsForSameBase(base) > 1 && key) {
      var msk = panelAppMutedByStreamKey;
      msk[key] = muted;
      panelAppMutedByStreamKey = msk;
    } else if (base) {
      var pmb = panelAppMutedByBase;
      pmb[base] = muted;
      panelAppMutedByBase = pmb;
    }
  }

  function _skipPipewireVolumeSyncForNode(node): bool {
    var base = getAppBaseKey(node);
    var key = getAppKey(node);
    if (key && panelAppVolumeByStreamKey[key] !== undefined) {
      return true;
    }
    return !!(base && panelAppVolumeByBase[base] !== undefined && _concurrentStreamsForSameBase(base) <= 1);
  }

  function _skipPipewireMuteSyncForNode(node): bool {
    var base = getAppBaseKey(node);
    var key = getAppKey(node);
    if (key && panelAppMutedByStreamKey[key] !== undefined) {
      return true;
    }
    return !!(base && panelAppMutedByBase[base] !== undefined && _concurrentStreamsForSameBase(base) <= 1);
  }

  function _migrateBasePanelLocksToPerStreamIfNeeded(): void {
    var streams = root.appStreams;
    if (!streams || streams.length === 0) {
      return;
    }

    var bases = {};
    for (var i = 0; i < streams.length; i++) {
      var b = getAppBaseKey(streams[i]);
      if (b) {
        bases[b] = true;
      }
    }

    var psk = _cloneStrMap(panelAppVolumeByStreamKey);
    var msk = _cloneStrMap(panelAppMutedByStreamKey);
    var pvb = _cloneStrMap(panelAppVolumeByBase);
    var pmb = _cloneStrMap(panelAppMutedByBase);
    var oNew = _cloneOverrideMap(appVolumeOverrides);
    var changed = false;

    for (var base in bases) {
      if (!Object.prototype.hasOwnProperty.call(bases, base)) {
        continue;
      }
      if (_concurrentStreamsForSameBase(base) <= 1) {
        continue;
      }
      var volB = pvb[base];
      var muteB = pmb[base];
      if (volB === undefined && muteB === undefined) {
        continue;
      }

      for (var j = 0; j < streams.length; j++) {
        var s = streams[j];
        if (!s || getAppBaseKey(s) !== base) {
          continue;
        }
        var key = getAppKey(s);
        if (!key) {
          continue;
        }
        if (volB !== undefined && psk[key] === undefined) {
          psk[key] = volB;
          _ensureOverrideSlot(oNew, key).volume = volB;
          changed = true;
        }
        if (muteB !== undefined && msk[key] === undefined) {
          msk[key] = muteB;
          _ensureOverrideSlot(oNew, key).muted = muteB;
          changed = true;
        }
      }
      if (volB !== undefined) {
        delete pvb[base];
        changed = true;
      }
      if (muteB !== undefined) {
        delete pmb[base];
        changed = true;
      }
    }

    if (!changed) {
      return;
    }
    panelAppVolumeByStreamKey = psk;
    panelAppMutedByStreamKey = msk;
    panelAppVolumeByBase = pvb;
    panelAppMutedByBase = pmb;
    appVolumeOverrides = oNew;
  }

  function _seedNewStreamOverride(key, base, audio) {
    var seeded = appVolumeOverrides;
    if (!seeded[key]) {
      seeded[key] = {};
    }
    var pv = _panelStickyVolume(key, base);
    var pm = _panelStickyMute(key, base);
    seeded[key].volume = (pv !== undefined) ? pv : audio.volume;
    seeded[key].muted = (pm !== undefined) ? pm : audio.muted;
    appVolumeOverrides = seeded;
    return seeded[key];
  }

  function _applyAppOverrides(): void {
    var streams = root.appStreams;
    if (!streams) {
      return;
    }

    root._migrateBasePanelLocksToPerStreamIfNeeded();

    var prevKnown = root._knownAppStreamIds;
    var currentIds = {};
    _isApplyingAppOverride = true;
    for (var i = 0; i < streams.length; i++) {
      var s = streams[i];
      if (!s) {
        continue;
      }

      currentIds[s.id] = true;
      var key = getAppKey(s);
      var base = getAppBaseKey(s);
      var ov = key ? appVolumeOverrides[key] : null;

      if (key && s.audio && !prevKnown[s.id]) {
        ov = _seedNewStreamOverride(key, base, s.audio);
      }

      if (!s.audio) {
        continue;
      }

      var panelVol = _panelStickyVolume(key, base);
      var panelMute = _panelStickyMute(key, base);
      var targetVol = (panelVol !== undefined) ? panelVol : (ov && ov.volume !== undefined ? ov.volume : undefined);
      var targetMuted = (panelMute !== undefined) ? panelMute : (ov && ov.muted !== undefined ? ov.muted : undefined);
      if (targetVol !== undefined && Math.abs(s.audio.volume - targetVol) > root.epsilon) {
        s.audio.volume = targetVol;
      }
      if (targetMuted !== undefined && s.audio.muted !== targetMuted) {
        s.audio.muted = targetMuted;
      }
    }
    _knownAppStreamIds = currentIds;
    _isApplyingAppOverride = false;
  }

  Connections {
    target: root
    function onAppStreamsChanged() {
      _appOverrideTimer.restart();
    }
  }

  Timer {
    id: _appOverrideTimer
    interval: 50
    onTriggered: root._applyAppOverrides()
  }

  Timer {
    id: _appOverrideEnforcer
    interval: 1000
    running: Object.keys(root.appVolumeOverrides).length > 0 && root.appStreams.length > 0
    repeat: true
    onTriggered: root._applyAppOverrides()
  }

  Component.onCompleted: {
    wpctlAvailabilityProcess.running = true;
  }

  Connections {
    target: root
    function onSinkChanged() {
      if (root.wpctlAvailable) {
        root.refreshWpctlOutputState();
      }
    }

    function onSourceChanged() {
      if (root.wpctlAvailable) {
        root.refreshWpctlInputState();
      }
    }
  }

  Timer {
    id: wpctlPollTimer
    // Safety net only; regular updates are event-driven from sink audio signals.
    interval: 20000
    running: root.wpctlAvailable
    repeat: true
    onTriggered: {
      root.refreshWpctlOutputState();
      root.refreshWpctlInputState();
    }
  }

  Process {
    id: wpctlAvailabilityProcess
    command: ["sh", "-c", "command -v wpctl"]
    running: false

    onExited: function (code) {
      root.wpctlAvailable = (code === 0);
      root.wpctlStateValid = false;
      root.wpctlInputStateValid = false;
      if (root.wpctlAvailable) {
        root.refreshWpctlOutputState();
        root.refreshWpctlInputState();
      }
    }
  }

  Process {
    id: wpctlStateProcess
    running: false

    onExited: function (code) {
      if (code !== 0 || !root.applyWpctlOutputState(stdout.text)) {
        root.wpctlStateValid = false;
      }
    }

    stdout: StdioCollector {}
  }

  Process {
    id: wpctlSetVolumeProcess
    running: false

    onExited: function (code) {
      root.isSettingOutputVolume = false;
      if (code !== 0) {
        Logger.w("AudioService", "wpctl set-volume failed, falling back to PipeWire node audio");
        if (root.sink?.audio) {
          root.sink.audio.muted = false;
          root.sink.audio.volume = root.clampOutputVolume(root.wpctlOutputVolume);
        }
      }
      root.refreshWpctlOutputState();
    }
  }

  Process {
    id: wpctlSetMuteProcess
    running: false

    onExited: function (_code) {
      root.refreshWpctlOutputState();
    }
  }

  Process {
    id: wpctlInputStateProcess
    running: false

    onExited: function (code) {
      if (code !== 0 || !root.applyWpctlInputState(stdout.text)) {
        root.wpctlInputStateValid = false;
      }
    }

    stdout: StdioCollector {}
  }

  Process {
    id: wpctlSetInputVolumeProcess
    running: false

    onExited: function (code) {
      root.isSettingInputVolume = false;
      if (code !== 0) {
        Logger.w("AudioService", "wpctl set-volume failed for default source, falling back to PipeWire node audio");
        if (root.source?.audio) {
          root.source.audio.muted = false;
          root.source.audio.volume = Math.max(0, Math.min(root.maxVolume, root.wpctlInputVolume));
        }
      }
      root.refreshWpctlInputState();
    }
  }

  Process {
    id: wpctlSetInputMuteProcess
    running: false

    onExited: function (_code) {
      root.refreshWpctlInputState();
    }
  }

  // Watch output device changes for clamping
  Connections {
    target: sink?.audio ?? null

    function onVolumeChanged() {
      if (root.wpctlAvailable) {
        root.refreshWpctlOutputState();
      }

      // Ignore volume changes if we're the one setting it (to prevent feedback loop)
      if (root.isSettingOutputVolume) {
        return;
      }

      if (!root.sink?.audio) {
        return;
      }

      const vol = root.sink.audio.volume;
      if (vol === undefined || isNaN(vol)) {
        return;
      }

      if (root.sink !== root._lastFeedbackSink) {
        root._lastFeedbackSink = root.sink;
      } else {
        playVolumeFeedback(clampOutputVolume(vol));
      }

      // If volume exceeds max, clamp it (but only if we didn't just set it)
      if (vol > root.maxVolume) {
        root.isSettingOutputVolume = true;
        Qt.callLater(() => {
                       if (root.sink?.audio && root.sink.audio.volume > root.maxVolume) {
                         root.sink.audio.volume = root.maxVolume;
                       }
                       root.isSettingOutputVolume = false;
                     });
      }
    }

    function onMutedChanged() {
      if (root.wpctlAvailable) {
        root.refreshWpctlOutputState();
      }
    }
  }

  // Watch input device changes for clamping
  Connections {
    target: source?.audio ?? null

    function onVolumeChanged() {
      if (root.wpctlAvailable) {
        root.refreshWpctlInputState();
      }

      // Ignore volume changes if we're the one setting it (to prevent feedback loop)
      if (root.isSettingInputVolume) {
        return;
      }

      if (!root.source?.audio) {
        return;
      }

      const vol = root.source.audio.volume;
      if (vol === undefined || isNaN(vol)) {
        return;
      }

      // If volume exceeds max, clamp it (but only if we didn't just set it)
      if (vol > root.maxVolume) {
        root.isSettingInputVolume = true;
        Qt.callLater(() => {
                       if (root.source?.audio && root.source.audio.volume > root.maxVolume) {
                         root.source.audio.volume = root.maxVolume;
                       }
                       root.isSettingInputVolume = false;
                     });
      }
    }

    function onMutedChanged() {
      if (root.wpctlAvailable) {
        root.refreshWpctlInputState();
      }
    }
  }

  // Output Control
  function increaseVolume() {
    if (!Pipewire.ready || (!sink?.audio && !wpctlAvailable)) {
      return;
    }
    if (volume >= root.maxVolume) {
      volumeAtMaximum();
      return;
    }
    setVolume(Math.min(root.maxVolume, volume + stepVolume));
  }

  function decreaseVolume() {
    if (!Pipewire.ready || (!sink?.audio && !wpctlAvailable)) {
      return;
    }
    if (volume <= 0) {
      volumeAtMinimum();
      return;
    }
    setVolume(Math.max(0, volume - stepVolume));
  }

  function setVolume(newVolume: real) {
    if (!Pipewire.ready || (!sink?.audio && !wpctlAvailable)) {
      Logger.w("AudioService", "No sink available or not ready");
      return;
    }

    const clampedVolume = clampOutputVolume(newVolume);
    const delta = Math.abs(clampedVolume - volume);
    if (delta < root.epsilon) {
      return;
    }

    if (wpctlAvailable) {
      if (wpctlSetVolumeProcess.running) {
        return;
      }

      isSettingOutputVolume = true;
      wpctlOutputMuted = false;
      wpctlOutputVolume = clampedVolume;
      wpctlStateValid = true;

      const volumePct = Math.round(clampedVolume * 10000) / 100;
      wpctlSetVolumeProcess.command = ["sh", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 && wpctl set-volume @DEFAULT_AUDIO_SINK@ " + volumePct + "%"];
      wpctlSetVolumeProcess.running = true;

      playVolumeFeedback(clampedVolume);
      return;
    }

    if (!sink?.ready || !sink?.audio) {
      Logger.w("AudioService", "No sink available or not ready");
      return;
    }

    // Set flag to prevent feedback loop, then set the actual volume
    isSettingOutputVolume = true;
    sink.audio.muted = false;
    sink.audio.volume = clampedVolume;

    playVolumeFeedback(clampedVolume);

    // Clear flag after a short delay to allow external changes to be detected
    Qt.callLater(() => {
                   isSettingOutputVolume = false;
                 });
  }

  function setOutputMuted(muted: bool) {
    if (!Pipewire.ready || (!sink?.audio && !wpctlAvailable)) {
      Logger.w("AudioService", "No sink available or Pipewire not ready");
      return;
    }

    if (wpctlAvailable) {
      if (wpctlSetMuteProcess.running) {
        return;
      }

      wpctlOutputMuted = muted;
      wpctlStateValid = true;
      wpctlSetMuteProcess.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", muted ? "1" : "0"];
      wpctlSetMuteProcess.running = true;
      return;
    }

    sink.audio.muted = muted;
  }

  function getOutputIcon() {
    if (muted) {
      return "volume-mute";
    }

    const clampedVolume = Math.max(0, Math.min(volume, root.maxVolume));

    // Show volume-x icon when volume is effectively 0% (within rounding threshold)
    if (clampedVolume < root.epsilon) {
      return "volume-x";
    }
    if (clampedVolume <= 0.5) {
      return "volume-low";
    }
    return "volume-high";
  }

  // Input Control
  function increaseInputVolume() {
    if (!Pipewire.ready || (!source?.audio && !wpctlAvailable)) {
      return;
    }
    if (inputVolume >= root.maxVolume) {
      return;
    }
    setInputVolume(Math.min(root.maxVolume, inputVolume + stepVolume));
  }

  function decreaseInputVolume() {
    if (!Pipewire.ready || (!source?.audio && !wpctlAvailable)) {
      return;
    }
    setInputVolume(Math.max(0, inputVolume - stepVolume));
  }

  function setInputVolume(newVolume: real) {
    if (!Pipewire.ready) {
      return;
    }

    const clampedVolume = Math.max(0, Math.min(root.maxVolume, newVolume));
    var currentVol = 0;
    if (wpctlAvailable && wpctlInputStateValid) {
      currentVol = wpctlInputVolume;
    } else if (source?.audio && source.audio.volume !== undefined && !isNaN(source.audio.volume)) {
      currentVol = source.audio.volume;
    }
    const delta = Math.abs(clampedVolume - currentVol);
    if (delta < root.epsilon) {
      return;
    }

    if (wpctlAvailable) {
      if (wpctlSetInputVolumeProcess.running) {
        return;
      }

      isSettingInputVolume = true;
      wpctlInputMuted = false;
      wpctlInputVolume = clampedVolume;
      wpctlInputStateValid = true;

      const volumePct = Math.round(clampedVolume * 10000) / 100;
      wpctlSetInputVolumeProcess.command = ["sh", "-c", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0 && wpctl set-volume @DEFAULT_AUDIO_SOURCE@ " + volumePct + "%"];
      wpctlSetInputVolumeProcess.running = true;
      return;
    }

    if (!source?.ready || !source?.audio) {
      Logger.w("AudioService", "No source available or not ready");
      return;
    }

    isSettingInputVolume = true;
    source.audio.muted = false;
    source.audio.volume = clampedVolume;

    Qt.callLater(() => {
                   isSettingInputVolume = false;
                 });
  }

  function playVolumeFeedback(currentVolume: real) {
    if (!SoundService.multimediaAvailable) {
      return;
    }

    if (!Settings.data.audio.volumeFeedback) {
      return;
    }

    const now = Date.now();
    if (now - lastVolumeFeedbackTime < minVolumeFeedbackInterval) {
      return;
    }
    lastVolumeFeedbackTime = now;

    const feedbackVolume = currentVolume;
    const configuredSoundFile = Settings.data.audio.volumeFeedbackSoundFile;
    const soundFile = (configuredSoundFile && configuredSoundFile.trim() !== "") ? configuredSoundFile : "volume-change.wav";

    SoundService.playSound(soundFile, {
                             volume: feedbackVolume,
                             fallback: false,
                             repeat: false
                           });
  }

  function setInputMuted(muted: bool) {
    if (!Pipewire.ready) {
      Logger.w("AudioService", "Pipewire not ready");
      return;
    }

    if (wpctlAvailable) {
      if (wpctlSetInputMuteProcess.running) {
        return;
      }

      wpctlInputMuted = muted;
      wpctlInputStateValid = true;
      wpctlSetInputMuteProcess.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", muted ? "1" : "0"];
      wpctlSetInputMuteProcess.running = true;
      return;
    }

    if (!source?.audio) {
      Logger.w("AudioService", "No source available");
      return;
    }

    source.audio.muted = muted;
  }

  function getInputIcon() {
    if (inputMuted || inputVolume <= Number.EPSILON) {
      return "microphone-mute";
    }
    return "microphone";
  }

  // Device Selection
  function setAudioSink(newSink: PwNode): void {
    if (!Pipewire.ready) {
      Logger.w("AudioService", "Pipewire not ready");
      return;
    }
    Pipewire.preferredDefaultAudioSink = newSink;
  }

  function setAudioSource(newSource: PwNode): void {
    if (!Pipewire.ready) {
      Logger.w("AudioService", "Pipewire not ready");
      return;
    }
    Pipewire.preferredDefaultAudioSource = newSource;
  }
}
