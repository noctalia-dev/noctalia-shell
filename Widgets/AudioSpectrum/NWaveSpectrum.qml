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

  // Reactive path that updates when values change
  readonly property string svgPath: {
    if (!values || !Array.isArray(values) || values.length === 0) {
      return "M 0 0"; // Valid no-op path to avoid Qt triangulator crash on empty path
    }

    // Apply minimum signal if enabled
    const processedValues = showMinimumSignal ? values.map(v => v === 0 ? minimumSignalValue : v) : values;

    // Create the mirrored values
    const partToMirror = processedValues.slice(1).reverse();
    const mirroredValues = partToMirror.concat(processedValues);

    if (mirroredValues.length < 2) {
      return "M 0 0"; // Valid no-op path to avoid Qt triangulator crash on empty path
    }

    const count = mirroredValues.length;

    if (vertical) {
      const stepY = height / (count - 1);
      const centerX = width / 2;
      const amplitude = width / 2;

      let xOffset = mirroredValues[0] * amplitude;
      let path = `M ${centerX - xOffset} 0`;

      for (let i = 1; i < count; i++) {
        const y = i * stepY;
        xOffset = mirroredValues[i] * amplitude;
        path += ` L ${centerX - xOffset} ${y}`;
      }

      for (let i = count - 1; i >= 0; i--) {
        const y = i * stepY;
        xOffset = mirroredValues[i] * amplitude;
        path += ` L ${centerX + xOffset} ${y}`;
      }

      return path + " Z";
    } else {
      const stepX = width / (count - 1);
      const centerY = height / 2;
      const amplitude = height / 2;

      let yOffset = mirroredValues[0] * amplitude;
      let path = `M 0 ${centerY - yOffset}`;

      for (let i = 1; i < count; i++) {
        const x = i * stepX;
        yOffset = mirroredValues[i] * amplitude;
        path += ` L ${x} ${centerY - yOffset}`;
      }

      for (let i = count - 1; i >= 0; i--) {
        const x = i * stepX;
        yOffset = mirroredValues[i] * amplitude;
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
