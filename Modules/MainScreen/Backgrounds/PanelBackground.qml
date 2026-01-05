import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Modules.MainScreen.Backgrounds

/**
* PanelBackground - Dynamic ShapePath for rendering panel backgrounds
*
* Dynamically switches between panels based on which panel is currently
* assigned by PanelService. Only 2 instances are needed: one for the
* currently open panel and one for a closing panel during transitions.
*
* Uses 4-state per-corner system for flexible corner rendering:
* - State -1: No radius (flat/square corner)
* - State 0: Normal (inner curve)
* - State 1: Horizontal inversion (outer curve on X-axis)
* - State 2: Vertical inversion (outer curve on Y-axis)
*/
ShapePath {
  id: root

  // Dynamically assigned panel (null if slot is unused)
  property var assignedPanel: null

  // Required reference to AllBackgrounds shapeContainer
  required property var shapeContainer

  // Default background color (used if panel doesn't specify one)
  property color defaultBackgroundColor: Color.mSurface

  // Corner radius (from Style)
  readonly property real radius: Style.radiusL

  // Get panel's panelRegion (geometry placeholder)
  readonly property var panelRegion: assignedPanel?.panelRegion ?? null

  // Get the actual panelBackground Item from panelRegion
  // Only access panelItem if panelRegion exists and is visible
  readonly property var panelBg: (panelRegion && panelRegion.visible) ? panelRegion.panelItem : null

  // Effective background color: use panel's if defined, else default
  readonly property color effectiveBackgroundColor: {
    if (!assignedPanel)
      return "transparent";
    if (assignedPanel.panelBackgroundColor !== undefined) {
      return assignedPanel.panelBackgroundColor;
    }
    return defaultBackgroundColor;
  }

  // Panel position - panelBg is in screen coordinates already
  readonly property real panelX: panelBg ? panelBg.x : 0
  readonly property real panelY: panelBg ? panelBg.y : 0
  readonly property real panelWidth: panelBg ? panelBg.width : 0
  readonly property real panelHeight: panelBg ? panelBg.height : 0

  // Flatten corners if panel is too small
  readonly property bool shouldFlatten: panelBg ? ShapeCornerHelper.shouldFlatten(panelWidth, panelHeight, radius) : false
  readonly property real effectiveRadius: shouldFlatten ? ShapeCornerHelper.getFlattenedRadius(Math.min(panelWidth, panelHeight), radius) : radius

  // Helper function for getting corner radius based on state
  function getCornerRadius(cornerState) {
    // State -1 = no radius (flat corner)
    if (cornerState === -1)
      return 0;
    // All other states use effectiveRadius
    return effectiveRadius;
  }

  // Per-corner multipliers and radii based on panelBg's corner states
  readonly property real tlMultX: panelBg ? ShapeCornerHelper.getMultX(panelBg.topLeftCornerState) : 1
  readonly property real tlMultY: panelBg ? ShapeCornerHelper.getMultY(panelBg.topLeftCornerState) : 1
  readonly property real tlRadius: panelBg ? getCornerRadius(panelBg.topLeftCornerState) : 0

  readonly property real trMultX: panelBg ? ShapeCornerHelper.getMultX(panelBg.topRightCornerState) : 1
  readonly property real trMultY: panelBg ? ShapeCornerHelper.getMultY(panelBg.topRightCornerState) : 1
  readonly property real trRadius: panelBg ? getCornerRadius(panelBg.topRightCornerState) : 0

  readonly property real brMultX: panelBg ? ShapeCornerHelper.getMultX(panelBg.bottomRightCornerState) : 1
  readonly property real brMultY: panelBg ? ShapeCornerHelper.getMultY(panelBg.bottomRightCornerState) : 1
  readonly property real brRadius: panelBg ? getCornerRadius(panelBg.bottomRightCornerState) : 0

  readonly property real blMultX: panelBg ? ShapeCornerHelper.getMultX(panelBg.bottomLeftCornerState) : 1
  readonly property real blMultY: panelBg ? ShapeCornerHelper.getMultY(panelBg.bottomLeftCornerState) : 1
  readonly property real blRadius: panelBg ? getCornerRadius(panelBg.bottomLeftCornerState) : 0

  // ShapePath configuration
  strokeWidth: -1 // No stroke, fill only

  // Starting position (top-left corner, after the arc)
  startX: panelX + tlRadius * tlMultX
  startY: panelY

  fillColor: effectiveBackgroundColor

  // ========== PATH DEFINITION ==========
  // Draws a rectangle with potentially inverted corners
  // All coordinates are relative to startX/startY

  // Top edge (moving right)
  PathLine {
    relativeX: root.panelWidth - root.tlRadius * root.tlMultX - root.trRadius * root.trMultX
    relativeY: 0
  }

  // Top-right corner arc
  PathArc {
    relativeX: root.trRadius * root.trMultX
    relativeY: root.trRadius * root.trMultY
    radiusX: root.trRadius
    radiusY: root.trRadius
    direction: ShapeCornerHelper.getArcDirection(root.trMultX, root.trMultY)
  }

  // Right edge (moving down)
  PathLine {
    relativeX: 0
    relativeY: root.panelHeight - root.trRadius * root.trMultY - root.brRadius * root.brMultY
  }

  // Bottom-right corner arc
  PathArc {
    relativeX: -root.brRadius * root.brMultX
    relativeY: root.brRadius * root.brMultY
    radiusX: root.brRadius
    radiusY: root.brRadius
    direction: ShapeCornerHelper.getArcDirection(root.brMultX, root.brMultY)
  }

  // Bottom edge (moving left)
  PathLine {
    relativeX: -(root.panelWidth - root.brRadius * root.brMultX - root.blRadius * root.blMultX)
    relativeY: 0
  }

  // Bottom-left corner arc
  PathArc {
    relativeX: -root.blRadius * root.blMultX
    relativeY: -root.blRadius * root.blMultY
    radiusX: root.blRadius
    radiusY: root.blRadius
    direction: ShapeCornerHelper.getArcDirection(root.blMultX, root.blMultY)
  }

  // Left edge (moving up) - closes the path back to start
  PathLine {
    relativeX: 0
    relativeY: -(root.panelHeight - root.blRadius * root.blMultY - root.tlRadius * root.tlMultY)
  }

  // Top-left corner arc (back to start)
  PathArc {
    relativeX: root.tlRadius * root.tlMultX
    relativeY: -root.tlRadius * root.tlMultY
    radiusX: root.tlRadius
    radiusY: root.tlRadius
    direction: ShapeCornerHelper.getArcDirection(root.tlMultX, root.tlMultY)
  }
}
