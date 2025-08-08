import QtQuick
import qs.Settings

Rectangle {
    id: circularProgressBar
    color: "transparent"
    
    property real progress: 0.0
    property int size: 80
    property color backgroundColor: Theme.surfaceVariant
    property color progressColor: Theme.accentPrimary
    property int strokeWidth: 6 * Theme.scale(Screen)
    property bool showText: true
    property string units: "%"
    property string text: Math.round(progress * 100) + units
    property int textSize: 10 * Theme.scale(Screen)
    property color textColor: Theme.textPrimary
    
    // Notch properties
    property bool hasNotch: false
    property real notchSize: 0.25
    property string notchIcon: ""
    property int notchIconSize: 12
    property color notchIconColor: Theme.accentPrimary
    
    width: size
    height: size
    
    Canvas {
        id: canvas
        anchors.fill: parent
        
        onPaint: {
            // Setup canvas context and calculate dimensions
            var ctx = getContext("2d")
            var centerX = width / 2
            var centerY = height / 2
            var radius = Math.min(width, height) / 2 - strokeWidth / 2
            var startAngle = -Math.PI / 2 // Start from top
            var notchAngle = notchSize * 2 * Math.PI
            var notchStartAngle = -notchAngle / 2
            var notchEndAngle = notchAngle / 2
            
            ctx.reset()
            ctx.strokeStyle = backgroundColor
            ctx.lineWidth = strokeWidth
            ctx.lineCap = "round"
            ctx.beginPath()
            
            if (hasNotch) {
                // Draw background arc with notch gap
                ctx.arc(centerX, centerY, radius, notchEndAngle, 2 * Math.PI + notchStartAngle)
            } else {
                // Draw full background circle
                ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI)
            }
            ctx.stroke()
            
            // Draw progress arc
            if (progress > 0) {
                ctx.strokeStyle = progressColor
                ctx.lineWidth = strokeWidth
                ctx.lineCap = "round"
                ctx.beginPath()
                
                if (hasNotch) {
                    // Calculate progress arc with notch gap
                    var availableAngle = 2 * Math.PI - notchAngle
                    var progressAngle = availableAngle * progress
                    var adjustedStartAngle = notchEndAngle
                    var adjustedEndAngle = adjustedStartAngle + progressAngle
                    if (adjustedEndAngle > 2 * Math.PI + notchStartAngle) {
                        adjustedEndAngle = 2 * Math.PI + notchStartAngle
                    }
                    
                    if (adjustedEndAngle > adjustedStartAngle) {
                        ctx.arc(centerX, centerY, radius, adjustedStartAngle, adjustedEndAngle)
                    }
                } else {
                    // Draw full progress arc
                    ctx.arc(centerX, centerY, radius, startAngle, startAngle + (2 * Math.PI * progress))
                }
                ctx.stroke()
            }
        }
    }
    
    // Center text - always show the percentage
    Text {
        id: centerText
        anchors.centerIn: parent
        text: circularProgressBar.text
        font.pixelSize: textSize
        font.family: Theme.fontFamily
        font.bold: true
        color: textColor
        visible: showText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    
    // Notch icon - positioned further to the right
    Text {
        id: notchIconText
        anchors.right: parent.right
        anchors.rightMargin: -4
        anchors.verticalCenter: parent.verticalCenter
        text: notchIcon
        font.family: "Material Symbols Outlined"
        font.pixelSize: notchIconSize
        color: notchIconColor
        visible: hasNotch && notchIcon !== ""
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    
    // Animate progress changes
    Behavior on progress {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }
    
    // Redraw canvas when properties change
    onProgressChanged: canvas.requestPaint()
    onSizeChanged: canvas.requestPaint()
    onBackgroundColorChanged: canvas.requestPaint()
    onProgressColorChanged: canvas.requestPaint()
    onStrokeWidthChanged: canvas.requestPaint()
    onHasNotchChanged: canvas.requestPaint()
    onNotchSizeChanged: canvas.requestPaint()
} 