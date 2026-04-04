import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: fadeMaskRoot

  property int orientation: Gradient.Vertical
  property real fadeExtent: 0.1

  property color startColor: "transparent"
  property color endColor: "transparent"
  property bool animateColors: false
  property int animationDuration: Style.animationFast

  property real heightAdjustment: 0
  property real widthAdjustment: 0

  property real topLeftRadius: 0
  property real topRightRadius: 0
  property real bottomLeftRadius: 0
  property real bottomRightRadius: 0

  readonly property Component effectComponent: Component {
    MultiEffect {
      maskEnabled: true
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
      maskSource: fadeMaskRoot
    }
  }

  function applyTo(targetItem) {
    targetItem.layer.effect = effectComponent;
  }

  visible: false
  layer.enabled: true
  layer.smooth: true

  Rectangle {
    anchors.centerIn: parent
    width: parent.width + fadeMaskRoot.widthAdjustment
    height: parent.height + fadeMaskRoot.heightAdjustment
    topLeftRadius: fadeMaskRoot.topLeftRadius
    topRightRadius: fadeMaskRoot.topRightRadius
    bottomLeftRadius: fadeMaskRoot.bottomLeftRadius
    bottomRightRadius: fadeMaskRoot.bottomRightRadius

    gradient: Gradient {
      orientation: fadeMaskRoot.orientation
      GradientStop {
        position: 0.0
        color: fadeMaskRoot.startColor
        Behavior on color {
          enabled: fadeMaskRoot.animateColors
          ColorAnimation {
            duration: fadeMaskRoot.animationDuration
            easing.type: Easing.InOutQuad
          }
        }
      }
      GradientStop {
        position: fadeMaskRoot.fadeExtent
        color: "white"
      }
      GradientStop {
        position: 1.0 - fadeMaskRoot.fadeExtent
        color: "white"
      }
      GradientStop {
        position: 1.0
        color: fadeMaskRoot.endColor
        Behavior on color {
          enabled: fadeMaskRoot.animateColors
          ColorAnimation {
            duration: fadeMaskRoot.animationDuration
            easing.type: Easing.InOutQuad
          }
        }
      }
    }
  }
}
