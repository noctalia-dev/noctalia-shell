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
  property bool isDockHovered: false

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

  panelContent: Item {
    id: panelContent

    property bool allowAttach: true
    property real contentPreferredWidth: 300
    property real contentPreferredHeight: 50 - Settings.data.bar.frameThickness

    // Detect mouse exit to close panel
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: {
        root.isDockHovered = true;
      }
      onExited: {
        root.isDockHovered = false;
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
