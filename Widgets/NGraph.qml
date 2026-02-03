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

  // Auto-scale: when false, use minValue/maxValue directly (e.g., for 0-100% graphs)
  property bool autoScale: true
  property bool autoScale2: true

  // Padding for bezier overshoot (percentage of range)
  readonly property real curvePadding: 0.08

  readonly property bool hasData: values.length >= 2
  readonly property bool hasData2: values2.length >= 2

  // Animation state
  property real _t: 1.0
  property bool _ready: false
  property real _pred: 0
  property real _pred2: 0

  onValuesChanged: {
    if (values.length < 2)
      return;
    const last = values[values.length - 1];
    const prev = values.length > 1 ? values[values.length - 2] : last;
    _pred = Math.max(minValue, last + (last - prev));

    if (!_ready) {
      _ready = true;
      _t = 0;
      _animTimer.start();
      return;
    }
    // Maintain continuity: new_t = old_t - 1
    _t = _t - 1.0;
    _animTimer.start();
  }

  onValues2Changed: {
    if (values2.length < 2)
      return;
    const last = values2[values2.length - 1];
    const prev = values2.length > 1 ? values2[values2.length - 2] : last;
    _pred2 = Math.max(minValue2, last + (last - prev));
    // Let animation timer handle repaints - don't trigger here
  }

  Timer {
    id: _animTimer
    interval: 16
    repeat: true
    onTriggered: {
      root._t = Math.min(1.0, root._t + (16 / root.updateInterval));
      canvas.requestPaint();
      if (root._t >= 1.0)
        stop();
    }
  }

  // Effective max values that include current data and predictions (when autoScale is true)
  readonly property real _effectiveMax: {
    if (!autoScale || !hasData)
      return maxValue;
    let m = maxValue;
    for (let i = 0; i < values.length; i++) {
      if (values[i] > m)
        m = values[i];
    }
    if (_pred > m)
      m = _pred;
    return m;
  }

  readonly property real _effectiveMax2: {
    if (!autoScale2 || !hasData2)
      return maxValue2;
    let m = maxValue2;
    for (let i = 0; i < values2.length; i++) {
      if (values2[i] > m)
        m = values2[i];
    }
    if (_pred2 > m)
      m = _pred2;
    return m;
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
    renderStrategy: Canvas.Cooperative

    onPaint: {
      var ctx = getContext("2d");
      ctx.clearRect(0, 0, width, height);
      if (width <= 0 || height <= 0)
        return;

      // Use primary values length for consistent step size
      const baseLen = root.hasData ? root.values.length : (root.hasData2 ? root.values2.length : 0);
      if (baseLen < 2)
        return;
      const step = width / (baseLen - 1);

      if (root.hasData) {
        drawGraph(ctx, root.values, root._pred, root.minValue, root._effectiveMax, root.color, root._t, step);
      }
      if (root.hasData2) {
        drawGraph(ctx, root.values2, root._pred2, root.minValue2, root._effectiveMax2, root.color2, root._t, step);
      }
    }

    function drawGraph(ctx, vals, pred, minVal, maxVal, lineColor, t, step) {
      if (!vals || vals.length < 2)
        return;

      const n = vals.length;

      // Build points with interpolated X positions for smooth scrolling
      let pts = [];
      for (let i = 0; i < n; i++) {
        const x = (i + 1 - t) * step;
        const y = root.valueToY(vals[i], minVal, maxVal);
        pts.push({
                   x: x,
                   y: y
                 });
      }
      // Prediction point enters from right
      pts.push({
                 x: (n + 1 - t) * step,
                 y: root.valueToY(pred, minVal, maxVal)
               });

      if (pts.length < 2)
        return;

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
