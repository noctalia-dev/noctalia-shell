import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Modules.MainScreen.Backgrounds
import qs.Services.UI

/**
* BarBackground - ShapePath component for rendering the bar background
*
* Unified shadow system. This component is a ShapePath that will be
* a child of the unified AllBackgrounds Shape container.
*
* Uses 4-state per-corner system for flexible corner rendering:
* - State -1: No radius (flat/square corner)
* - State 0: Normal (inner curve)
* - State 1: Horizontal inversion (outer curve on X-axis)
* - State 2: Vertical inversion (outer curve on Y-axis)
*/
ShapePath {
  id: root

  // Required reference to the bar component
  required property var bar

  // Required reference to AllBackgrounds shapeContainer
  required property var shapeContainer

  // Required reference to windowRoot for screen access
  required property var windowRoot

  required property color backgroundColor

  // Check if bar should be visible on this screen
  readonly property bool shouldShow: {
    // Check global bar visibility (includes overview state)
    if (!BarService.effectivelyVisible)
      return false;

    // Check screen-specific configuration
    var monitors = Settings.data.bar.monitors || [];
    var screenName = windowRoot?.screen?.name || "";

    // If no monitors specified, show on all screens
    // If monitors specified, only show if this screen is in the list
    return monitors.length === 0 || monitors.includes(screenName);
  }

  // Corner radius (from Style)
  readonly property real radius: Style.radiusL

  // Framed bar properties
  readonly property bool isFramed: Settings.data.bar.barType === "framed"
  readonly property real frameThickness: Settings.data.bar.frameThickness ?? 12
  readonly property real frameRadius: Settings.data.bar.frameRadius ?? 20

  // Bar position - since bar's parent fills the screen and Shape also fills the screen,
  // we can use bar.x and bar.y directly (they're already in screen coordinates)
  readonly property point barMappedPos: bar ? Qt.point(bar.x, bar.y) : Qt.point(0, 0)

  // Effective dimensions - 0 when bar shouldn't show (similar to panel behavior)
  readonly property real barWidth: (bar && shouldShow) ? bar.width : 0
  readonly property real barHeight: (bar && shouldShow) ? bar.height : 0

  // Screen dimensions for frame
  readonly property real screenWidth: windowRoot?.screen?.width || 0
  readonly property real screenHeight: windowRoot?.screen?.height || 0

  // Inner hole dimensions for framed mode - always relative to screen
  readonly property string barPosition: Settings.getBarPositionForScreen(windowRoot?.screen?.name)
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property real holeX: (barPosition === "left") ? barWidth : frameThickness
  readonly property real holeY: (barPosition === "top") ? barHeight : frameThickness
  readonly property real holeWidth: screenWidth - (barPosition === "left" || barPosition === "right" ? (barWidth + frameThickness) : (frameThickness * 2))
  readonly property real holeHeight: screenHeight - (barPosition === "top" || barPosition === "bottom" ? (barHeight + frameThickness) : (frameThickness * 2))

  // Flatten corners if bar is too small (handle null bar)
  readonly property bool shouldFlatten: bar ? ShapeCornerHelper.shouldFlatten(barWidth, barHeight, radius) : false
  readonly property real effectiveRadius: shouldFlatten ? (bar ? ShapeCornerHelper.getFlattenedRadius(Math.min(barWidth, barHeight), radius) : 0) : radius

  // Helper function for getting corner radius based on state
  function getCornerRadius(cornerState) {
    // State -1 = no radius (flat corner)
    if (cornerState === -1)
      return 0;
    // All other states use effectiveRadius
    return effectiveRadius;
  }

  // Per-corner multipliers and radii based on bar's corner states (handle null bar)
  readonly property real tlMultX: bar ? ShapeCornerHelper.getMultX(bar.topLeftCornerState) : 1
  readonly property real tlMultY: bar ? ShapeCornerHelper.getMultY(bar.topLeftCornerState) : 1
  readonly property real tlRadius: bar ? getCornerRadius(bar.topLeftCornerState) : 0

  readonly property real trMultX: bar ? ShapeCornerHelper.getMultX(bar.topRightCornerState) : 1
  readonly property real trMultY: bar ? ShapeCornerHelper.getMultY(bar.topRightCornerState) : 1
  readonly property real trRadius: bar ? getCornerRadius(bar.topRightCornerState) : 0

  readonly property real brMultX: bar ? ShapeCornerHelper.getMultX(bar.bottomRightCornerState) : 1
  readonly property real brMultY: bar ? ShapeCornerHelper.getMultY(bar.bottomRightCornerState) : 1
  readonly property real brRadius: bar ? getCornerRadius(bar.bottomRightCornerState) : 0

  readonly property real blMultX: bar ? ShapeCornerHelper.getMultX(bar.bottomLeftCornerState) : 1
  readonly property real blMultY: bar ? ShapeCornerHelper.getMultY(bar.bottomLeftCornerState) : 1
  readonly property real blRadius: bar ? getCornerRadius(bar.bottomLeftCornerState) : 0

  // Extend bar background beyond screen edges where both adjacent corners are flat,
  // to prevent CurveRenderer antialiasing artifacts on screen-flush edges
  readonly property real screenEdgeOvershoot: 2
  readonly property real topEdgeOvs: (!isFramed && shouldShow && tlRadius === 0 && trRadius === 0 && barMappedPos.y <= 0) ? -screenEdgeOvershoot : 0
  readonly property real bottomEdgeOvs: (!isFramed && shouldShow && blRadius === 0 && brRadius === 0 && (barMappedPos.y + barHeight) >= screenHeight) ? screenEdgeOvershoot : 0
  readonly property real leftEdgeOvs: (!isFramed && shouldShow && tlRadius === 0 && blRadius === 0 && barMappedPos.x <= 0) ? -screenEdgeOvershoot : 0
  readonly property real rightEdgeOvs: (!isFramed && shouldShow && trRadius === 0 && brRadius === 0 && (barMappedPos.x + barWidth) >= screenWidth) ? screenEdgeOvershoot : 0

  // Auto-hide opacity factor for background fade
  property real opacityFactor: (bar && bar.isHidden) ? 0 : 1

  Behavior on opacityFactor {
    enabled: bar && bar.autoHide
    NumberAnimation {
      duration: Style.animationFast
      easing.type: Style.easingTypeFast
    }
  }

  // ShapePath configuration
  strokeWidth: -1 // No stroke, fill only
  fillColor: Qt.rgba(backgroundColor.r, backgroundColor.g, backgroundColor.b, backgroundColor.a * opacityFactor)
  fillRule: isFramed ? ShapePath.OddEvenFill : ShapePath.WindingFill

  // Starting position
  // In framed mode, we start at (0,0) to draw the screen rectangle first
  startX: isFramed ? 0 : (barMappedPos.x + leftEdgeOvs + tlRadius * tlMultX)
  startY: isFramed ? 0 : (barMappedPos.y + topEdgeOvs)

  // ========== PATH DEFINITION ==========

  // 1. Main Bar / Outer Screen Rectangle
  PathLine {
    x: {
      if (!root.shouldShow)
        return 0;
      if (root.isFramed)
        return root.screenWidth;
      return root.barMappedPos.x + root.barWidth + root.rightEdgeOvs - root.trRadius * root.trMultX;
    }
    y: root.isFramed ? 0 : (root.barMappedPos.y + root.topEdgeOvs)
  }

  // Bar top-right corner (only if not framed)
  PathArc {
    x: root.isFramed ? (root.shouldShow ? root.screenWidth : 0) : (root.barMappedPos.x + root.barWidth + root.rightEdgeOvs)
    y: root.isFramed ? 0 : (root.barMappedPos.y + root.topEdgeOvs + root.trRadius * root.trMultY)
    radiusX: root.isFramed ? 0 : root.trRadius
    radiusY: root.isFramed ? 0 : root.trRadius
    direction: ShapeCornerHelper.getArcDirection(root.trMultX, root.trMultY)
  }

  PathLine {
    x: root.isFramed ? (root.shouldShow ? root.screenWidth : 0) : (root.barMappedPos.x + root.barWidth + root.rightEdgeOvs)
    y: {
      if (!root.shouldShow)
        return 0;
      if (root.isFramed)
        return root.screenHeight;
      return root.barMappedPos.y + root.barHeight + root.bottomEdgeOvs - root.brRadius * root.brMultY;
    }
  }

  // Bar bottom-right corner (only if not framed)
  PathArc {
    x: root.isFramed ? (root.shouldShow ? root.screenWidth : 0) : (root.barMappedPos.x + root.barWidth + root.rightEdgeOvs - root.brRadius * root.brMultX)
    y: root.isFramed ? (root.shouldShow ? root.screenHeight : 0) : (root.barMappedPos.y + root.barHeight + root.bottomEdgeOvs)
    radiusX: root.isFramed ? 0 : root.brRadius
    radiusY: root.isFramed ? 0 : root.brRadius
    direction: ShapeCornerHelper.getArcDirection(root.brMultX, root.brMultY)
  }

  PathLine {
    x: {
      if (!root.shouldShow)
        return 0;
      if (root.isFramed)
        return 0;
      return root.barMappedPos.x + root.leftEdgeOvs + root.blRadius * root.blMultX;
    }
    y: root.isFramed ? (root.shouldShow ? root.screenHeight : 0) : (root.barMappedPos.y + root.barHeight + root.bottomEdgeOvs)
  }

  // Bar bottom-left corner (only if not framed)
  PathArc {
    x: root.isFramed ? 0 : (root.barMappedPos.x + root.leftEdgeOvs)
    y: root.isFramed ? (root.shouldShow ? root.screenHeight : 0) : (root.barMappedPos.y + root.barHeight + root.bottomEdgeOvs - root.blRadius * root.blMultY)
    radiusX: root.isFramed ? 0 : root.blRadius
    radiusY: root.isFramed ? 0 : root.blRadius
    direction: ShapeCornerHelper.getArcDirection(root.blMultX, root.blMultY)
  }

  PathLine {
    x: root.isFramed ? 0 : (root.barMappedPos.x + root.leftEdgeOvs)
    y: {
      if (!root.shouldShow)
        return 0;
      if (root.isFramed)
        return 0;
      return root.barMappedPos.y + root.topEdgeOvs + root.tlRadius * root.tlMultY;
    }
  }

  // Bar top-left corner (only if not framed, back to start)
  PathArc {
    x: root.isFramed ? 0 : (root.barMappedPos.x + root.leftEdgeOvs + root.tlRadius * root.tlMultX)
    y: root.isFramed ? 0 : (root.barMappedPos.y + root.topEdgeOvs)
    radiusX: root.isFramed ? 0 : root.tlRadius
    radiusY: root.isFramed ? 0 : root.tlRadius
    direction: ShapeCornerHelper.getArcDirection(root.tlMultX, root.tlMultY)
  }

  // 2. Inner Hole for Framed Mode (Clockwise)
  PathMove {
    x: (root.isFramed && root.shouldShow) ? (root.holeX + root.frameRadius) : root.startX
    y: (root.isFramed && root.shouldShow) ? root.holeY : root.startY
  }

  // Top edge
  PathLine {
    x: (root.isFramed && root.shouldShow) ? (root.holeX + root.holeWidth - root.frameRadius) : ((root.isFramed && root.shouldShow) ? (root.holeX + root.frameRadius) : root.startX)
    y: (root.isFramed && root.shouldShow) ? root.holeY : ((root.isFramed && root.shouldShow) ? root.holeY : root.startY)
  }

  // Top-right corner
  PathArc {
    x: (root.isFramed && root.shouldShow) ? (root.holeX + root.holeWidth) : ((root.isFramed && root.shouldShow) ? (root.holeX + root.holeWidth - root.frameRadius) : root.startX)
    y: (root.isFramed && root.shouldShow) ? (root.holeY + root.frameRadius) : ((root.isFramed && root.shouldShow) ? root.holeY : root.startY)
    radiusX: (root.isFramed && root.shouldShow) ? root.frameRadius : 0
    radiusY: (root.isFramed && root.shouldShow) ? root.frameRadius : 0
    direction: PathArc.Clockwise
  }

  // Right edge
  PathLine {
    x: (root.isFramed && root.shouldShow) ? (root.holeX + root.holeWidth) : root.startX
    y: (root.isFramed && root.shouldShow) ? (root.holeY + root.holeHeight - root.frameRadius) : root.startY
  }

  // Bottom-right corner
  PathArc {
    x: (root.isFramed && root.shouldShow) ? (root.holeX + root.holeWidth - root.frameRadius) : root.startX
    y: (root.isFramed && root.shouldShow) ? (root.holeY + root.holeHeight) : root.startY
    radiusX: (root.isFramed && root.shouldShow) ? root.frameRadius : 0
    radiusY: (root.isFramed && root.shouldShow) ? root.frameRadius : 0
    direction: PathArc.Clockwise
  }

  // Bottom edge
  PathLine {
    x: (root.isFramed && root.shouldShow) ? (root.holeX + root.frameRadius) : root.startX
    y: (root.isFramed && root.shouldShow) ? (root.holeY + root.holeHeight) : root.startY
  }

  // Bottom-left corner
  PathArc {
    x: (root.isFramed && root.shouldShow) ? root.holeX : root.startX
    y: (root.isFramed && root.shouldShow) ? (root.holeY + root.holeHeight - root.frameRadius) : root.startY
    radiusX: (root.isFramed && root.shouldShow) ? root.frameRadius : 0
    radiusY: (root.isFramed && root.shouldShow) ? root.frameRadius : 0
    direction: PathArc.Clockwise
  }

  // Left edge
  PathLine {
    x: (root.isFramed && root.shouldShow) ? root.holeX : root.startX
    y: (root.isFramed && root.shouldShow) ? (root.holeY + root.frameRadius) : root.startY
  }

  // Top-left corner (back to start)
  PathArc {
    x: (root.isFramed && root.shouldShow) ? (root.holeX + root.frameRadius) : root.startX
    y: (root.isFramed && root.shouldShow) ? root.holeY : root.startY
    radiusX: (root.isFramed && root.shouldShow) ? root.frameRadius : 0
    radiusY: (root.isFramed && root.shouldShow) ? root.frameRadius : 0
    direction: PathArc.Clockwise
  }
}
