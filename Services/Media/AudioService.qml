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

  // Track unavailable devices
  property var unavailableSinkNames: []
  property var unavailableSourceNames: []

  readonly property list<PwNode> sinks: deviceNodes.sinks
  readonly property list<PwNode> sources: deviceNodes.sources

  readonly property real epsilon: 0.005

  // Output Volume - read directly from device
  readonly property real volume: {
    if (!sink?.audio)
    return 0;
    const vol = sink.audio.volume;
    if (vol === undefined || isNaN(vol))
    return 0;
    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    return Math.max(0, Math.min(maxVolume, vol));
  }
  readonly property bool muted: sink?.audio?.muted ?? true

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
  readonly property var deviceNodes: {
    // trigger binding on availability changes
    const unavailableSinks = root.unavailableSinkNames;
    const unavailableSources = root.unavailableSourceNames;

    return Pipewire.ready ? Pipewire.nodes.values.reduce((acc, node) => {
                                                           if (!node.isStream) {
                                                             if (node.isSink) {
                                                               if (!unavailableSinks.includes(node.name)) {
                                                                 acc.sinks.push(node);
                                                               }
                                                             } else if (node.audio) {
                                                               if (!unavailableSources.includes(node.name)) {
                                                                 acc.sources.push(node);
                                                               }
                                                             }
                                                           }
                                                           return acc;
                                                         }, {
                                                           "sources": [],
                                                           "sinks": []
                                                         }) : {
                              "sources": [],
                              "sinks": []
                            };
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

  // Bind all devices to ensure their properties are available
  PwObjectTracker {
    objects: [...root.sinks, ...root.sources]
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
    if (!Pipewire.ready || !sink?.audio) {
      return;
    }
    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    if (volume >= maxVolume) {
      return;
    }
    setVolume(Math.min(maxVolume, volume + stepVolume));
  }

  function decreaseVolume() {
    if (!Pipewire.ready || !sink?.audio) {
      return;
    }
    if (volume <= 0) {
      return;
    }
    setVolume(Math.max(0, volume - stepVolume));
  }

  function setVolume(newVolume: real) {
    if (!Pipewire.ready || !sink?.ready || !sink?.audio) {
      Logger.w("AudioService", "No sink available or not ready");
      return;
    }

    const maxVolume = Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
    const clampedVolume = Math.max(0, Math.min(maxVolume, newVolume));
    const delta = Math.abs(clampedVolume - sink.audio.volume);
    if (delta < root.epsilon) {
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
    if (!Pipewire.ready || !sink?.audio) {
      Logger.w("AudioService", "No sink available or Pipewire not ready");
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

  // Device availability checking
  Timer {
    id: checkTimer
    interval: 5000 // 5s might be too short?? I hate polling.
    running: Pipewire.ready
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      checkProcess.running = true;
    }
  }

  Process {
    id: checkProcess
    command: ["pw-dump"]
    stdout: StdioCollector {
      id: pwDumpOutput
    }
    onExited: code => {
      if (code !== 0) {
        Logger.e("AudioService", "pw-dump failed with code: " + code);
        return;
      }

      const data = pwDumpOutput.data;
      if (!data)
      return;

      try {
        const dump = JSON.parse(data);
        const devices = {};
        for (const obj of dump) {
          if (obj.type === "PipeWire:Interface:Device") {
            devices[obj.id] = obj;
          }
        }

        const unavailableSinks = [];
        const unavailableSources = [];

        for (const obj of dump) {
          if (obj.type === "PipeWire:Interface:Node" && obj.info && obj.info.props) {
            const props = obj.info.props;
            const mediaClass = props["media.class"];
            const name = props["node.name"];
            const deviceId = props["device.id"];
            const cardProfileDevice = props["card.profile.device"];

            if ((mediaClass === "Audio/Sink" || mediaClass === "Audio/Source") && deviceId !== undefined && cardProfileDevice !== undefined) {

              // Explicitly ignore HDMI devices from unavailability checks to prevent auto-switching/hiding
              if (name && name.toLowerCase().includes("hdmi"))
              continue;

              const device = devices[deviceId];
              if (device && device.info && device.info.params && device.info.params.EnumRoute) {
                const routes = device.info.params.EnumRoute;
                const route = routes.find(r => r.devices && r.devices.includes(cardProfileDevice));

                if (route && route.available === "no") {
                  // Secondary check for HDMI in route details if not caught by node name
                  if (route.name && route.name.toLowerCase().includes("hdmi"))
                  continue;
                  if (route.description && route.description.toLowerCase().includes("hdmi"))
                  continue;

                  if (mediaClass === "Audio/Sink") {
                    unavailableSinks.push(name);
                  } else {
                    unavailableSources.push(name);
                  }
                }
              }
            }
          }
        }

        if (JSON.stringify(root.unavailableSinkNames) !== JSON.stringify(unavailableSinks)) {
          root.unavailableSinkNames = unavailableSinks;
        }
        if (JSON.stringify(root.unavailableSourceNames) !== JSON.stringify(unavailableSources)) {
          root.unavailableSourceNames = unavailableSources;
        }
      } catch (err) {
        Logger.e("AudioService", "Failed to parse pw-dump JSON: " + err);
      }
    }
  }
}
