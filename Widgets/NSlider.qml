import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.Commons
import qs.Services

Slider {
  id: root

  property var cutoutColor: Color.mSurface
  property bool snapAlways: true
  property real heightRatio: 0.7
  property string tooltipText
  property string tooltipDirection: "auto"
  property bool hovering: false

  readonly property real knobDiameter: Math.round((Style.baseWidgetSize * heightRatio * Style.uiScaleRatio) / 2) * 2
  readonly property real trackHeight: Math.round((knobDiameter * 0.4 * Style.uiScaleRatio) / 2) * 2
  readonly property real cutoutExtra: Math.round((Style.baseWidgetSize * 0.1 * Style.uiScaleRatio) / 2) * 2

  padding: cutoutExtra / 2

  snapMode: snapAlways ? Slider.SnapAlways : Slider.SnapOnRelease
  implicitHeight: Math.max(trackHeight, knobDiameter)

  background: Rectangle {
    x: root.leftPadding
    y: root.topPadding + root.availableHeight / 2 - height / 2
    implicitWidth: Style.sliderWidth
    implicitHeight: trackHeight
    width: root.availableWidth
    height: implicitHeight
    radius: height / 2
    color: Qt.alpha(Color.mSurface, 0.5)
    border.color: Qt.alpha(Color.mOutline, 0.5)
    border.width: Style.borderS

    // A container composite shape that puts a semicircle on the end
    Item {
      id: activeTrackContainer
      width: root.visualPosition * parent.width
      height: parent.height

      // The rounded end cap made from a rounded rectangle
      Rectangle {
        width: parent.height
        height: parent.height
        radius: width / 2
        color: Qt.darker(Color.mPrimary, 1.2) //starting color of gradient
      }

      // The main rectangle
      Rectangle {
        x: parent.height / 2
        width: parent.width - x // Fills the rest of the container
        height: parent.height
        radius: 0
        // Animated gradient fill
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop {
            position: 0.0
            color: Qt.darker(Color.mPrimary, 1.2)
            Behavior on color {
              ColorAnimation {
                duration: 300
              }
            }
          }
          GradientStop {
            position: 0.5
            color: Color.mPrimary
            SequentialAnimation on position {
              loops: Animation.Infinite
              NumberAnimation {
                from: 0.3
                to: 0.7
                duration: 2000
                easing.type: Easing.InOutSine
              }
              NumberAnimation {
                from: 0.7
                to: 0.3
                duration: 2000
                easing.type: Easing.InOutSine
              }
            }
          }
          GradientStop {
            position: 1.0
            color: Qt.lighter(Color.mPrimary, 1.2)
          }
        }
      }
    }

    // Circular cutout
    Rectangle {
      id: knobCutout
      implicitWidth: knobDiameter + cutoutExtra
      implicitHeight: knobDiameter + cutoutExtra
      radius: width / 2
      color: root.cutoutColor !== undefined ? root.cutoutColor : Color.mSurface
      x: root.leftPadding + root.visualPosition * (root.availableWidth - root.knobDiameter) - cutoutExtra
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  handle: Item {
    implicitWidth: knobDiameter
    implicitHeight: knobDiameter
    x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
    anchors.verticalCenter: parent.verticalCenter

    Rectangle {
      id: knob
      implicitWidth: knobDiameter
      implicitHeight: knobDiameter
      radius: width / 2
      color: root.pressed ? Color.mHover : Color.mSurface
      border.color: Color.mPrimary
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
      // Pass through mouse events to the slider
      propagateComposedEvents: true
      preventStealing: false

      onEntered: {
        root.hovering = true
        if (root.tooltipText) {
          TooltipService.show(Screen, knob, root.tooltipText, root.tooltipDirection)
        }
      }

      onExited: {
        root.hovering = false
        if (root.tooltipText) {
          TooltipService.hide()
        }
      }

      onPressed: function (mouse) {
        if (root.tooltipText) {
          TooltipService.hide()
        }
        // Pass the event through to the slider
        mouse.accepted = false
      }

      onReleased: function (mouse) {
        // Pass the event through to the slider
        mouse.accepted = false
      }

      onPositionChanged: function (mouse) {
        // Pass the event through to the slider
        mouse.accepted = false
      }
    }
  }
}
