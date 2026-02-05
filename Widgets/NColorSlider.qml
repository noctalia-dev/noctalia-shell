import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import qs.Commons
import qs.Services.UI

Slider {
  id: root

  property color fillColor: "transparent"
  property var cutoutColor: Color.mSurface
  property bool snapAlways: true
  property real widthRatio: 0.7
  property string tooltipText
  property string tooltipDirection: "auto"
  property bool hovering: false
  property color topColor: "white"
  property color bottomColor: "black"
  property bool rainbowMode: false

  readonly property real knobDiameter: Math.round((Style.baseWidgetSize * widthRatio * Style.uiScaleRatio) / 2) * 2
  readonly property real trackWidth: Math.round((knobDiameter * 0.4 * Style.uiScaleRatio) / 2) * 2
  readonly property real trackRadius: Math.min(Style.iRadiusL, trackWidth / 2)
  readonly property real cutoutExtra: Math.round((Style.baseWidgetSize * 0.1 * Style.uiScaleRatio) / 2) * 2

  orientation: Qt.Vertical

  padding: cutoutExtra / 2

  snapMode: snapAlways ? Slider.SnapAlways : Slider.SnapOnRelease
  implicitWidth: Math.max(trackWidth, knobDiameter)

  background: Item {
    id: bgContainer
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: root.trackWidth
    height: root.availableHeight

    LinearGradient {
      id: standardLinearGradient
      x1: 0
      y1: 0
      x2: 0
      y2: root.availableHeight
      GradientStop {
        position: 0.0
        color: root.topColor
      }
      GradientStop {
        position: 1.0
        color: root.bottomColor
      }
    }

    LinearGradient {
      id: rainbowLinearGradient
      x1: 0
      y1: 0
      x2: 0
      y2: root.availableHeight
      GradientStop {
        position: 0.000
        color: "#FF0000"
      }
      GradientStop {
        position: 0.167
        color: "#FF00FF"
      }
      GradientStop {
        position: 0.333
        color: "#0000FF"
      }
      GradientStop {
        position: 0.500
        color: "#00FFFF"
      }
      GradientStop {
        position: 0.667
        color: "#00FF00"
      }
      GradientStop {
        position: 0.833
        color: "#FFFF00"
      }
      GradientStop {
        position: 1.000
        color: "#FF0000"
      }
    }

    Shape {
      anchors.centerIn: parent
      width: root.trackWidth
      height: bgContainer.height
      layer.enabled: true
      layer.samples: 4

      ShapePath {
        id: trackPath
        strokeColor: Qt.alpha(Color.mOutline, 0.5)
        strokeWidth: Style.borderS
        fillGradient: root.rainbowMode ? rainbowLinearGradient : standardLinearGradient

        readonly property real w: root.trackWidth
        readonly property real h: root.availableHeight
        readonly property real r: root.trackRadius

        startX: r
        startY: 0

        PathLine {
          x: trackPath.w - trackPath.r
          y: 0
        }
        PathArc {
          x: trackPath.w
          y: trackPath.r
          radiusX: trackPath.r
          radiusY: trackPath.r
        }
        PathLine {
          x: trackPath.w
          y: trackPath.h - trackPath.r
        }
        PathArc {
          x: trackPath.w - trackPath.r
          y: trackPath.h
          radiusX: trackPath.r
          radiusY: trackPath.r
        }
        PathLine {
          x: trackPath.r
          y: trackPath.h
        }
        PathArc {
          x: 0
          y: trackPath.h - trackPath.r
          radiusX: trackPath.r
          radiusY: trackPath.r
        }
        PathLine {
          x: 0
          y: trackPath.r
        }
        PathArc {
          x: trackPath.r
          y: 0
          radiusX: trackPath.r
          radiusY: trackPath.r
        }
      }
    }

    // Circular cutout
    Rectangle {
      id: knobCutout
      implicitWidth: root.knobDiameter + root.cutoutExtra
      implicitHeight: root.knobDiameter + root.cutoutExtra
      radius: Math.min(Style.iRadiusL, width / 2)
      color: root.cutoutColor !== undefined ? root.cutoutColor : Color.mSurface
      y: root.visualPosition * (root.availableHeight - root.knobDiameter) - root.cutoutExtra / 2
      anchors.horizontalCenter: parent.horizontalCenter
    }
  }

  handle: Item {
    implicitWidth: root.knobDiameter
    implicitHeight: root.knobDiameter
    y: root.topPadding + root.visualPosition * (root.availableHeight - height)
    anchors.horizontalCenter: parent.horizontalCenter

    Rectangle {
      id: knob
      implicitWidth: root.knobDiameter
      implicitHeight: root.knobDiameter
      radius: Math.min(Style.iRadiusL, width / 2)
      color: {
        if (root.rainbowMode) {
          // Hue Logic: Map position (0.0 to 1.0) directly to Hue
          return Qt.hsva(1 - root.visualPosition, 1, 1, 1);
        } else {
          // Linear Interpolation for Standard Gradients
          // visualPosition 0.0 = Top, 1.0 = Bottom
          var t = root.visualPosition;
          var r = root.topColor.r * (1 - t) + root.bottomColor.r * t;
          var g = root.topColor.g * (1 - t) + root.bottomColor.g * t;
          var b = root.topColor.b * (1 - t) + root.bottomColor.b * t;
          return Qt.rgba(r, g, b, 1);
        }
      }

      border.color: root.pressed ? Color.mHover : Color.mPrimary
      border.width: Style.borderL
      anchors.centerIn: parent

      Behavior on color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }
    }

    MouseArea {
      enabled: true
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true
      acceptedButtons: Qt.NoButton // Don't accept any mouse buttons - only hover
      propagateComposedEvents: true

      onEntered: {
        root.hovering = true;
        if (root.tooltipText) {
          TooltipService.show(knob, root.tooltipText, root.tooltipDirection);
        }
      }

      onExited: {
        root.hovering = false;
        if (root.tooltipText) {
          TooltipService.hide();
        }
      }
    }

    // Hide tooltip when slider is pressed (anywhere on the slider)
    Connections {
      target: root
      function onPressedChanged() {
        if (root.pressed && root.tooltipText) {
          TooltipService.hide();
        }
      }
    }
  }
}
