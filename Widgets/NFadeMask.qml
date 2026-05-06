import QtQuick
import QtQuick.Effects
import qs.Commons

/*
Component {
id: fadeMaskComponent
NFadeMask {
// Adjust fade properties
}

Component.onCompleted {
var mask = fadeMaskComponent.createObject(targetParent)
targetItem.layer.enabled = Qt.binding(() => condition)
mask.applyTo(targetItem)
}
*/

Item {
  id: fadeMaskRoot

  // Gradient.Vertical or Gradient.Horizontal
  property int orientation: Gradient.Vertical

  // Fraction of height/width of component that fades on each side
  // Value: 0.0 - 0.5
  property real fadeExtent: 0.1

  // Outer stop colors - "transparent" = fade out, "white" = show content through
  // Bind externally for scroll-position-aware fading
  property color startColor: "transparent"
  property color endColor: "transparent"

  // Enable Behaviour on outer stops for animated "spawning" of the fades
  property bool animateColors: false
  property int animationDuration: Style.animationFast

  // Size adjustments for the inner gradient rectangle relative to the target
  // e.g. heightAdjustment: -2 * Style.capsuleBorderWidth to avoid sampling over borders
  property real heightAdjustment: 0
  property real widthAdjustment: 0

  // Corner radii for the gradient rectangle
  property real topLeftRadius: 0
  property real topRightRadius: 0
  property real bottomLeftRadius: 0
  property real bottomRightRadius: 0

  // Assign to targetItem.layer.effect declaratively, or use applyTo() dynamically
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
