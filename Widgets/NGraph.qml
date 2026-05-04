import QtQuick
import Quickshell
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
  property real strokeWidth: 1
  property bool fill: true
  property real fillOpacity: 0.15
  property real antialiasing: 0.5

  // Smooth scrolling interval (how often data updates)
  property int updateInterval: 1000

  // Animate scale changes (for network graphs with dynamic max)
  property bool animateScale: false

  // Vertical padding (percentage of range) to keep values from touching edges
  readonly property real curvePadding: 0.12

  readonly property bool hasData: values.length >= 4
  readonly property bool hasData2: values2.length >= 4

  // Scale animation state
  property real _targetMax1: maxValue
  property real _targetMax2: maxValue2
  property real _animMax1: maxValue
  property real _animMax2: maxValue2

  onMaxValueChanged: {
    _targetMax1 = maxValue;
    if (animateScale && _ready1) {
      _scaleTimer.start();
    } else {
      _animMax1 = maxValue;
    }
  }

  onMaxValue2Changed: {
    _targetMax2 = maxValue2;
    if (animateScale && _ready2) {
      _scaleTimer.start();
    } else {
      _animMax2 = maxValue2;
    }
  }

  // Effective max values (animated or direct)
  readonly property real _effectiveMax1: animateScale ? _animMax1 : maxValue
  readonly property real _effectiveMax2: animateScale ? _animMax2 : maxValue2

  // Scroll state (driven by NumberAnimation)
  property real _t1: 1.0
  property bool _ready1: false
  property real _pred1: 0

  property real _t2: 1.0
  property bool _ready2: false
  property real _pred2: 0

  // Frame-accurate scroll animations tied to Qt's render loop
  NumberAnimation {
    id: _scrollAnim1
    target: root
    property: "_t1"
    from: 0
    to: 1
    duration: root.updateInterval
  }

  NumberAnimation {
    id: _scrollAnim2
    target: root
    property: "_t2"
    from: 0
    to: 1
    duration: root.updateInterval
  }

  onValuesChanged: {
    if (values.length < 4)
      return;

    const last = values[values.length - 1];
    const prev = values[values.length - 2];
    _pred1 = Math.max(minValue, last + (last - prev) * 0.5);

    if (!_ready1)
      _ready1 = true;
    _scrollAnim1.restart();
  }

  onValues2Changed: {
    if (values2.length < 4)
      return;

    const last = values2[values2.length - 1];
    const prev = values2[values2.length - 2];
    _pred2 = Math.max(minValue2, last + (last - prev) * 0.5);

    if (!_ready2)
      _ready2 = true;
    _scrollAnim2.restart();
  }

  // Scale animation timer (only needed for animateScale mode)
  Timer {
    id: _scaleTimer
    interval: 16
    repeat: true

    onTriggered: {
      const scaleLerp = 0.15;
      const threshold = 0.5;
      let stillAnimating = false;

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

      if (!stillAnimating)
        stop();
    }
  }

  // Normalize a value to [0, 1] with padding applied
  function _normalize(val, minVal, maxVal) {
    let range = maxVal - minVal;
    if (range <= 0)
      return 0.5;
    let padding = range * curvePadding;
    let paddedMin = minVal - padding;
    let paddedRange = (maxVal + padding) - paddedMin;
    return Math.max(0, Math.min(1, (val - paddedMin) / paddedRange));
  }

  // Data texture built from Rectangles instead of Canvas.
  // Each Rectangle is one data point, color-coded with normalized values.
  // R channel = primary, G channel = secondary.
  Item {
    id: _dataRow
    width: Math.max(root.values.length + 1, root.values2.length + 1, 4)
    height: 1

    Repeater {
      model: _dataRow.width

      Rectangle {
        required property int index
        x: index
        width: 1
        height: 1
        color: {
          let r = 0, g = 0;
          let n1 = root.values.length;
          let n2 = root.values2.length;
          let eMax1 = root._effectiveMax1;
          let eMax2 = root._effectiveMax2;

          if (index < n1)
            r = root._normalize(root.values[index], root.minValue, eMax1);
          else if (n1 > 0)
            r = root._normalize(root._pred1, root.minValue, eMax1);

          if (index < n2)
            g = root._normalize(root.values2[index], root.minValue2, eMax2);
          else if (n2 > 0)
            g = root._normalize(root._pred2, root.minValue2, eMax2);

          return Qt.rgba(r, g, 0, 1);
        }
      }
    }
  }

  ShaderEffectSource {
    id: _dataTex
    sourceItem: _dataRow
    textureSize: Qt.size(_dataRow.width, 1)
    live: true
    smooth: false
    hideSource: true
  }

  ShaderEffect {
    anchors.fill: parent
    visible: (root.hasData || root.hasData2) && width > 0 && height > 0

    property variant dataSource: _dataTex
    property color lineColor1: root.color
    property color lineColor2: root.color2
    property real count1: root.values.length
    property real count2: root.values2.length
    property real scroll1: root._t1
    property real scroll2: root._t2
    property real lineWidth: root.strokeWidth
    property real graphFillOpacity: root.fill ? root.fillOpacity : 0.0
    property real texWidth: _dataRow.width
    property real resY: height
    property real aaSize: root.antialiasing

    fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/graph.frag.qsb")
    blending: true
  }
}
