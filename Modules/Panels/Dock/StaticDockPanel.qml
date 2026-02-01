import QtQuick

import qs.Commons
import qs.Modules.MainScreen

SmartPanel {
  id: root

  property real dockWidth: 0
  property real dockHeight: 0

  readonly property string dockPosition: Settings.data.dock.position
  readonly property bool isVertical: dockPosition === "left" || dockPosition === "right"

  panelAnchorTop: dockPosition === "top"
  panelAnchorBottom: dockPosition === "bottom"
  panelAnchorLeft: dockPosition === "left"
  panelAnchorRight: dockPosition === "right"
  panelAnchorHorizontalCenter: !isVertical
  panelAnchorVerticalCenter: isVertical

  forceAttachToBar: true
  exclusiveKeyboard: false

  preferredWidth: Math.max(1, dockWidth)
  preferredHeight: Math.max(1, dockHeight)

  panelContent: Item {
    id: panelContent

    property bool allowAttach: true
    property real contentPreferredWidth: Math.max(1, root.dockWidth)
    property real contentPreferredHeight: Math.max(1, root.dockHeight)
  }
}
