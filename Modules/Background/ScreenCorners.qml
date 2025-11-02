import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

Loader {
  active: Settings.data.general.showScreenCorners && (!Settings.data.ui.panelsAttachedToBar || Settings.data.bar.backgroundOpacity >= 1 || Settings.data.bar.floating)

  sourceComponent: Variants {
    model: Quickshell.screens

    PanelWindow {
      id: root

      required property ShellScreen modelData
      screen: modelData

      property color cornerColor: Settings.data.general.forceBlackScreenCorners ? Qt.rgba(0, 0, 0, 1) : Qt.alpha(Color.mSurface, Settings.data.bar.backgroundOpacity)
      property real cornerRadius: Style.screenRadius
      property real cornerSize: Style.screenRadius

      // Helper properties for margin calculations
      readonly property bool barOnThisMonitor: BarService.isVisible && ((modelData && Settings.data.bar.monitors.includes(modelData.name)) || (Settings.data.bar.monitors.length === 0)) && Settings.data.bar.backgroundOpacity > 0
      readonly property real barMargin: !Settings.data.bar.floating && barOnThisMonitor ? Style.barHeight : 0

      color: Color.transparent

      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "quickshell-corner"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      margins {
        // When bar is floating, corners should be at screen edges (no margins)
        // When bar is not floating, respect bar margins as before
        top: Settings.data.bar.position === "top" ? barMargin : 0
        bottom: Settings.data.bar.position === "bottom" ? barMargin : 0
        left: Settings.data.bar.position === "left" ? barMargin : 0
        right: Settings.data.bar.position === "right" ? barMargin : 0
      }

      mask: Region {}

      // Reusable corner canvas component
      component CornerCanvas: Canvas {
        id: corner

        required property real arcCenterX
        required property real arcCenterY

        width: root.cornerSize
        height: root.cornerSize
        antialiasing: true
        renderTarget: Canvas.FramebufferObject
        smooth: true

        onPaint: {
          const ctx = getContext("2d")
          if (!ctx)
            return

          ctx.reset()
          ctx.clearRect(0, 0, width, height)

          // Fill the entire area with the corner color
          ctx.fillStyle = root.cornerColor
          ctx.fillRect(0, 0, width, height)

          // Cut out the rounded corner using destination-out
          ctx.globalCompositeOperation = "destination-out"
          ctx.fillStyle = "#ffffff"
          ctx.beginPath()
          ctx.arc(arcCenterX, arcCenterY, root.cornerRadius, 0, 2 * Math.PI)
          ctx.fill()
        }

        onWidthChanged: if (available)
                          requestPaint()
        onHeightChanged: if (available)
                           requestPaint()
      }

      // Consolidated repaint handler for all corners
      property var corners: [topLeftCorner, topRightCorner, bottomLeftCorner, bottomRightCorner]

      onCornerColorChanged: {
        corners.forEach(corner => {
                          if (corner.available)
                          corner.requestPaint()
                        })
      }

      onCornerRadiusChanged: {
        corners.forEach(corner => {
                          if (corner.available)
                          corner.requestPaint()
                        })
      }

      // Top-left concave corner
      CornerCanvas {
        id: topLeftCorner
        anchors.top: parent.top
        anchors.left: parent.left
        arcCenterX: width
        arcCenterY: height
      }

      // Top-right concave corner
      CornerCanvas {
        id: topRightCorner
        anchors.top: parent.top
        anchors.right: parent.right
        arcCenterX: 0
        arcCenterY: height
      }

      // Bottom-left concave corner
      CornerCanvas {
        id: bottomLeftCorner
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        arcCenterX: width
        arcCenterY: 0
      }

      // Bottom-right concave corner
      CornerCanvas {
        id: bottomRightCorner
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        arcCenterX: 0
        arcCenterY: 0
      }
    }
  }
}
