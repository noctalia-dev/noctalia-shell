import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root
  clip: true // Clip bezier overshoot

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

  // Padding for bezier overshoot (percentage of range)
  readonly property real curvePadding: 0.08

  readonly property bool hasData: values.length >= 2
  readonly property bool hasData2: values2.length >= 2

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

  // Generate SVG path for a given values array using monotone cubic interpolation
  function generateCurvePath(vals, minVal, maxVal) {
    if (!vals || vals.length < 2 || width <= 0 || height <= 0)
      return "";

    const n = vals.length;

    // Build array of points
    let points = [];
    for (let i = 0; i < n; i++) {
      points.push({
                    x: (i / (n - 1)) * width,
                    y: valueToY(vals[i], minVal, maxVal)
                  });
    }

    // For only 2 points, draw a line
    if (points.length === 2) {
      return `M ${points[0].x.toFixed(2)} ${points[0].y.toFixed(2)} L ${points[1].x.toFixed(2)} ${points[1].y.toFixed(2)}`;
    }

    // Calculate tangents using finite differences (monotone cubic)
    let tangents = [];
    for (let i = 0; i < points.length; i++) {
      if (i === 0) {
        tangents.push((points[1].y - points[0].y) / (points[1].x - points[0].x));
      } else if (i === points.length - 1) {
        tangents.push((points[i].y - points[i - 1].y) / (points[i].x - points[i - 1].x));
      } else {
        // Average of left and right slopes
        const left = (points[i].y - points[i - 1].y) / (points[i].x - points[i - 1].x);
        const right = (points[i + 1].y - points[i].y) / (points[i + 1].x - points[i].x);
        tangents.push((left + right) / 2);
      }
    }

    // Build the path
    let path = `M ${points[0].x.toFixed(2)} ${points[0].y.toFixed(2)}`;

    for (let i = 0; i < points.length - 1; i++) {
      const p0 = points[i];
      const p1 = points[i + 1];
      const dx = p1.x - p0.x;

      // Control points for cubic bezier
      const cp1x = p0.x + dx / 3;
      const cp1y = p0.y + tangents[i] * dx / 3;
      const cp2x = p1.x - dx / 3;
      const cp2y = p1.y - tangents[i + 1] * dx / 3;

      path += ` C ${cp1x.toFixed(2)},${cp1y.toFixed(2)} ${cp2x.toFixed(2)},${cp2y.toFixed(2)} ${p1.x.toFixed(2)},${p1.y.toFixed(2)}`;
    }

    return path;
  }

  // Generate fill path (curve + bottom edge)
  function generateFillPath(curvePath) {
    if (!curvePath || width <= 0 || height <= 0)
      return "";
    return curvePath + ` L ${width.toFixed(2)} ${height.toFixed(2)} L 0 ${height.toFixed(2)} Z`;
  }

  // Computed paths for primary line
  readonly property string curvePath: generateCurvePath(values, minValue, maxValue)
  readonly property string fillPath: generateFillPath(curvePath)

  // Computed paths for secondary line
  readonly property string curvePath2: generateCurvePath(values2, minValue2, maxValue2)
  readonly property string fillPath2: generateFillPath(curvePath2)

  Shape {
    anchors.fill: parent
    layer.enabled: true
    layer.samples: 4
    antialiasing: true
    visible: root.hasData || root.hasData2

    // Primary line fill
    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillGradient: LinearGradient {
        x1: 0
        y1: 0
        x2: 0
        y2: root.height
        GradientStop {
          position: 0.0
          color: Qt.rgba(root.color.r, root.color.g, root.color.b, root.fill ? root.fillOpacity : 0)
        }
        GradientStop {
          position: 1.0
          color: "transparent"
        }
      }
      PathSvg {
        path: root.fillPath
      }
    }

    // Secondary line fill
    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillGradient: LinearGradient {
        x1: 0
        y1: 0
        x2: 0
        y2: root.height
        GradientStop {
          position: 0.0
          color: Qt.rgba(root.color2.r, root.color2.g, root.color2.b, root.fill && root.hasData2 ? root.fillOpacity : 0)
        }
        GradientStop {
          position: 1.0
          color: "transparent"
        }
      }
      PathSvg {
        path: root.fillPath2
      }
    }

    // Primary line stroke
    ShapePath {
      strokeColor: root.hasData ? root.color : "transparent"
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathSvg {
        path: root.curvePath
      }
    }

    // Secondary line stroke
    ShapePath {
      strokeColor: root.hasData2 ? root.color2 : "transparent"
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathSvg {
        path: root.curvePath2
      }
    }
  }
}
