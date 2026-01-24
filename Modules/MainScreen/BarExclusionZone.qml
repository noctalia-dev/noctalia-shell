import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor

/**
* BarExclusionZone - Invisible PanelWindow that reserves exclusive space for the bar
*
* This is a minimal window that works with the compositor to reserve space,
* while the actual bar UI is rendered in MainScreen.
*/
PanelWindow {
  id: root

  readonly property bool exclusive: Settings.data.bar.exclusive
  readonly property string barPosition: Settings.getBarPositionForScreen(screen?.name)
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property real barHeight: Style.getBarHeightForScreen(screen?.name)
  readonly property bool barFloating: Settings.data.bar.floating || false
  readonly property bool barIsland: Settings.data.bar.island || false
  readonly property real barMarginH: (barFloating || barIsland) ? Math.ceil(Settings.data.bar.marginHorizontal) : 0
  readonly property real barMarginV: (barFloating || barIsland) ? Math.ceil(Settings.data.bar.marginVertical) : 0
  readonly property real edgeMarginH: (barIsland && (barPosition === "left" || barPosition === "right")) ? 0 : barMarginH
  readonly property real edgeMarginV: (barIsland && (barPosition === "top" || barPosition === "bottom")) ? 0 : barMarginV
  readonly property real fractOffset: CompositorService.getDisplayScale(screen?.name) % 1.0

  // Invisible - just reserves space
  color: "transparent"

  mask: Region {}

  // Wayland layer shell configuration
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "noctalia-bar-exclusion-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: exclusive ? ExclusionMode.Auto : ExclusionMode.Ignore

  // Anchor based on bar position
  anchors {
    top: barPosition === "top"
    bottom: barPosition === "bottom"
    left: barPosition === "left" || barPosition === "top" || barPosition === "bottom"
    right: barPosition === "right" || barPosition === "top" || barPosition === "bottom"
  }

  // Size based on bar orientation
  implicitWidth: {
    if (barIsVertical) {
      // Vertical bar: reserve bar height + margin on the anchored edge only
      return barHeight + edgeMarginH - fractOffset;
    }
    return 0; // Auto-width when left/right anchors are true
  }

  implicitHeight: {
    if (!barIsVertical) {
      // Horizontal bar: reserve bar height + margin on the anchored edge only
      return barHeight + edgeMarginV - fractOffset;
    }
    return 0; // Auto-height when top/bottom anchors are true
  }

  Component.onCompleted: {
    Logger.d("BarExclusionZone", "Created for screen:", screen?.name);
  }
}
