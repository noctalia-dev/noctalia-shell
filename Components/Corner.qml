import QtQuick
import QtQuick.Shapes
import qs.Settings

Shape {
    id: root
    
    property string position: "topleft"  // Corner position: topleft/topright/bottomleft/bottomright
    property real size: 1.0 * Theme.scale(Screen)              // Scale multiplier for entire corner
    property int concaveWidth: 100 * size
    property int concaveHeight: 60 * size
    property int offsetX: -20 * Theme.scale(Screen)
    property int offsetY: -20 * Theme.scale(Screen)
    property color fillColor: Theme.accentPrimary
    property int arcRadius: 20 * size

    property var modelData: null
    
    // Position flags derived from position string - calculated once
    readonly property bool _isTop: position.includes("top")
    readonly property bool _isLeft: position.includes("left")
    readonly property bool _isRight: position.includes("right")
    readonly property bool _isBottom: position.includes("bottom")
    
    // Shift the path vertically if offsetY is negative to pull shape up
    readonly property real pathOffsetY: Math.min(offsetY, 0)
    
    // Base coordinates for left corner shape, shifted by pathOffsetY vertically
    readonly property real _baseStartX: 30 * size
    readonly property real _baseStartY: (_isTop ? 20 * size : 0) + pathOffsetY
    readonly property real _baseLineX: 30 * size  
    readonly property real _baseLineY: (_isTop ? 0 : 20 * size) + pathOffsetY
    readonly property real _baseArcX: 50 * size
    readonly property real _baseArcY: (_isTop ? 20 * size : 0) + pathOffsetY
    
    // Mirror coordinates for right corners
    readonly property real _startX: _isRight ? (concaveWidth - _baseStartX) : _baseStartX
    readonly property real _startY: _baseStartY
    readonly property real _lineX: _isRight ? (concaveWidth - _baseLineX) : _baseLineX
    readonly property real _lineY: _baseLineY
    readonly property real _arcX: _isRight ? (concaveWidth - _baseArcX) : _baseArcX
    readonly property real _arcY: _baseArcY
    
    // Arc direction varies by corner to maintain proper concave shape
    readonly property int _arcDirection: {
        if (_isTop && _isLeft) return PathArc.Counterclockwise
        if (_isTop && _isRight) return PathArc.Clockwise
        if (_isBottom && _isLeft) return PathArc.Clockwise
        if (_isBottom && _isRight) return PathArc.Counterclockwise
        return PathArc.Counterclockwise
    }
    
    width: concaveWidth
    height: concaveHeight
    
    // Position relative to parent based on corner type
    x: _isLeft ? offsetX : (parent ? parent.width - width + offsetX : 0)
    y: _isTop ? offsetY : (parent ? parent.height - height + offsetY : 0)
    
    // Optimized rendering settings - reduced quality for better performance
    preferredRendererType: Shape.GeometryRenderer  // Use simpler renderer
    layer.enabled: false  // Disable layer rendering to save memory
    antialiasing: true    // Use standard antialiasing instead of MSAA

    ShapePath {
        strokeWidth: 0
        fillColor: root.fillColor
        strokeColor: root.fillColor

        startX: root._startX
        startY: root._startY

        PathLine { 
            x: root._lineX
            y: root._lineY 
        }

        PathArc {
            x: root._arcX
            y: root._arcY
            radiusX: root.arcRadius
            radiusY: root.arcRadius
            useLargeArc: false
            direction: root._arcDirection
        }
    }
}
