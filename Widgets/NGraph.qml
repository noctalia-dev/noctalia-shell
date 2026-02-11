import QtQuick
import qs.Commons

Item {
  id: root
  clip: true

  // Primary line
  property var values: []
  property color color: Color.mPrimary

  // Optional secondary line
  property var values2: []
  property color color2: Color.mError

  // Range settings for primary line
  property real minValue: 0
  property real maxValue: 100

  // Range settings for secondary line (defaults to primary range)
  property real minValue2: minValue
  property real maxValue2: maxValue

  // Style settings
  property real strokeWidth: 2 * Style.uiScaleRatio
  property bool fill: true
  property real fillOpacity: 0.15

  // Smooth scrolling interval (how often data updates)
  property int updateInterval: 1000

  // Animate scale changes (for network graphs with dynamic max)
  property bool animateScale: false

  // Padding for bezier overshoot (percentage of range)
  readonly property real curvePadding: 0.12

  // Allow curve to extend to the edges (no horizontal padding)
  property bool edgeToEdge: false

  // Edge padding to hide bezier curve overshoot (in pixels)
  readonly property real edgePadding: edgeToEdge ? 0 : Math.max(8, width * 0.02)

  readonly property bool hasData: values.length >= 4
  readonly property bool hasData2: values2.length >= 4

  // Target max values (what we're animating toward)
  property real _targetMax1: maxValue
  property real _targetMax2: maxValue2

  // Current animated max values (interpolated in timer when animateScale is true)
  property real _animMax1: maxValue
  property real _animMax2: maxValue2

  onMaxValueChanged: {
    _targetMax1 = maxValue;
    if (animateScale && _ready1) {
      _animTimer.start();
    } else {
      _animMax1 = maxValue;
    }
  }

  onMaxValue2Changed: {
    _targetMax2 = maxValue2;
    if (animateScale && _ready2) {
      _animTimer.start();
    } else {
      _animMax2 = maxValue2;
    }
  }

  // Effective max values (animated or direct)
  readonly property real _effectiveMax1: animateScale ? _animMax1 : maxValue
  readonly property real _effectiveMax2: animateScale ? _animMax2 : maxValue2

  // Animation state for primary line
  property real _t1: 1.0
  property bool _ready1: false
  property real _pred1: 0

  // Animation state for secondary line
  property real _t2: 1.0
  property bool _ready2: false
  property real _pred2: 0

  onValuesChanged: {
    if (values.length < 4)
      return;

    const last = values[values.length - 1];
    const prev = values[values.length - 2];
    _pred1 = Math.max(minValue, last + (last - prev));

    if (!_ready1) {
      _ready1 = true;
      _t1 = 0;
    } else {
      _t1 = Math.max(0, _t1 - 1.0);
    }
    _animTimer.start();
  }

  onValues2Changed: {
    if (values2.length < 4)
      return;

    const last = values2[values2.length - 1];
    const prev = values2[values2.length - 2];
    _pred2 = Math.max(minValue2, last + (last - prev));

    if (!_ready2) {
      _ready2 = true;
      _t2 = 0;
    } else {
      _t2 = Math.max(0, _t2 - 1.0);
    }
    _animTimer.start();
  }

  Timer {
    id: _animTimer
    interval: 16
    repeat: true
    property real _prevTime: 0

    onTriggered: {
      const now = Date.now();
      const elapsed = _prevTime > 0 ? (now - _prevTime) : 16;
      _prevTime = now;
      const dt = elapsed / root.updateInterval;
      let stillAnimating = false;

      // Scroll animation
      if (root._t1 < 1.0) {
        root._t1 = Math.min(1.0, root._t1 + dt);
        stillAnimating = true;
      }
      if (root._t2 < 1.0) {
        root._t2 = Math.min(1.0, root._t2 + dt);
        stillAnimating = true;
      }

      // Scale animation (lerp toward target) - synchronized with scroll
      if (root.animateScale) {
        const scaleLerp = 0.15; // Smooth lerp factor per frame
        const threshold = 0.5; // Snap when close enough

        if (Math.abs(root._animMax1 - root._targetMax1) > threshold) {
          root._animMax1 += (root._targetMax1 - root._animMax1) * scaleLerp;
          stillAnimating = true;
        } else if (root._animMax1 !== root._targetMax1) {
          root._animMax1 = root._targetMax1;
        }

        if (Math.abs(root._animMax2 - root._targetMax2) > threshold) {
          root._animMax2 += (root._targetMax2 - root._animMax2) * scaleLerp;
          stillAnimating = true;
        } else if (root._animMax2 !== root._targetMax2) {
          root._animMax2 = root._targetMax2;
        }
      }

      canvas.requestPaint();

      if (!stillAnimating) {
        _prevTime = 0;
        stop();
      }
    }
  }

  // Convert a value to Y coordinate (with padding for bezier curves)
  function valueToY(val, minVal, maxVal) {
    let range = maxVal - minVal;
    if (range <= 0)
      return height / 2;
    let padding = range * curvePadding;
    let paddedMin = minVal - padding;
    let paddedMax = maxVal + padding;
    let paddedRange = paddedMax - paddedMin;
    let normalized = (val - paddedMin) / paddedRange;
    return height - normalized * height;
  }

  Canvas {
    id: canvas
    anchors.fill: parent

    onPaint: {
      var ctx = getContext("2d");
      ctx.clearRect(0, 0, width, height);
      if (width <= 0 || height <= 0)
        return;

      // Apply edge clipping to hide bezier overshoot (symmetric horizontal)
      const pad = root.edgePadding;
      ctx.save();
      ctx.beginPath();
      ctx.rect(pad, 0, width - pad * 2, height);
      ctx.clip();

      // Draw primary line
      if (root.hasData) {
        const n = root.values.length;
        // Step based on visible points (n-2 since vals[0] and vals[1] are off-screen buffers)
        const step = width / (n - 3);
        drawGraph(ctx, root.values, root._pred1, root.minValue, root._effectiveMax1, root.color, root._t1, step);
      }

      // Draw secondary line (independent animation)
      if (root.hasData2) {
        const n2 = root.values2.length;
        const step2 = width / (n2 - 3);
        drawGraph(ctx, root.values2, root._pred2, root.minValue2, root._effectiveMax2, root.color2, root._t2, step2);
      }

      ctx.restore();
    }

    function drawGraph(ctx, vals, pred, minVal, maxVal, lineColor, t, step) {
      if (!vals || vals.length < 4)
        return;

      // Safety check for invalid step
      if (!isFinite(step) || step <= 0)
        return;

      const n = vals.length;

      // Build points with interpolated X positions for smooth scrolling
      // vals[0] and vals[1] are off-screen buffers for bezier continuity
      // Visible data starts from vals[2]
      let pts = [];

      // Buffer points (always off-screen, provide bezier continuity)
      pts.push({
                 x: (-2 - t) * step,
                 y: root.valueToY(vals[0], minVal, maxVal)
               });
      pts.push({
                 x: (-1 - t) * step,
                 y: root.valueToY(vals[1], minVal, maxVal)
               });

      // Visible data points start from vals[2]
      for (let i = 2; i < n; i++) {
        const x = (i - 2 - t) * step;
        const y = root.valueToY(vals[i], minVal, maxVal);
        pts.push({
                   x: x,
                   y: y
                 });
      }

      // Prediction point
      pts.push({
                 x: (n - 2 - t) * step,
                 y: root.valueToY(pred, minVal, maxVal)
               });

      // Calculate tangents for smooth bezier curves
      let tan = [];
      for (let i = 0; i < pts.length; i++) {
        let tg = 0;
        if (i === 0 && pts[1].x !== pts[0].x) {
          tg = (pts[1].y - pts[0].y) / (pts[1].x - pts[0].x);
        } else if (i === pts.length - 1 && pts[i].x !== pts[i - 1].x) {
          tg = (pts[i].y - pts[i - 1].y) / (pts[i].x - pts[i - 1].x);
        } else if (i > 0 && i < pts.length - 1) {
          const dxL = pts[i].x - pts[i - 1].x;
          const dxR = pts[i + 1].x - pts[i].x;
          const l = dxL !== 0 ? (pts[i].y - pts[i - 1].y) / dxL : 0;
          const r = dxR !== 0 ? (pts[i + 1].y - pts[i].y) / dxR : 0;
          tg = (l + r) / 2;
        }
        tan.push(tg);
      }

      // Draw fill gradient
      if (root.fill) {
        let grad = ctx.createLinearGradient(0, 0, 0, height);
        grad.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, root.fillOpacity));
        grad.addColorStop(1, "transparent");

        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (let i = 0; i < pts.length - 1; i++) {
          const dx = pts[i + 1].x - pts[i].x;
          if (Math.abs(dx) < 0.1) {
            ctx.lineTo(pts[i + 1].x, pts[i + 1].y);
            continue;
          }
          const c1x = pts[i].x + dx / 3, c1y = pts[i].y + tan[i] * dx / 3;
          const c2x = pts[i + 1].x - dx / 3, c2y = pts[i + 1].y - tan[i + 1] * dx / 3;
          ctx.bezierCurveTo(c1x, c1y, c2x, c2y, pts[i + 1].x, pts[i + 1].y);
        }
        ctx.lineTo(pts[pts.length - 1].x, height);
        ctx.lineTo(pts[0].x, height);
        ctx.closePath();
        ctx.fillStyle = grad;
        ctx.fill();
      }

      // Draw stroke
      ctx.beginPath();
      ctx.moveTo(pts[0].x, pts[0].y);
      for (let i = 0; i < pts.length - 1; i++) {
        const dx = pts[i + 1].x - pts[i].x;
        if (Math.abs(dx) < 0.1) {
          ctx.lineTo(pts[i + 1].x, pts[i + 1].y);
          continue;
        }
        const c1x = pts[i].x + dx / 3, c1y = pts[i].y + tan[i] * dx / 3;
        const c2x = pts[i + 1].x - dx / 3, c2y = pts[i + 1].y - tan[i + 1] * dx / 3;
        ctx.bezierCurveTo(c1x, c1y, c2x, c2y, pts[i + 1].x, pts[i + 1].y);
      }
      ctx.strokeStyle = lineColor;
      ctx.lineWidth = root.strokeWidth;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.stroke();
    }
  }
}
