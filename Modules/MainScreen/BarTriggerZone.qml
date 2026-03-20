import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI

/**
* BarTriggerZone - Thin invisible window at screen edge to reveal hidden bar
*
* This window is only active when the bar is in auto-hide mode and hidden.
* When the mouse enters this zone, it triggers the bar to show.
*/
PanelWindow {
  id: root

  readonly property string barPosition: Settings.getBarPositionForScreen(screen?.name)
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property int triggerSize: 1

  // Track if component is being destroyed to prevent signals during cleanup
  property bool isBeingDestroyed: false
  Component.onDestruction: isBeingDestroyed = true

  // Invisible trigger zone
  color: "transparent"
  focusable: false

  WlrLayershell.namespace: "noctalia-bar-trigger-" + (screen?.name || "unknown")
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  // Anchor to bar's edge
  anchors {
    top: barPosition === "top" || barIsVertical
    bottom: barPosition === "bottom" || barIsVertical
    left: barPosition === "left" || !barIsVertical
    right: barPosition === "right" || !barIsVertical
  }

  // Size based on orientation - thin strip at edge
  implicitWidth: barIsVertical ? triggerSize : 0
  implicitHeight: !barIsVertical ? triggerSize : 0

  MouseArea {
    id: triggerArea
    anchors.fill: parent
    hoverEnabled: true

    onEntered: {
      if (root.isBeingDestroyed)
        return;
      // Signal hover - BarContentWindow will handle the show delay
      BarService.setScreenHovered(root.screen?.name, true);
    }

    onExited: {
      if (root.isBeingDestroyed)
        return;
      BarService.setScreenHovered(root.screen?.name, false);
    }
  }

  Component.onCompleted: {
    Logger.d("BarTriggerZone", "Created for screen:", screen?.name);
  }
}
