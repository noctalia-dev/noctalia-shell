import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.Commons

/**
* ScreenCorners - Shape component for rendering screen corners
*
* Renders concave corners at the screen edges to create a rounded screen effect.
* Self-contained Shape component (no shadows).
*/
Item {
  id: root

  property string screenName: ""
  property real cornerRadius: Style.screenRadius
  property real cornerSize: Style.screenRadius
  readonly property bool feedbackEnabled: Settings.data.general.showScreenCorners && Settings.data.general.showScreenCornersFeedback
  property real feedbackTopLeftOpacity: 0
  property real feedbackTopRightOpacity: 0
  property real feedbackBottomLeftOpacity: 0
  property real feedbackBottomRightOpacity: 0

  function feedbackColor(opacity) {
    return Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, opacity);
  }

  anchors.fill: parent

  // Wrapper with layer caching to reduce GPU tessellation overhead
  Item {
    anchors.fill: parent

    // Cache the Shape to a texture to prevent continuous re-tessellation
    layer.enabled: true

    Shape {
      id: cornersShape

      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      enabled: false // Disable mouse input
      visible: cornersPath.cornerRadius > 0 && width > 0 && height > 0 && (Settings.data.general.showScreenCorners || root.feedbackEnabled)

      ShapePath {
        id: cornersPath

        // Corner configuration
        readonly property color cornerColor: Settings.data.general.forceBlackScreenCorners ? "black" : Color.mSurface
        readonly property real cornerRadius: root.cornerRadius
        readonly property real cornerSize: root.cornerSize

        // Determine margins based on bar position
        readonly property real topMargin: 0
        readonly property real bottomMargin: 0
        readonly property real leftMargin: 0
        readonly property real rightMargin: 0

        // Screen dimensions
        readonly property real screenWidth: cornersShape.width
        readonly property real screenHeight: cornersShape.height

        // Only show screen corners if enabled and appropriate conditions are met
        readonly property bool shouldShow: Settings.data.general.showScreenCorners

        // ShapePath configuration
        strokeWidth: -1 // No stroke, fill only
        fillColor: shouldShow ? cornerColor : "transparent"

        // Smooth color animation (disabled during theme transitions to sync with Color.qml)
        Behavior on fillColor {
          enabled: !Color.isTransitioning
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        // ========== PATH DEFINITION ==========
        // Draws 4 separate corner squares at screen edges
        // Each corner square has a concave arc on the inner diagonal

        // ========== TOP-LEFT CORNER ==========
        // Arc is at the bottom-right of this square (inner diagonal)
        // Start at top-left screen corner
        startX: leftMargin
        startY: topMargin

        // Top edge (moving right)
        PathLine {
          relativeX: cornersPath.cornerSize
          relativeY: 0
        }

        // Right edge (moving down toward arc)
        PathLine {
          relativeX: 0
          relativeY: cornersPath.cornerSize - cornersPath.cornerRadius
        }

        // Concave arc (bottom-right corner of square, curving inward toward screen center)
        PathArc {
          relativeX: -cornersPath.cornerRadius
          relativeY: cornersPath.cornerRadius
          radiusX: cornersPath.cornerRadius
          radiusY: cornersPath.cornerRadius
          direction: PathArc.Counterclockwise
        }

        // Bottom edge (moving left)
        PathLine {
          relativeX: -(cornersPath.cornerSize - cornersPath.cornerRadius)
          relativeY: 0
        }

        // Left edge (moving up) - closes back to start
        PathLine {
          relativeX: 0
          relativeY: -cornersPath.cornerSize
        }

        // ========== TOP-RIGHT CORNER ==========
        // Arc is at the bottom-left of this square (inner diagonal)
        PathMove {
          x: cornersPath.screenWidth - cornersPath.rightMargin - cornersPath.cornerSize
          y: cornersPath.topMargin
        }

        // Top edge (moving right)
        PathLine {
          relativeX: cornersPath.cornerSize
          relativeY: 0
        }

        // Right edge (moving down)
        PathLine {
          relativeX: 0
          relativeY: cornersPath.cornerSize
        }

        // Bottom edge (moving left toward arc)
        PathLine {
          relativeX: -(cornersPath.cornerSize - cornersPath.cornerRadius)
          relativeY: 0
        }

        // Concave arc (bottom-left corner of square, curving inward toward screen center)
        PathArc {
          relativeX: -cornersPath.cornerRadius
          relativeY: -cornersPath.cornerRadius
          radiusX: cornersPath.cornerRadius
          radiusY: cornersPath.cornerRadius
          direction: PathArc.Counterclockwise
        }

        // Left edge (moving up) - closes back to start
        PathLine {
          relativeX: 0
          relativeY: -(cornersPath.cornerSize - cornersPath.cornerRadius)
        }

        // ========== BOTTOM-LEFT CORNER ==========
        // Arc is at the top-right of this square (inner diagonal)
        PathMove {
          x: cornersPath.leftMargin
          y: cornersPath.screenHeight - cornersPath.bottomMargin - cornersPath.cornerSize
        }

        // Top edge (moving right toward arc)
        PathLine {
          relativeX: cornersPath.cornerSize - cornersPath.cornerRadius
          relativeY: 0
        }

        // Concave arc (top-right corner of square, curving inward toward screen center)
        PathArc {
          relativeX: cornersPath.cornerRadius
          relativeY: cornersPath.cornerRadius
          radiusX: cornersPath.cornerRadius
          radiusY: cornersPath.cornerRadius
          direction: PathArc.Counterclockwise
        }

        // Right edge (moving down)
        PathLine {
          relativeX: 0
          relativeY: cornersPath.cornerSize - cornersPath.cornerRadius
        }

        // Bottom edge (moving left)
        PathLine {
          relativeX: -cornersPath.cornerSize
          relativeY: 0
        }

        // Left edge (moving up) - closes back to start
        PathLine {
          relativeX: 0
          relativeY: -cornersPath.cornerSize
        }

        // ========== BOTTOM-RIGHT CORNER ==========
        // Arc is at the top-left of this square (inner diagonal)
        // Start at bottom-right of square (different from other corners!)
        PathMove {
          x: cornersPath.screenWidth - cornersPath.rightMargin
          y: cornersPath.screenHeight - cornersPath.bottomMargin
        }

        // Bottom edge (moving left)
        PathLine {
          relativeX: -cornersPath.cornerSize
          relativeY: 0
        }

        // Left edge (moving up toward arc)
        PathLine {
          relativeX: 0
          relativeY: -(cornersPath.cornerSize - cornersPath.cornerRadius)
        }

        // Concave arc (top-left corner of square, curving inward toward screen center)
        PathArc {
          relativeX: cornersPath.cornerRadius
          relativeY: -cornersPath.cornerRadius
          radiusX: cornersPath.cornerRadius
          radiusY: cornersPath.cornerRadius
          direction: PathArc.Counterclockwise
        }

        // Top edge (moving right)
        PathLine {
          relativeX: cornersPath.cornerSize - cornersPath.cornerRadius
          relativeY: 0
        }

        // Right edge (moving down) - closes back to start
        PathLine {
          relativeX: 0
          relativeY: cornersPath.cornerSize
        }
      }

      ShapePath {
        strokeWidth: -1
        fillColor: root.feedbackColor(root.feedbackTopLeftOpacity)

        startX: cornersPath.leftMargin
        startY: cornersPath.topMargin

        PathLine { relativeX: cornersPath.cornerSize; relativeY: 0 }
        PathLine { relativeX: 0; relativeY: cornersPath.cornerSize - cornersPath.cornerRadius }
        PathArc {
          relativeX: -cornersPath.cornerRadius
          relativeY: cornersPath.cornerRadius
          radiusX: cornersPath.cornerRadius
          radiusY: cornersPath.cornerRadius
          direction: PathArc.Counterclockwise
        }
        PathLine { relativeX: -(cornersPath.cornerSize - cornersPath.cornerRadius); relativeY: 0 }
        PathLine { relativeX: 0; relativeY: -cornersPath.cornerSize }
      }

      ShapePath {
        strokeWidth: -1
        fillColor: root.feedbackColor(root.feedbackTopRightOpacity)

        startX: cornersPath.screenWidth - cornersPath.rightMargin - cornersPath.cornerSize
        startY: cornersPath.topMargin

        PathLine { relativeX: cornersPath.cornerSize; relativeY: 0 }
        PathLine { relativeX: 0; relativeY: cornersPath.cornerSize }
        PathLine { relativeX: -(cornersPath.cornerSize - cornersPath.cornerRadius); relativeY: 0 }
        PathArc {
          relativeX: -cornersPath.cornerRadius
          relativeY: -cornersPath.cornerRadius
          radiusX: cornersPath.cornerRadius
          radiusY: cornersPath.cornerRadius
          direction: PathArc.Counterclockwise
        }
        PathLine { relativeX: 0; relativeY: -(cornersPath.cornerSize - cornersPath.cornerRadius) }
      }

      ShapePath {
        strokeWidth: -1
        fillColor: root.feedbackColor(root.feedbackBottomLeftOpacity)

        startX: cornersPath.leftMargin
        startY: cornersPath.screenHeight - cornersPath.bottomMargin - cornersPath.cornerSize

        PathLine { relativeX: cornersPath.cornerSize - cornersPath.cornerRadius; relativeY: 0 }
        PathArc {
          relativeX: cornersPath.cornerRadius
          relativeY: cornersPath.cornerRadius
          radiusX: cornersPath.cornerRadius
          radiusY: cornersPath.cornerRadius
          direction: PathArc.Counterclockwise
        }
        PathLine { relativeX: 0; relativeY: cornersPath.cornerSize - cornersPath.cornerRadius }
        PathLine { relativeX: -cornersPath.cornerSize; relativeY: 0 }
        PathLine { relativeX: 0; relativeY: -cornersPath.cornerSize }
      }

      ShapePath {
        strokeWidth: -1
        fillColor: root.feedbackColor(root.feedbackBottomRightOpacity)

        startX: cornersPath.screenWidth - cornersPath.rightMargin
        startY: cornersPath.screenHeight - cornersPath.bottomMargin

        PathLine { relativeX: -cornersPath.cornerSize; relativeY: 0 }
        PathLine { relativeX: 0; relativeY: -(cornersPath.cornerSize - cornersPath.cornerRadius) }
        PathArc {
          relativeX: cornersPath.cornerRadius
          relativeY: -cornersPath.cornerRadius
          radiusX: cornersPath.cornerRadius
          radiusY: cornersPath.cornerRadius
          direction: PathArc.Counterclockwise
        }
        PathLine { relativeX: cornersPath.cornerSize - cornersPath.cornerRadius; relativeY: 0 }
        PathLine { relativeX: 0; relativeY: cornersPath.cornerSize }
      }
    }
  }

  SequentialAnimation {
    id: feedbackTopLeftAnim
    PropertyAnimation { target: root; property: "feedbackTopLeftOpacity"; to: 1; duration: Style.animationNormal }
    PropertyAnimation { target: root; property: "feedbackTopLeftOpacity"; to: 0; duration: Style.animationSlowest }
  }

  SequentialAnimation {
    id: feedbackTopRightAnim
    PropertyAnimation { target: root; property: "feedbackTopRightOpacity"; to: 1; duration: Style.animationNormal }
    PropertyAnimation { target: root; property: "feedbackTopRightOpacity"; to: 0; duration: Style.animationSlowest }
  }

  SequentialAnimation {
    id: feedbackBottomLeftAnim
    PropertyAnimation { target: root; property: "feedbackBottomLeftOpacity"; to: 1; duration: Style.animationNormal }
    PropertyAnimation { target: root; property: "feedbackBottomLeftOpacity"; to: 0; duration: Style.animationSlowest }
  }

  SequentialAnimation {
    id: feedbackBottomRightAnim
    PropertyAnimation { target: root; property: "feedbackBottomRightOpacity"; to: 1; duration: Style.animationNormal }
    PropertyAnimation { target: root; property: "feedbackBottomRightOpacity"; to: 0; duration: Style.animationSlowest }
  }

  function triggerHotCorner(cornerKey) {
    var command = Settings.getHotCornerCommandForScreen(root.screenName, cornerKey);
    if (command && command.trim() !== "") {
      Quickshell.execDetached(["sh", "-c", command]);
    }
  }

  function triggerFeedback(cornerKey) {
    if (!feedbackEnabled) {
      return;
    }

    if (cornerKey === "TopLeft") {
      feedbackTopLeftAnim.stop();
      root.feedbackTopLeftOpacity = 0;
      feedbackTopLeftAnim.start();
      return;
    }
    if (cornerKey === "TopRight") {
      feedbackTopRightAnim.stop();
      root.feedbackTopRightOpacity = 0;
      feedbackTopRightAnim.start();
      return;
    }
    if (cornerKey === "BottomLeft") {
      feedbackBottomLeftAnim.stop();
      root.feedbackBottomLeftOpacity = 0;
      feedbackBottomLeftAnim.start();
      return;
    }
    if (cornerKey === "BottomRight") {
      feedbackBottomRightAnim.stop();
      root.feedbackBottomRightOpacity = 0;
      feedbackBottomRightAnim.start();
    }
  }

  Repeater {
    model: [
      {
        "key": "TopLeft",
        "top": true,
        "left": true
      },
      {
        "key": "TopRight",
        "top": true,
        "right": true
      },
      {
        "key": "BottomLeft",
        "bottom": true,
        "left": true
      },
      {
        "key": "BottomRight",
        "bottom": true,
        "right": true
      }
    ]
    delegate: MouseArea {
      anchors.top: modelData.top ? parent.top : undefined
      anchors.bottom: modelData.bottom ? parent.bottom : undefined
      anchors.left: modelData.left ? parent.left : undefined
      anchors.right: modelData.right ? parent.right : undefined
      width: 3
      height: 3
      hoverEnabled: true
      enabled: Settings.getHotCornerEnabledForScreen(root.screenName, modelData.key)
      property int cooldownMs: 500
      property double lastTriggeredMs: 0

      onEntered: {
        var now = Date.now();
        if (now - lastTriggeredMs < cooldownMs) {
          return;
        }
        lastTriggeredMs = now;
        triggerFeedback(modelData.key);
        triggerHotCorner(modelData.key);
      }
    }
  }
}
