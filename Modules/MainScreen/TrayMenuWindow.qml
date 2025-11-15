import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI
import qs.Modules.Bar.Extras

// Separate window for TrayMenu context menus
// This is a top-level PanelWindow (sibling to MainScreen, not nested inside it)
PanelWindow {
  id: root

  required property ShellScreen screen

  anchors.top: true
  anchors.left: true
  anchors.right: true
  anchors.bottom: true
  visible: false
  color: Color.transparent

  // Use Top layer (same as MainScreen) for proper event handling
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "noctalia-traymenu-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  // Expose the trayMenu Loader directly
  readonly property alias trayMenuLoader: trayMenu

  // Register with PanelService so panels can find this window
  Component.onCompleted: {
    objectName = "trayMenuWindow-" + (screen?.name || "unknown")
    PanelService.registerTrayMenuWindow(screen, root)
  }

  function open() {
    visible = true
  }

  function close() {
    visible = false
    if (trayMenu.item) {
      trayMenu.item.hideMenu()
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: root.close()
  }

  Loader {
    id: trayMenu
    source: Quickshell.shellDir + "/Modules/Bar/Extras/TrayMenu.qml"
    onLoaded: {
      if (item) {
        item.screen = root.screen
      }
    }
  }
}
