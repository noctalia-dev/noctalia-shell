import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI

/**
* BarExclusionZone - Invisible PanelWindow that reserves exclusive space for the bar
*
* This is a minimal window that works with the compositor to reserve space,
* while the actual bar UI is rendered in MainScreen.
*/
PanelWindow {
  id: root

  // Edge to anchor to and thickness to reserve
  property string edge: Settings.getBarPositionForScreen(screen?.name)
  property real thickness: (edge === Settings.getBarPositionForScreen(screen?.name)) ? Style.getBarHeightForScreen(screen?.name) : (Settings.data.bar.frameThickness ?? 12)

  readonly property bool autoHide: Settings.data.bar.displayMode === "auto_hide"
  readonly property bool nonExclusive: Settings.data.bar.displayMode === "non_exclusive"
  readonly property bool barFloating: Settings.data.bar.floating || false
  readonly property real barMarginH: (barFloating && edge === Settings.getBarPositionForScreen(screen?.name)) ? Math.ceil(Settings.data.bar.marginHorizontal) : 0
  readonly property real barMarginV: (barFloating && edge === Settings.getBarPositionForScreen(screen?.name)) ? Math.ceil(Settings.data.bar.marginVertical) : 0
  // Reduce exclusion zone by 1 physical pixel so app windows blend flush against the bar edge
  readonly property real bleedInset: 1.0 / (CompositorService.getDisplayScale(screen?.name) || 1.0)

  // Invisible - just reserves space
  color: "transparent"

  mask: Region {}

  // Wayland layer shell configuration
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "noctalia-bar-exclusion-" + edge + "-" + (screen?.name || "unknown")
  // When auto-hide, non-exclusive mode is enabled, OR bar is explicitly hidden via IPC, don't reserve space
  // Note: We check BarService.isVisible directly, NOT effectivelyVisible, because we want
  // the exclusion zone to stay during overview (effectivelyVisible is false during overview
  // when hideOnOverview is enabled, but isVisible remains true)
  WlrLayershell.exclusionMode: (autoHide || nonExclusive || !BarService.isVisible) ? ExclusionMode.Ignore : ExclusionMode.Auto

  // Anchor based on specified edge
  anchors {
    top: edge === "top"
    bottom: edge === "bottom"
    left: edge === "left" || edge === "top" || edge === "bottom"
    right: edge === "right" || edge === "top" || edge === "bottom"
  }

  // Size based on orientation
  implicitWidth: {
    if (edge === "left" || edge === "right") {
      return thickness + barMarginH - bleedInset;
    }
    return 0; // Auto-width when left/right anchors are true
  }

  implicitHeight: {
    if (edge === "top" || edge === "bottom") {
      return thickness + barMarginV - bleedInset;
    }
    return 0; // Auto-height when top/bottom anchors are true
  }

  Component.onCompleted: {
    Logger.d("BarExclusionZone", "Created for screen:", screen?.name);
  }
}
