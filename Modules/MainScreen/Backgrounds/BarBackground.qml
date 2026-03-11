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

  // Minimum safe arc radius — prevents zero-displacement zero-radius PathArcs
  // that crash qTriangulate in CurveRenderer. 0.01px is sub-pixel and invisible.
  readonly property real _minR: 0.01

  // Helper function for getting corner radius based on state
  function getCornerRadius(cornerState) {
    // State -1 = flat corner — use minimum safe radius instead of 0
    // to prevent degenerate PathArc (zero displacement + zero radius)
    if (cornerState === -1)
      return _minR;
    // All other states use effectiveRadius (clamped to safe minimum)
    return Math.max(_minR, effectiveRadius);
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

  // True when the bar path has valid, non-degenerate geometry to render.
  // Mirrors PanelBackground.isRenderable — prevents CurveRenderer crash on zero-area paths.
  readonly property bool isRenderable: bar !== null && shouldShow && (isFramed ? (screenWidth > 0 && screenHeight > 0) : (barWidth > 0 && barHeight > 0))

  // Edge overshoot: extend bar background beyond screen edges where both adjacent
  // corners are flat (state -1) to prevent CurveRenderer antialiasing artifacts.
  // Uses corner state checks instead of radius === 0 since flat corners now have _minR.
  readonly property real screenEdgeOvershoot: 2
  readonly property real topEdgeOvs: (!isFramed && shouldShow && bar && bar.topLeftCornerState === -1 && bar.topRightCornerState === -1 && barMappedPos.y <= 0) ? -screenEdgeOvershoot : 0
  readonly property real bottomEdgeOvs: (!isFramed && shouldShow && bar && bar.bottomLeftCornerState === -1 && bar.bottomRightCornerState === -1 && (barMappedPos.y + barHeight) >= screenHeight) ? screenEdgeOvershoot : 0
  readonly property real leftEdgeOvs: (!isFramed && shouldShow && bar && bar.topLeftCornerState === -1 && bar.bottomLeftCornerState === -1 && barMappedPos.x <= 0) ? -screenEdgeOvershoot : 0
  readonly property real rightEdgeOvs: (!isFramed && shouldShow && bar && bar.topRightCornerState === -1 && bar.bottomRightCornerState === -1 && (barMappedPos.x + barWidth) >= screenWidth) ? screenEdgeOvershoot : 0

  // Auto-hide opacity factor for background fade
  property real opacityFactor: (bar && bar.isHidden) ? 0 : 1

  Behavior on opacityFactor {
    enabled: bar && bar.autoHide
    NumberAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutQuad
    }
  }

  // ShapePath configuration
  strokeWidth: -1 // No stroke, fill only
  fillColor: isRenderable ? Qt.rgba(backgroundColor.r, backgroundColor.g, backgroundColor.b, backgroundColor.a * opacityFactor) : "transparent"
  fillRule: isFramed ? ShapePath.OddEvenFill : ShapePath.WindingFill

  // Starting position — falls back to off-screen when not renderable so that
  // all subsequent path elements form a valid non-degenerate off-screen square.
  // Each edge is split between PathLine and PathArc so no arc has zero displacement,
  // preventing CurveRenderer triangulation crashes on degenerate arcs.
  // For framed mode the outer path is a full-screen rectangle; _minR offsets at each
  // corner prevent zero-displacement zero-radius arcs that crash qTriangulate.
  startX: isRenderable ? (isFramed ? _minR : (barMappedPos.x + leftEdgeOvs + tlRadius * tlMultX)) : -0.75
  startY: isRenderable ? (isFramed ? 0 : (barMappedPos.y + topEdgeOvs)) : -1

  // ========== PATH DEFINITION ==========

  // 1. Main Bar / Outer Screen Rectangle
  // When !isRenderable all elements use fallback coordinates forming a valid 1×1
  // off-screen square with non-degenerate arcs so CurveRenderer never receives
  // a zero-area, bare-moveto, or zero-displacement arc path.
  PathLine {
    x: root.isRenderable ? (root.isFramed ? (root.screenWidth - root._minR) : (root.barMappedPos.x + root.barWidth + root.rightEdgeOvs - root.trRadius * root.trMultX)) : 0
    y: root.isRenderable ? (root.isFramed ? 0 : (root.barMappedPos.y + root.topEdgeOvs)) : -1
  }

  // Top-right corner
  PathArc {
    x: root.isRenderable ? (root.isFramed ? root.screenWidth : (root.barMappedPos.x + root.barWidth + root.rightEdgeOvs)) : 0
    y: root.isRenderable ? (root.isFramed ? root._minR : (root.barMappedPos.y + root.topEdgeOvs + root.trRadius * root.trMultY)) : -0.75
    radiusX: root.isRenderable ? (root.isFramed ? root._minR : root.trRadius) : 0
    radiusY: root.isRenderable ? (root.isFramed ? root._minR : root.trRadius) : 0
    direction: ShapeCornerHelper.getArcDirection(root.trMultX, root.trMultY)
  }

  PathLine {
    x: root.isRenderable ? (root.isFramed ? root.screenWidth : (root.barMappedPos.x + root.barWidth + root.rightEdgeOvs)) : 0
    y: root.isRenderable ? (root.isFramed ? (root.screenHeight - root._minR) : (root.barMappedPos.y + root.barHeight + root.bottomEdgeOvs - root.brRadius * root.brMultY)) : 0
  }

  // Bottom-right corner
  PathArc {
    x: root.isRenderable ? (root.isFramed ? (root.screenWidth - root._minR) : (root.barMappedPos.x + root.barWidth + root.rightEdgeOvs - root.brRadius * root.brMultX)) : -0.25
    y: root.isRenderable ? (root.isFramed ? root.screenHeight : (root.barMappedPos.y + root.barHeight + root.bottomEdgeOvs)) : 0
    radiusX: root.isRenderable ? (root.isFramed ? root._minR : root.brRadius) : 0
    radiusY: root.isRenderable ? (root.isFramed ? root._minR : root.brRadius) : 0
    direction: ShapeCornerHelper.getArcDirection(root.brMultX, root.brMultY)
  }

  PathLine {
    x: root.isRenderable ? (root.isFramed ? root._minR : (root.barMappedPos.x + root.leftEdgeOvs + root.blRadius * root.blMultX)) : -1
    y: root.isRenderable ? (root.isFramed ? root.screenHeight : (root.barMappedPos.y + root.barHeight + root.bottomEdgeOvs)) : 0
  }

  // Bottom-left corner
  PathArc {
    x: root.isRenderable ? (root.isFramed ? 0 : (root.barMappedPos.x + root.leftEdgeOvs)) : -1
    y: root.isRenderable ? (root.isFramed ? (root.screenHeight - root._minR) : (root.barMappedPos.y + root.barHeight + root.bottomEdgeOvs - root.blRadius * root.blMultY)) : -0.25
    radiusX: root.isRenderable ? (root.isFramed ? root._minR : root.blRadius) : 0
    radiusY: root.isRenderable ? (root.isFramed ? root._minR : root.blRadius) : 0
    direction: ShapeCornerHelper.getArcDirection(root.blMultX, root.blMultY)
  }

  PathLine {
    x: root.isRenderable ? (root.isFramed ? 0 : (root.barMappedPos.x + root.leftEdgeOvs)) : -1
    y: root.isRenderable ? (root.isFramed ? root._minR : (root.barMappedPos.y + root.topEdgeOvs + root.tlRadius * root.tlMultY)) : -1
  }

  // Top-left corner (back to start)
  PathArc {
    x: root.isRenderable ? (root.isFramed ? root._minR : (root.barMappedPos.x + root.leftEdgeOvs + root.tlRadius * root.tlMultX)) : -0.75
    y: root.isRenderable ? (root.isFramed ? 0 : (root.barMappedPos.y + root.topEdgeOvs)) : -1
    radiusX: root.isRenderable ? (root.isFramed ? root._minR : root.tlRadius) : 0
    radiusY: root.isRenderable ? (root.isFramed ? root._minR : root.tlRadius) : 0
    direction: ShapeCornerHelper.getArcDirection(root.tlMultX, root.tlMultY)
  }

  // 2. Inner Hole for Framed Mode (Clockwise)
  // When !isFramed, draws a tiny 1x1 rectangle inside the bar as a non-degenerate WindingFill
  // no-op to prevent a zero-area degenerate subpath crashing qTriangulate.
  // Note: an exact duplicate of the outer path cannot be used here because Qt's CurveRenderer
  // has issues with exactly coincident subpaths, causing the fill to not render on some systems.
  // When !isRenderable, falls back to a valid 1×1 off-screen square at (-3,-3)→(-2,-2).
  readonly property real _nhX: barMappedPos.x + barWidth / 2
  readonly property real _nhY: barMappedPos.y + barHeight / 2
  PathMove {
    x: root.isRenderable ? (root.isFramed ? (root.holeX + root.frameRadius) : (root._nhX + 0.25)) : -2.75
    y: root.isRenderable ? (root.isFramed ? root.holeY : root._nhY) : -3
  }

  // Top edge
  PathLine {
    x: root.isRenderable ? (root.isFramed ? (root.holeX + root.holeWidth - root.frameRadius) : (root._nhX + 1)) : -2
    y: root.isRenderable ? (root.isFramed ? root.holeY : root._nhY) : -3
  }

  // Top-right corner
  PathArc {
    x: root.isRenderable ? (root.isFramed ? (root.holeX + root.holeWidth) : (root._nhX + 1)) : -2
    y: root.isRenderable ? (root.isFramed ? (root.holeY + root.frameRadius) : (root._nhY + 0.25)) : -2.75
    radiusX: root.isRenderable ? (root.isFramed ? root.frameRadius : 0) : 0
    radiusY: root.isRenderable ? (root.isFramed ? root.frameRadius : 0) : 0
    direction: PathArc.Clockwise
  }

  // Right edge
  PathLine {
    x: root.isRenderable ? (root.isFramed ? (root.holeX + root.holeWidth) : (root._nhX + 1)) : -2
    y: root.isRenderable ? (root.isFramed ? (root.holeY + root.holeHeight - root.frameRadius) : (root._nhY + 1)) : -2
  }

  // Bottom-right corner
  PathArc {
    x: root.isRenderable ? (root.isFramed ? (root.holeX + root.holeWidth - root.frameRadius) : (root._nhX + 0.75)) : -2.25
    y: root.isRenderable ? (root.isFramed ? (root.holeY + root.holeHeight) : (root._nhY + 1)) : -2
    radiusX: root.isRenderable ? (root.isFramed ? root.frameRadius : 0) : 0
    radiusY: root.isRenderable ? (root.isFramed ? root.frameRadius : 0) : 0
    direction: PathArc.Clockwise
  }

  // Bottom edge
  PathLine {
    x: root.isRenderable ? (root.isFramed ? (root.holeX + root.frameRadius) : root._nhX) : -3
    y: root.isRenderable ? (root.isFramed ? (root.holeY + root.holeHeight) : (root._nhY + 1)) : -2
  }

  // Bottom-left corner
  PathArc {
    x: root.isRenderable ? (root.isFramed ? root.holeX : root._nhX) : -3
    y: root.isRenderable ? (root.isFramed ? (root.holeY + root.holeHeight - root.frameRadius) : (root._nhY + 0.75)) : -2.25
    radiusX: root.isRenderable ? (root.isFramed ? root.frameRadius : 0) : 0
    radiusY: root.isRenderable ? (root.isFramed ? root.frameRadius : 0) : 0
    direction: PathArc.Clockwise
  }

  // Left edge
  PathLine {
    x: root.isRenderable ? (root.isFramed ? root.holeX : root._nhX) : -3
    y: root.isRenderable ? (root.isFramed ? (root.holeY + root.frameRadius) : root._nhY) : -3
  }

  // Top-left corner (back to start)
  PathArc {
    x: root.isRenderable ? (root.isFramed ? (root.holeX + root.frameRadius) : (root._nhX + 0.25)) : -2.75
    y: root.isRenderable ? (root.isFramed ? root.holeY : root._nhY) : -3
    radiusX: root.isRenderable ? (root.isFramed ? root.frameRadius : 0) : 0
    radiusY: root.isRenderable ? (root.isFramed ? root.frameRadius : 0) : 0
    direction: PathArc.Clockwise
  }
}
