import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons

/**
* ScreenCornerWindow - Small PanelWindow that renders a single concave screen corner.
*/
PanelWindow {
  id: root

  required property string corner // "topLeft", "topRight", "bottomLeft", "bottomRight"

  readonly property real s: Style.screenRadius
  readonly property bool shouldShow: Settings.data.general.showScreenCorners && s > 0

  visible: shouldShow
  color: "transparent"

  // Click-through
  mask: Region {}

  WlrLayershell.namespace: "noctalia-corner-" + corner + "-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: corner === "topLeft" || corner === "topRight"
    bottom: corner === "bottomLeft" || corner === "bottomRight"
    left: corner === "topLeft" || corner === "bottomLeft"
    right: corner === "topRight" || corner === "bottomRight"
  }

  implicitWidth: Math.ceil(s)
  implicitHeight: Math.ceil(s)

  // Cache to texture to avoid continuous re-tessellation
  Item {
    anchors.fill: parent
    layer.enabled: true

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: true
      enabled: false
      visible: root.s > 0 && width > 0 && height > 0

      ShapePath {
        id: cornerPath

        readonly property color cornerColor: Settings.data.general.forceBlackScreenCorners ? "black" : Color.mSurface

        strokeWidth: -1
        fillColor: root.shouldShow ? cornerColor : "transparent"

        Behavior on fillColor {
          enabled: !Color.isTransitioning
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        PathSvg {
          path: {
            var s = root.s;
            if (s <= 0)
              return "M -1 -1 L -1 0 L 0 0 Z";
            switch (root.corner) {
            case "topLeft":
              return "M 0 0 L " + s + " 0 A " + s + " " + s + " 0 0 0 0 " + s + " Z";
            case "topRight":
              return "M 0 0 L " + s + " 0 L " + s + " " + s + " A " + s + " " + s + " 0 0 0 0 0 Z";
            case "bottomLeft":
              return "M 0 0 A " + s + " " + s + " 0 0 0 " + s + " " + s + " L 0 " + s + " Z";
            case "bottomRight":
              return "M " + s + " " + s + " L 0 " + s + " A " + s + " " + s + " 0 0 0 " + s + " 0 Z";
            default:
              return "M -1 -1 L -1 0 L 0 0 Z";
            }
          }
        }
      }
    }
  }
}
