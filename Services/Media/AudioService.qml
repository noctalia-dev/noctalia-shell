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

  // Devices
  readonly property PwNode sink: Pipewire.ready ? Pipewire.defaultAudioSink : null
  readonly property PwNode source: validatedSource
  readonly property bool hasInput: !!source
  readonly property list<PwNode> sinks: deviceNodes.sinks
  readonly property list<PwNode> sources: deviceNodes.sources

  readonly property real epsilon: 0.005

  // Fallback state sourced from wpctl when PipeWire node values go stale.
  property bool wpctlAvailable: false
  property bool wpctlStateValid: false
  property real wpctlOutputVolume: 0
  property bool wpctlOutputMuted: true

  function clampOutputVolume(vol: real): real {
    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    if (vol === undefined || isNaN(vol)) {
      return 0;
    }
    return Math.max(0, Math.min(maxVolume, vol));
  }

  function refreshWpctlOutputState(): void {
    if (!wpctlAvailable || wpctlStateProcess.running) {
      return;
    }
    wpctlStateProcess.command = ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"];
    wpctlStateProcess.running = true;
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

  // Output volume (prefer wpctl state when available)
  readonly property real volume: {
    if (wpctlAvailable && wpctlStateValid) {
      return clampOutputVolume(wpctlOutputVolume);
    }

    if (!sink?.audio)
    return 0;

    return clampOutputVolume(sink.audio.volume);
  }
  readonly property bool muted: {
    if (wpctlAvailable && wpctlStateValid) {
      return wpctlOutputMuted;
    }
    return sink?.audio?.muted ?? true;
  }

  // Input Volume - read directly from device
  readonly property real inputVolume: {
    if (!source?.audio)
    return 0;
    const vol = source.audio.volume;
    if (vol === undefined || isNaN(vol))
    return 0;
    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    return Math.max(0, Math.min(maxVolume, vol));
  }
  readonly property bool inputMuted: source?.audio?.muted ?? true

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
  readonly property PwNode validatedSource: {
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
    node: root.sink
  }

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

      // If it's a stream node, add it directly
      if (sourceNode.isStream && sourceNode.audio) {
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
  }

  Timer {
    id: wpctlPollTimer
    interval: 1250
    running: root.wpctlAvailable
    repeat: true
    onTriggered: root.refreshWpctlOutputState()
  }

  Process {
    id: wpctlAvailabilityProcess
    command: ["sh", "-c", "command -v wpctl"]
    running: false

    onExited: function (code) {
      root.wpctlAvailable = (code === 0);
      root.wpctlStateValid = false;
      if (root.wpctlAvailable) {
        root.refreshWpctlOutputState();
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
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
    stderr: StdioCollector {}
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

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  Process {
    id: wpctlSetMuteProcess
    running: false

    onExited: function (_code) {
      root.refreshWpctlOutputState();
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // Watch output device changes for clamping
  Connections {
    target: sink?.audio ?? null

    function onVolumeChanged() {
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

      const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;

      // If volume exceeds max, clamp it (but only if we didn't just set it)
      if (vol > maxVolume) {
        root.isSettingOutputVolume = true;
        Qt.callLater(() => {
                       if (root.sink?.audio && root.sink.audio.volume > maxVolume) {
                         root.sink.audio.volume = maxVolume;
                       }
                       root.isSettingOutputVolume = false;
                     });
      }
    }
  }

  // Watch input device changes for clamping
  Connections {
    target: source?.audio ?? null

    function onVolumeChanged() {
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

      const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;

      // If volume exceeds max, clamp it (but only if we didn't just set it)
      if (vol > maxVolume) {
        root.isSettingInputVolume = true;
        Qt.callLater(() => {
                       if (root.source?.audio && root.source.audio.volume > maxVolume) {
                         root.source.audio.volume = maxVolume;
                       }
                       root.isSettingInputVolume = false;
                     });
      }
    }
  }

  // Output Control
  function increaseVolume() {
    if (!Pipewire.ready || (!sink?.audio && !wpctlAvailable)) {
      return;
    }
    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    if (volume >= maxVolume) {
      return;
    }
    setVolume(Math.min(maxVolume, volume + stepVolume));
  }

  function decreaseVolume() {
    if (!Pipewire.ready || (!sink?.audio && !wpctlAvailable)) {
      return;
    }
    if (volume <= 0) {
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
    if (muted)
      return "volume-mute";

    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    const clampedVolume = Math.max(0, Math.min(volume, maxVolume));

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
    if (!Pipewire.ready || !source?.audio) {
      return;
    }
    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    if (inputVolume >= maxVolume) {
      return;
    }
    setInputVolume(Math.min(maxVolume, inputVolume + stepVolume));
  }

  function decreaseInputVolume() {
    if (!Pipewire.ready || !source?.audio) {
      return;
    }
    setInputVolume(Math.max(0, inputVolume - stepVolume));
  }

  function setInputVolume(newVolume: real) {
    if (!Pipewire.ready || !source?.ready || !source?.audio) {
      Logger.w("AudioService", "No source available or not ready");
      return;
    }

    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    const clampedVolume = Math.max(0, Math.min(maxVolume, newVolume));
    const delta = Math.abs(clampedVolume - source.audio.volume);
    if (delta < root.epsilon) {
      return;
    }

    // Set flag to prevent feedback loop, then set the actual volume
    isSettingInputVolume = true;
    source.audio.muted = false;
    source.audio.volume = clampedVolume;

    // Clear flag after a short delay to allow external changes to be detected
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
    SoundService.playSound("volume-change.wav", {
                             volume: feedbackVolume,
                             fallback: false,
                             repeat: false
                           });
  }

  function setInputMuted(muted: bool) {
    if (!Pipewire.ready || !source?.audio) {
      Logger.w("AudioService", "No source available or Pipewire not ready");
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
