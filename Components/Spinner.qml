import QtQuick
import qs.Settings

Item {
    id: root
    
    property bool running: false
    property color color: "white"
    property int size: 16
    property int strokeWidth: 2 * Theme.scale(Screen)
    property int duration: 1000
    
    implicitWidth: size
    implicitHeight: size
    
    Canvas {
        id: spinnerCanvas
        anchors.fill: parent
        
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            
            var centerX = width / 2
            var centerY = height / 2
            var radius = Math.min(width, height) / 2 - strokeWidth / 2
            
            ctx.strokeStyle = root.color
            ctx.lineWidth = root.strokeWidth
            ctx.lineCap = "round"
            
            // Draw arc with gap (270 degrees with 90 degree gap)
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, -Math.PI/2 + rotationAngle, -Math.PI/2 + rotationAngle + Math.PI * 1.5)
            ctx.stroke()
        }
        
        property real rotationAngle: 0
        
        onRotationAngleChanged: {
            requestPaint()
        }
        
        NumberAnimation {
            target: spinnerCanvas
            property: "rotationAngle"
            running: root.running
            from: 0
            to: 2 * Math.PI
            duration: root.duration
            loops: Animation.Infinite
        }
    }
} 