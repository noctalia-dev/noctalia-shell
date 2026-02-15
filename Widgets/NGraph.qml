import QtQuick
import QtQuick.Shapes
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

  // Vertical padding (percentage of range) to keep values from touching edges
  readonly property real curvePadding: 0.12

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

      if (!stillAnimating) {
        _prevTime = 0;
        stop();
      }
    }
  }

  // Convert a value to Y coordinate (with padding to keep values from touching edges)
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

  // Build SVG path with cubic bezier curves (Catmull-Rom → Bezier conversion)
  function buildSvg(vals, pred, minVal, maxVal, t, closeFill) {
    if (!vals || vals.length < 4 || width <= 0 || height <= 0)
      return "M 0 0";

    const n = vals.length;
    const step = width / (n - 3);
    if (!isFinite(step) || step <= 0)
      return "M 0 0";

    // Build raw data points
    let raw = [];
    raw.push({
               x: (-2 - t) * step,
               y: valueToY(vals[0], minVal, maxVal)
             });
    raw.push({
               x: (-1 - t) * step,
               y: valueToY(vals[1], minVal, maxVal)
             });
    for (let i = 2; i < n; i++) {
      raw.push({
                 x: (i - 2 - t) * step,
                 y: valueToY(vals[i], minVal, maxVal)
               });
    }
    raw.push({
               x: (n - 2 - t) * step,
               y: valueToY(pred, minVal, maxVal)
             });

    // Start at first point
    let svg = `M ${raw[0].x} ${raw[0].y}`;

    // Catmull-Rom to cubic bezier: cp1 = p1 + (p2-p0)/6, cp2 = p2 - (p3-p1)/6
    for (let i = 0; i < raw.length - 1; i++) {
      const p0 = raw[Math.max(i - 1, 0)];
      const p1 = raw[i];
      const p2 = raw[i + 1];
      const p3 = raw[Math.min(i + 2, raw.length - 1)];

      const cp1x = p1.x + (p2.x - p0.x) / 6;
      const cp1y = p1.y + (p2.y - p0.y) / 6;
      const cp2x = p2.x - (p3.x - p1.x) / 6;
      const cp2y = p2.y - (p3.y - p1.y) / 6;

      svg += ` C ${cp1x} ${cp1y} ${cp2x} ${cp2y} ${p2.x} ${p2.y}`;
    }

    if (closeFill) {
      const last = raw[raw.length - 1];
      svg += ` L ${last.x} ${height} L ${raw[0].x} ${height} Z`;
    }

    return svg;
  }

  // Reactive SVG paths — re-evaluated when any dependency changes
  readonly property string _strokeSvg1: buildSvg(values, _pred1, minValue, _effectiveMax1, _t1, false)
  readonly property string _fillSvg1: fill ? buildSvg(values, _pred1, minValue, _effectiveMax1, _t1, true) : "M 0 0"
  readonly property string _strokeSvg2: buildSvg(values2, _pred2, minValue2, _effectiveMax2, _t2, false)
  readonly property string _fillSvg2: fill ? buildSvg(values2, _pred2, minValue2, _effectiveMax2, _t2, true) : "M 0 0"

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    // Fill for primary line
    ShapePath {
      fillGradient: LinearGradient {
        y1: 0
        y2: root.height

        GradientStop {
          position: 0
          color: Qt.rgba(root.color.r, root.color.g, root.color.b, root.fillOpacity)
        }

        GradientStop {
          position: 1
          color: "transparent"
        }
      }
      strokeWidth: -1
      strokeColor: "transparent"

      PathSvg {
        path: root._fillSvg1
      }
    }

    // Stroke for primary line
    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      PathSvg {
        path: root._strokeSvg1
      }
    }

    // Fill for secondary line
    ShapePath {
      fillGradient: LinearGradient {
        y1: 0
        y2: root.height

        GradientStop {
          position: 0
          color: Qt.rgba(root.color2.r, root.color2.g, root.color2.b, root.fillOpacity)
        }

        GradientStop {
          position: 1
          color: "transparent"
        }
      }
      strokeWidth: -1
      strokeColor: "transparent"

      PathSvg {
        path: root._fillSvg2
      }
    }

    // Stroke for secondary line
    ShapePath {
      strokeColor: root.color2
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      PathSvg {
        path: root._strokeSvg2
      }
    }
  }
}
