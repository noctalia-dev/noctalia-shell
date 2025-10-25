// Modules/Bar/Widgets/CavaVisualizer.qml
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  // ---- Public props (configurable from settings) ----
  property int    bars: 48
  property int    asciiMax: 1000
  property real   barWidth: 3
  property real   barSpacing: 1
  property real   barRadius: 2
  property color  barColor: "#8bd5ff"
  property color  idleColor: "#334"
  property bool   center: false
  property bool   mono: true
  property int    framerate: 60
  property real   heightScale: 1.0
  property int    noiseReduction: 77
  property alias  running: cavaProc.running

  // Internal model of bar heights (0..1)
  property var values: Array(bars).fill(0)

  implicitHeight: 20
  implicitWidth: (bars * barWidth) + (Math.max(0, bars - 1) * barSpacing)

  // Write a tiny CAVA config into Quickshell's state dir
  FileView {
    id: cfg
    path: Quickshell.statePath("cava.cavarc")
  }
  function writeCavaConfig() {
    const cfgText = `
[general]
framerate = ${framerate}
bars = ${bars}

[input]
; method/source left to defaults (PipeWire/Pulse auto-detect)

[output]
method = raw
channels = ${mono ? "mono" : "stereo"}
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = ${asciiMax}
bar_delimiter = 59
frame_delimiter = 10

[smoothing]
noise_reduction = ${noiseReduction}
`.trim() + "\n";
    cfg.setText(cfgText);
    cfg.waitForJob();
  }

  // Launch and parse cava stream
  Process {
    id: cavaProc
    command: ["cava", "-p", cfg.path]
    running: root.visible

    stdout: SplitParser {
      id: frames
      onRead: (frame) => {
        const parts = frame.replace(/;$/,"").split(";");
        if (parts.length < 2) return;
        const limit = Math.max(1, root.asciiMax);
        const N = Math.min(root.bars, parts.length);
        for (let i = 0; i < N; i++) {
          const v = Math.max(0, Math.min(limit, parseInt(parts[i], 10))) / limit;
          root.values[i] = v;
        }
        barsView.requestPaint();
      }
    }

    onRunningChanged: if (!running && root.visible) running = true
  }

  Component.onCompleted: writeCavaConfig()
  onBarsChanged:        { values = Array(bars).fill(0); writeCavaConfig() }
  onAsciiMaxChanged:    writeCavaConfig()
  onMonoChanged:        writeCavaConfig()
  onFramerateChanged:   writeCavaConfig()
  onNoiseReductionChanged: writeCavaConfig()

  // Render bars
  Canvas {
    id: barsView
    anchors.fill: parent
    renderTarget: Canvas.FramebufferObject
    antialiasing: false

    onPaint: {
      const ctx = getContext("2d");
      const W = width, H = height;
      ctx.clearRect(0, 0, W, H);

      const bw = root.barWidth;
      const bs = root.barSpacing;
      const N  = root.values.length;
      const totalWidth = (N * bw) + ((N - 1) * bs);
      const x0 = root.center ? Math.floor((W - totalWidth) / 2) : 0;

      // baseline
      ctx.fillStyle = root.idleColor;
      if (totalWidth > 0) ctx.fillRect(x0, H - 1, totalWidth, 1);

      // bars
      ctx.fillStyle = root.barColor;
      for (let i = 0; i < N; i++) {
        const v = Math.max(0, Math.min(1, root.values[i])) * root.heightScale;
        const h = Math.max(0, Math.min(H, Math.floor(v * H)));
        if (h <= 0) continue;

        const x = x0 + i * (bw + bs);
        const y = H - h;

        if (root.barRadius > 0) {
          const r = Math.min(root.barRadius, bw / 2, h);
          ctx.beginPath();
          ctx.moveTo(x, y + r);
          ctx.arcTo(x, y, x + r, y, r);
          ctx.lineTo(x + bw - r, y);
          ctx.arcTo(x + bw, y, x + bw, y + r, r);
          ctx.lineTo(x + bw, y + h);
          ctx.lineTo(x, y + h);
          ctx.closePath();
          ctx.fill();
        } else {
          ctx.fillRect(x, y, bw, h);
        }
      }
    }

    Behavior on width  { NumberAnimation { duration: 120 } }
    Behavior on height { NumberAnimation { duration: 120 } }
  }

  Accessible.name: "CavaVisualizer"
}
