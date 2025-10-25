import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

Loader {
  active: Settings.data.general.showScreenCorners

  sourceComponent: Variants {
    model: Quickshell.screens

    PanelWindow {
      id: root

      required property ShellScreen modelData
      screen: modelData

      property color cornerColor: Settings.data.general.forceBlackScreenCorners ? Qt.rgba(0, 0, 0, 1) : Qt.alpha(Color.mSurface, Settings.data.bar.backgroundOpacity)
      property color hugCornerColor: Qt.alpha(Color.mSurface, Settings.data.bar.backgroundOpacity)
      property real cornerRadius: Style.screenRadius
      property real cornerSize: Style.screenRadius

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
        // Pin corners to four screen edges
        top: 0
        bottom: 0
        left: 0
        right: 0
      }

      mask: Region {}

      // Margins for hugCorner items to follow bar position when present on this screen
      readonly property bool __barOnThisScreen: (modelData && Settings.data.bar.monitors.includes(modelData.name)) || (Settings.data.bar.monitors.length === 0)
      readonly property bool __barActive: BarService.isVisible && __barOnThisScreen && Settings.data.bar.backgroundOpacity > 0
      readonly property int __hugTopMargin: (!Settings.data.bar.floating && __barActive && Settings.data.bar.position === "top") ? Style.barHeight : 0
      readonly property int __hugBottomMargin: (!Settings.data.bar.floating && __barActive && Settings.data.bar.position === "bottom") ? Style.barHeight : 0
      readonly property int __hugLeftMargin: (!Settings.data.bar.floating && __barActive && Settings.data.bar.position === "left") ? Style.barHeight : 0
      readonly property int __hugRightMargin: (!Settings.data.bar.floating && __barActive && Settings.data.bar.position === "right") ? Style.barHeight : 0

      // Top-left hug concave corner
      Canvas {
        id: topLeftHugCorner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.__hugTopMargin
        anchors.leftMargin: root.__hugLeftMargin
        anchors.rightMargin: root.__hugRightMargin
        anchors.bottomMargin: root.__hugBottomMargin
        width: cornerSize
        height: cornerSize
        visible: root.__barActive && (Settings.data.bar.position === "top" || Settings.data.bar.position === "left")
        antialiasing: true
        renderTarget: Canvas.FramebufferObject
        smooth: false

        onPaint: {
          const ctx = getContext("2d")
          if (!ctx)
            return

          ctx.reset()
          ctx.clearRect(0, 0, width, height)

          // Fill the entire area with the corner color
          ctx.fillStyle = hugCornerColor
          ctx.fillRect(0, 0, width, height)

          // Cut out the rounded corner using destination-out
          ctx.globalCompositeOperation = "destination-out"
          ctx.fillStyle = "#ffffff"
          ctx.beginPath()
          ctx.arc(width, height, root.cornerRadius, 0, 2 * Math.PI)
          ctx.fill()
        }

        onWidthChanged: if (available)
                          requestPaint()
        onHeightChanged: if (available)
                           requestPaint()

        Connections {
          target: root
          function onCornerColorChanged() {
            if (topLeftHugCorner.available)
              topLeftHugCorner.requestPaint()
          }
          function onCornerRadiusChanged() {
            if (topLeftHugCorner.available)
              topLeftHugCorner.requestPaint()
          }
        }
      }

      // Top-right hug concave corner
      Canvas {
        id: topRightHugCorner
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root.__hugTopMargin
        anchors.leftMargin: root.__hugLeftMargin
        anchors.rightMargin: root.__hugRightMargin
        anchors.bottomMargin: root.__hugBottomMargin
        width: cornerSize
        height: cornerSize
        visible: root.__barActive && (Settings.data.bar.position === "top" || Settings.data.bar.position === "right")
        antialiasing: true
        renderTarget: Canvas.FramebufferObject
        smooth: true

        onPaint: {
          const ctx = getContext("2d")
          if (!ctx)
            return

          ctx.reset()
          ctx.clearRect(0, 0, width, height)

          ctx.fillStyle = hugCornerColor
          ctx.fillRect(0, 0, width, height)

          ctx.globalCompositeOperation = "destination-out"
          ctx.fillStyle = "#ffffff"
          ctx.beginPath()
          ctx.arc(0, height, root.cornerRadius, 0, 2 * Math.PI)
          ctx.fill()
        }

        onWidthChanged: if (available)
                          requestPaint()
        onHeightChanged: if (available)
                           requestPaint()

        Connections {
          target: root
          function onCornerColorChanged() {
            if (topRightHugCorner.available)
              topRightHugCorner.requestPaint()
          }
          function onCornerRadiusChanged() {
            if (topRightHugCorner.available)
              topRightHugCorner.requestPaint()
          }
        }
      }

      // Bottom-left hug concave corner
      Canvas {
        id: bottomLeftHugCorner
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.topMargin: root.__hugTopMargin
        anchors.leftMargin: root.__hugLeftMargin
        anchors.rightMargin: root.__hugRightMargin
        anchors.bottomMargin: root.__hugBottomMargin
        width: cornerSize
        height: cornerSize
        visible: root.__barActive && (Settings.data.bar.position === "bottom" || Settings.data.bar.position === "left")
        antialiasing: true
        renderTarget: Canvas.FramebufferObject
        smooth: true

        onPaint: {
          const ctx = getContext("2d")
          if (!ctx)
            return

          ctx.reset()
          ctx.clearRect(0, 0, width, height)

          ctx.fillStyle = hugCornerColor
          ctx.fillRect(0, 0, width, height)

          ctx.globalCompositeOperation = "destination-out"
          ctx.fillStyle = "#ffffff"
          ctx.beginPath()
          ctx.arc(width, 0, root.cornerRadius, 0, 2 * Math.PI)
          ctx.fill()
        }

        onWidthChanged: if (available)
                          requestPaint()
        onHeightChanged: if (available)
                           requestPaint()

        Connections {
          target: root
          function onCornerColorChanged() {
            if (bottomLeftHugCorner.available)
              bottomLeftHugCorner.requestPaint()
          }
          function onCornerRadiusChanged() {
            if (bottomLeftHugCorner.available)
              bottomLeftHugCorner.requestPaint()
          }
        }
      }

      // Bottom-right hug concave corner
      Canvas {
        id: bottomRightHugCorner
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.topMargin: root.__hugTopMargin
        anchors.leftMargin: root.__hugLeftMargin
        anchors.rightMargin: root.__hugRightMargin
        anchors.bottomMargin: root.__hugBottomMargin
        width: cornerSize
        height: cornerSize
        visible: root.__barActive && (Settings.data.bar.position === "bottom" || Settings.data.bar.position === "right")
        antialiasing: true
        renderTarget: Canvas.FramebufferObject
        smooth: true

        onPaint: {
          const ctx = getContext("2d")
          if (!ctx)
            return

          ctx.reset()
          ctx.clearRect(0, 0, width, height)

          ctx.fillStyle = hugCornerColor
          ctx.fillRect(0, 0, width, height)

          ctx.globalCompositeOperation = "destination-out"
          ctx.fillStyle = "#ffffff"
          ctx.beginPath()
          ctx.arc(0, 0, root.cornerRadius, 0, 2 * Math.PI)
          ctx.fill()
        }

        onWidthChanged: if (available)
                          requestPaint()
        onHeightChanged: if (available)
                           requestPaint()

        Connections {
          target: root
          function onCornerColorChanged() {
            if (bottomRightHugCorner.available)
              bottomRightHugCorner.requestPaint()
          }
          function onCornerRadiusChanged() {
            if (bottomRightHugCorner.available)
              bottomRightHugCorner.requestPaint()
          }
        }
      }

      // Top-left concave corner
      Canvas {
        id: topLeftCorner
        anchors.top: parent.top
        anchors.left: parent.left
        width: cornerSize
        height: cornerSize
        antialiasing: true
        renderTarget: Canvas.FramebufferObject
        smooth: false

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
          ctx.arc(width, height, root.cornerRadius, 0, 2 * Math.PI)
          ctx.fill()
        }

        onWidthChanged: if (available)
                          requestPaint()
        onHeightChanged: if (available)
                           requestPaint()

        Connections {
          target: root
          function onCornerColorChanged() {
            if (topLeftCorner.available)
              topLeftCorner.requestPaint()
          }
          function onCornerRadiusChanged() {
            if (topLeftCorner.available)
              topLeftCorner.requestPaint()
          }
        }
      }

      // Top-right concave corner
      Canvas {
        id: topRightCorner
        anchors.top: parent.top
        anchors.right: parent.right
        width: cornerSize
        height: cornerSize
        antialiasing: true
        renderTarget: Canvas.FramebufferObject
        smooth: true

        onPaint: {
          const ctx = getContext("2d")
          if (!ctx)
            return

          ctx.reset()
          ctx.clearRect(0, 0, width, height)

          ctx.fillStyle = root.cornerColor
          ctx.fillRect(0, 0, width, height)

          ctx.globalCompositeOperation = "destination-out"
          ctx.fillStyle = "#ffffff"
          ctx.beginPath()
          ctx.arc(0, height, root.cornerRadius, 0, 2 * Math.PI)
          ctx.fill()
        }

        onWidthChanged: if (available)
                          requestPaint()
        onHeightChanged: if (available)
                           requestPaint()

        Connections {
          target: root
          function onCornerColorChanged() {
            if (topRightCorner.available)
              topRightCorner.requestPaint()
          }
          function onCornerRadiusChanged() {
            if (topRightCorner.available)
              topRightCorner.requestPaint()
          }
        }
      }

      // Bottom-left concave corner
      Canvas {
        id: bottomLeftCorner
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: cornerSize
        height: cornerSize
        antialiasing: true
        renderTarget: Canvas.FramebufferObject
        smooth: true

        onPaint: {
          const ctx = getContext("2d")
          if (!ctx)
            return

          ctx.reset()
          ctx.clearRect(0, 0, width, height)

          ctx.fillStyle = root.cornerColor
          ctx.fillRect(0, 0, width, height)

          ctx.globalCompositeOperation = "destination-out"
          ctx.fillStyle = "#ffffff"
          ctx.beginPath()
          ctx.arc(width, 0, root.cornerRadius, 0, 2 * Math.PI)
          ctx.fill()
        }

        onWidthChanged: if (available)
                          requestPaint()
        onHeightChanged: if (available)
                           requestPaint()

        Connections {
          target: root
          function onCornerColorChanged() {
            if (bottomLeftCorner.available)
              bottomLeftCorner.requestPaint()
          }
          function onCornerRadiusChanged() {
            if (bottomLeftCorner.available)
              bottomLeftCorner.requestPaint()
          }
        }
      }

      // Bottom-right concave corner
      Canvas {
        id: bottomRightCorner
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: cornerSize
        height: cornerSize
        antialiasing: true
        renderTarget: Canvas.FramebufferObject
        smooth: true

        onPaint: {
          const ctx = getContext("2d")
          if (!ctx)
            return

          ctx.reset()
          ctx.clearRect(0, 0, width, height)

          ctx.fillStyle = root.cornerColor
          ctx.fillRect(0, 0, width, height)

          ctx.globalCompositeOperation = "destination-out"
          ctx.fillStyle = "#ffffff"
          ctx.beginPath()
          ctx.arc(0, 0, root.cornerRadius, 0, 2 * Math.PI)
          ctx.fill()
        }

        onWidthChanged: if (available)
                          requestPaint()
        onHeightChanged: if (available)
                           requestPaint()

        Connections {
          target: root
          function onCornerColorChanged() {
            if (bottomRightCorner.available)
              bottomRightCorner.requestPaint()
          }
          function onCornerRadiusChanged() {
            if (bottomRightCorner.available)
              bottomRightCorner.requestPaint()
          }
        }
      }
    }
  }
}
