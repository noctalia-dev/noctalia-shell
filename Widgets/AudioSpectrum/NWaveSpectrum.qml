import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root
  property color fillColor: Color.mPrimary
  property color strokeColor: Color.mOnSurface
  property int strokeWidth: 0
  property var values: []
  property bool vertical: false

  // Minimum signal properties
  property bool showMinimumSignal: false
  property real minimumSignalValue: 0.05 // Default to 5% of height

  // Safe degenerate-path fallback: valid off-screen line that renders nothing visible.
  // Bare move-to paths like "M 0 0" can crash Qt's CurveRenderer triangulation.
  readonly property string _safeFallbackPath: "M -1 -1 L -1 0"

  // Reactive path that updates when values change
  readonly property string svgPath: {
    if (!values || !Array.isArray(values) || values.length === 0) {
      return _safeFallbackPath;
    }

    if (!isFinite(width) || !isFinite(height) || width <= 0 || height <= 0)
      return _safeFallbackPath;

    // Apply minimum signal if enabled
    const processedValues = showMinimumSignal ? values.map(v => v === 0 ? minimumSignalValue : v) : values;

    // Create the mirrored values
    const partToMirror = processedValues.slice(1).reverse();
    const mirroredValues = partToMirror.concat(processedValues);

    if (mirroredValues.length < 2) {
      return _safeFallbackPath;
    }

    const count = mirroredValues.length;

    for (let i = 0; i < count; i++) {
      if (!isFinite(mirroredValues[i]))
        return _safeFallbackPath;
    }

    if (vertical) {
      const stepY = height / (count - 1);
      const centerX = width / 2;
      const amplitude = width / 2;

      if (!isFinite(stepY) || !isFinite(centerX) || !isFinite(amplitude))
        return _safeFallbackPath;

      let xOffset = mirroredValues[0] * amplitude;
      if (!isFinite(xOffset))
        return _safeFallbackPath;
      let path = `M ${centerX - xOffset} 0`;

      for (let i = 1; i < count; i++) {
        const y = i * stepY;
        xOffset = mirroredValues[i] * amplitude;
        if (!isFinite(y) || !isFinite(xOffset))
          return _safeFallbackPath;
        path += ` L ${centerX - xOffset} ${y}`;
      }

      for (let i = count - 1; i >= 0; i--) {
        const y = i * stepY;
        xOffset = mirroredValues[i] * amplitude;
        if (!isFinite(y) || !isFinite(xOffset))
          return _safeFallbackPath;
        path += ` L ${centerX + xOffset} ${y}`;
      }

      return path + " Z";
    } else {
      const stepX = width / (count - 1);
      const centerY = height / 2;
      const amplitude = height / 2;

      if (!isFinite(stepX) || !isFinite(centerY) || !isFinite(amplitude))
        return _safeFallbackPath;

      let yOffset = mirroredValues[0] * amplitude;
      if (!isFinite(yOffset))
        return _safeFallbackPath;
      let path = `M 0 ${centerY - yOffset}`;

      for (let i = 1; i < count; i++) {
        const x = i * stepX;
        yOffset = mirroredValues[i] * amplitude;
        if (!isFinite(x) || !isFinite(yOffset))
          return _safeFallbackPath;
        path += ` L ${x} ${centerY - yOffset}`;
      }

      for (let i = count - 1; i >= 0; i--) {
        const x = i * stepX;
        yOffset = mirroredValues[i] * amplitude;
        if (!isFinite(x) || !isFinite(yOffset))
          return _safeFallbackPath;
        path += ` L ${x} ${centerY + yOffset}`;
      }

      return path + " Z";
    }
  }

  Shape {
    id: shape
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    containsMode: Shape.FillContains

    ShapePath {
      id: shapePath
      fillColor: root.fillColor
      strokeColor: root.strokeWidth > 0 ? root.strokeColor : "transparent"
      strokeWidth: root.strokeWidth

      PathSvg {
        path: root.svgPath
      }
    }
  }
}
