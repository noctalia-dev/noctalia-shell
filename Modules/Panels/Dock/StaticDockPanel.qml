import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen

SmartPanel {
  id: root

  property real dockWidth: 0
  property real dockHeight: 0

  readonly property string dockPosition: Settings.data.dock.position
  readonly property bool isVertical: dockPosition === "left" || dockPosition === "right"
  readonly property bool isStaticMode: Settings.data.dock.dockType === "static"

  panelAnchorTop: dockPosition === "top"
  panelAnchorBottom: dockPosition === "bottom"
  panelAnchorLeft: dockPosition === "left"
  panelAnchorRight: dockPosition === "right"
  panelAnchorHorizontalCenter: !isVertical
  panelAnchorVerticalCenter: isVertical

  forceAttachToBar: true
  exclusiveKeyboard: false

  // Fixed size 200x200
  preferredWidth: 200
  preferredHeight: 200

  // Peek Window to detect hover when panel is closed
  Loader {
    active: root.isStaticMode && !root.isPanelOpen && !root.isClosing && root.screen
    sourceComponent: PanelWindow {
      id: peekWindow
      screen: root.screen
      color: "transparent"
      focusable: false

      // Layer config
      WlrLayershell.namespace: "noctalia-static-dock-peek-" + (screen?.name || "unknown")
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.exclusionMode: ExclusionMode.Ignore

      // implicitHeight: barAtSameEdge && !isVertical ? 3 : peekHeight
      // implicitWidth: barAtSameEdge && isVertical ? 3 : peekHeight

      // Anchors
      anchors.top: root.dockPosition === "top" || root.isVertical
      anchors.bottom: root.dockPosition === "bottom" || root.isVertical
      anchors.left: root.dockPosition === "left" || !root.isVertical
      anchors.right: root.dockPosition === "right" || !root.isVertical

      // Size - 2px thick strip
      implicitWidth: root.isVertical ? 2 : (root.screen ? Math.round(root.screen.width) : 0)
      implicitHeight: !root.isVertical ? 2 : (root.screen ? Math.round(root.screen.height) : 0)

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: {
          root.open(null, null);
        }
      }
    }
  }

  panelContent: Item {
    id: panelContent

    property bool allowAttach: true
    property real contentPreferredWidth: 300
    property real contentPreferredHeight: 50 - Settings.data.bar.frameThickness

    // Detect mouse exit to close panel
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onExited: {
        root.close();
      }
    }

    Rectangle {
      anchors.centerIn: parent.centerIn
      color: "darkred"
      radius: 24
      width: 300
      height: 50

      Text {
        anchors.centerIn: parent
        text: "Static Dock"
        color: Settings.data.colorSchemes.darkMode ? "#cdd6f4" : "#4c4f69"
      }
    }
  }
}
