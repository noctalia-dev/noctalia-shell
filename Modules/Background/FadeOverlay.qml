import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Power

/**
* IdleFadeOverlay — full-screen fade-to-black shown before each idle action.
*
* A single Loader wraps a Variants so per-screen windows only exist while
* a fade is in progress, keeping VRAM usage at zero at rest.
*
* Any mouse movement cancels the fade and unloads the windows immediately.
*/
Item {
  id: root

  Loader {
    active: IdleService.fadePending !== ""
    asynchronous: false

    sourceComponent: Variants {
      model: Quickshell.screens
      delegate: PanelWindow {
        id: overlay
        required property ShellScreen modelData
        screen: modelData

        color: Qt.rgba(0, 0, 0, 0)

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "noctalia-fade-overlay"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        ColorAnimation on color {
          running: true
          from: Qt.rgba(0, 0, 0, 0)
          to: Qt.rgba(0, 0, 0, 1)
          duration: IdleService.fadeDuration * 1000
          easing.type: Easing.InQuad
        }
      }
    }
  }
}
