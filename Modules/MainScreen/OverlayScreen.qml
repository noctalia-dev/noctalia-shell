import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Panels.Launcher
import qs.Services.Compositor
import qs.Services.UI

PanelWindow {
  id: root

  color: "transparent"

  Component.onCompleted: {
    Logger.d("OverlayPanelsWindow", "Overlay panels window created for screen:", screen?.name);
  }

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "noctalia-overlay-panels-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore
  WlrLayershell.keyboardFocus: {
    if (!isOverlayPanelOpen) return WlrKeyboardFocus.None
    if (CompositorService.isHyprland) {
      return PanelService.isInitializingKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    }
    return PanelService.openedPanel.exclusiveKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
  }

  anchors { top: true; bottom: true; left: true; right: true }

  readonly property bool isOverlayPanelOpen: {
    if (!PanelService.openedPanel) return false
    var name = PanelService.openedPanel.objectName || ""
    return name.startsWith("launcherPanel-")
  }

  Loader {
    id: maskLoader
    active: !root.isOverlayPanelOpen
    sourceComponent: Region {}
  }

  mask: maskLoader.item

  MouseArea {
    anchors.fill: parent
    enabled: root.isOverlayPanelOpen
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: {
      if (PanelService.openedPanel) {
        PanelService.openedPanel.close()
      }
    }
    z: 0
  }

  Launcher {
    id: launcherPanel
    objectName: "launcherPanel-" + (screen?.name || "unknown")
    screen: root.screen
  }

  Shortcut {
    sequence: "Escape"
    enabled: root.isOverlayPanelOpen
    onActivated: {
      if (PanelService.openedPanel) {
        PanelService.openedPanel.close()
      }
    }
  }
}
