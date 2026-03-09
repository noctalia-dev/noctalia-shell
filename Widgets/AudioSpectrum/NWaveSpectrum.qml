import QtQuick
import Quickshell
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

  readonly property int valuesCount: (values && Array.isArray(values)) ? values.length : 0
  readonly property bool hasData: valuesCount >= 2

  // Data texture: one pixel per value, R channel = amplitude
  Item {
    id: dataRow
    width: Math.max(root.valuesCount, 4)
    height: 1

    Repeater {
      model: dataRow.width

      Rectangle {
        required property int index
        x: index
        width: 1
        height: 1
        color: {
          if (index >= root.valuesCount)
            return Qt.rgba(0, 0, 0, 1);
          var v = root.values[index];
          if (v === undefined || v === null || !isFinite(v))
            v = 0;
          if (root.showMinimumSignal && v === 0)
            v = root.minimumSignalValue;
          return Qt.rgba(Math.max(0, Math.min(1, v)), 0, 0, 1);
        }
      }
    }
  }

  ShaderEffectSource {
    id: dataTex
    sourceItem: dataRow
    textureSize: Qt.size(dataRow.width, 1)
    live: true
    smooth: false
    hideSource: true
  }

  ShaderEffect {
    anchors.fill: parent
    visible: root.hasData && root.width > 0 && root.height > 0

    property variant dataSource: dataTex
    property color fillColor: root.fillColor
    property real count: root.valuesCount
    property real texWidth: dataRow.width
    property real vertical: root.vertical ? 1.0 : 0.0

    fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/wave_spectrum.frag.qsb")
    blending: true
  }
}
