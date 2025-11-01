import QtQuick
import qs.Commons

Item {
  id: root

  // Corner radius properties
  property real topLeftRadius: 0
  property real topRightRadius: 0
  property real bottomLeftRadius: 0
  property real bottomRightRadius: 0

  // Inverted corner properties (concave instead of convex)
  property bool topLeftInverted: false
  property bool topRightInverted: false
  property bool bottomLeftInverted: false
  property bool bottomRightInverted: false

  // Direction for inverted corners: "horizontal" or "vertical"
  // horizontal: curves left/right (extends beyond left/right edges)
  // vertical: curves up/down (extends beyond top/bottom edges)
  property string topLeftInvertedDirection: "horizontal" // default: curves left
  property string topRightInvertedDirection: "horizontal" // default: curves right
  property string bottomLeftInvertedDirection: "horizontal" // default: curves left
  property string bottomRightInvertedDirection: "horizontal" // default: curves right

  // Background color
  property color backgroundColor: "white"

  // Check if any corner is inverted
  readonly property bool hasInvertedCorners: topLeftInverted || topRightInverted || bottomLeftInverted || bottomRightInverted

  // Calculate padding needed for inverted corners based on their direction
  readonly property real topPadding: Math.max((topLeftInverted && topLeftInvertedDirection === "vertical") ? topLeftRadius : 0, (topRightInverted && topRightInvertedDirection === "vertical") ? topRightRadius : 0)
  readonly property real bottomPadding: Math.max((bottomLeftInverted && bottomLeftInvertedDirection === "vertical") ? bottomLeftRadius : 0, (bottomRightInverted && bottomRightInvertedDirection === "vertical") ? bottomRightRadius : 0)
  readonly property real leftPadding: Math.max((topLeftInverted && topLeftInvertedDirection === "horizontal") ? topLeftRadius : 0, (bottomLeftInverted && bottomLeftInvertedDirection === "horizontal") ? bottomLeftRadius : 0)
  readonly property real rightPadding: Math.max((topRightInverted && topRightInvertedDirection === "horizontal") ? topRightRadius : 0, (bottomRightInverted && bottomRightInvertedDirection === "horizontal") ? bottomRightRadius : 0)

  // Simple rectangle for non-inverted corners (better performance)
  Rectangle {
    id: simpleBackground
    anchors.fill: parent
    color: root.backgroundColor
    radius: topLeftRadius // Use topLeftRadius as default
    border.width: Style.borderS
    border.color: Color.mOutline
    visible: !root.hasInvertedCorners

    topLeftRadius: root.topLeftRadius
    topRightRadius: root.topRightRadius
    bottomLeftRadius: root.bottomLeftRadius
    bottomRightRadius: root.bottomRightRadius
  }

  // Background with custom corners (for inverted corners)
  Canvas {
    id: background
    anchors.fill: parent
    anchors.topMargin: -root.topPadding
    anchors.bottomMargin: -root.bottomPadding
    anchors.leftMargin: -root.leftPadding
    anchors.rightMargin: -root.rightPadding
    visible: root.hasInvertedCorners

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()

      // Adjust coordinates to account for inverted corner padding
      var x = root.leftPadding
      var y = root.topPadding
      var w = width - root.leftPadding - root.rightPadding
      var h = height - root.topPadding - root.bottomPadding

      ctx.fillStyle = root.backgroundColor
      ctx.beginPath()

      // Start from top left
      if (topLeftInverted) {
        if (topLeftInvertedDirection === "vertical") {
          ctx.moveTo(x, y)
        } else {
          ctx.moveTo(x + topLeftRadius, y)
        }
      } else {
        ctx.moveTo(x + topLeftRadius, y)
      }

      // Top edge and top right corner
      if (topRightInverted) {
        if (topRightInvertedDirection === "horizontal") {
          // Curves to the right
          ctx.lineTo(x + w, y)
          ctx.lineTo(x + w + topRightRadius, y)
          ctx.quadraticCurveTo(x + w, y, x + w, y + topRightRadius)
        } else {
          // Curves upward
          ctx.lineTo(x + w, y)
          ctx.lineTo(x + w, y - topRightRadius)
          ctx.quadraticCurveTo(x + w, y, x + w - topRightRadius, y)
          ctx.lineTo(x + w, y)
          ctx.lineTo(x + w, y + topRightRadius)
        }
      } else {
        ctx.lineTo(x + w - topRightRadius, y)
        ctx.arcTo(x + w, y, x + w, y + topRightRadius, topRightRadius)
      }

      // Right edge and bottom right corner
      if (bottomRightInverted) {
        if (bottomRightInvertedDirection === "horizontal") {
          // Curves to the right
          ctx.lineTo(x + w, y + h - bottomRightRadius)
          ctx.quadraticCurveTo(x + w, y + h, x + w + bottomRightRadius, y + h)
          ctx.lineTo(x + w, y + h)
          ctx.lineTo(x + w - bottomRightRadius, y + h)
        } else {
          // Curves downward
          ctx.lineTo(x + w, y + h)
          ctx.lineTo(x + w, y + h + bottomRightRadius)
          ctx.quadraticCurveTo(x + w, y + h, x + w - bottomRightRadius, y + h)
        }
      } else {
        ctx.lineTo(x + w, y + h - bottomRightRadius)
        ctx.arcTo(x + w, y + h, x + w - bottomRightRadius, y + h, bottomRightRadius)
      }

      // Bottom edge and bottom left corner
      if (bottomLeftInverted) {
        if (bottomLeftInvertedDirection === "horizontal") {
          // Curves to the left
          ctx.lineTo(x + bottomLeftRadius, y + h)
          ctx.lineTo(x - bottomLeftRadius, y + h)
          ctx.quadraticCurveTo(x, y + h, x, y + h - bottomLeftRadius)
        } else {
          // Curves downward
          ctx.lineTo(x, y + h)
          ctx.lineTo(x, y + h + bottomLeftRadius)
          ctx.quadraticCurveTo(x, y + h, x + bottomLeftRadius, y + h)
          ctx.lineTo(x, y + h)
          ctx.lineTo(x, y + h - bottomLeftRadius)
        }
      } else {
        ctx.lineTo(x + bottomLeftRadius, y + h)
        ctx.arcTo(x, y + h, x, y + h - bottomLeftRadius, bottomLeftRadius)
      }

      // Left edge and back to top left corner
      if (topLeftInverted) {
        if (topLeftInvertedDirection === "horizontal") {
          // Curves to the left
          ctx.lineTo(x, y + topLeftRadius)
          ctx.quadraticCurveTo(x, y, x - topLeftRadius, y)
          ctx.lineTo(x, y)
          ctx.lineTo(x + topLeftRadius, y)
        } else {
          // Curves upward
          ctx.lineTo(x, y + topLeftRadius)
          ctx.lineTo(x, y)
          ctx.lineTo(x, y - topLeftRadius)
          ctx.quadraticCurveTo(x, y, x + topLeftRadius, y)
        }
      } else {
        ctx.lineTo(x, y + topLeftRadius)
        ctx.arcTo(x, y, x + topLeftRadius, y, topLeftRadius)
      }

      ctx.closePath()
      ctx.fill()
    }
  }

  // Trigger repaint when properties change
  onTopLeftRadiusChanged: background.requestPaint()
  onTopRightRadiusChanged: background.requestPaint()
  onBottomLeftRadiusChanged: background.requestPaint()
  onBottomRightRadiusChanged: background.requestPaint()
  onTopLeftInvertedChanged: background.requestPaint()
  onTopRightInvertedChanged: background.requestPaint()
  onBottomLeftInvertedChanged: background.requestPaint()
  onBottomRightInvertedChanged: background.requestPaint()
  onTopLeftInvertedDirectionChanged: background.requestPaint()
  onTopRightInvertedDirectionChanged: background.requestPaint()
  onBottomLeftInvertedDirectionChanged: background.requestPaint()
  onBottomRightInvertedDirectionChanged: background.requestPaint()
  onBackgroundColorChanged: background.requestPaint()
  onWidthChanged: background.requestPaint()
  onHeightChanged: background.requestPaint()
}
