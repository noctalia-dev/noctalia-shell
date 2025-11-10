import QtQuick
import QtQuick.Shapes
import qs.Commons


/**
 * ScreenCorners - Shape component for rendering screen corners
 *
 * Renders concave corners at the screen edges to create a rounded screen effect.
 * Self-contained Shape component (no shadows).
 */
Item {
  id: root

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

      ShapePath {
        id: cornersPath

        // Corner configuration
        readonly property color cornerColor: Settings.data.general.forceBlackScreenCorners ? Color.black : Color.mSurface
        readonly property real cornerRadius: Style.screenRadius
        readonly property real cornerSize: Style.screenRadius

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
        fillColor: shouldShow ? cornerColor : Color.transparent

        // Smooth color animation
        Behavior on fillColor {
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
    }
  }
}
