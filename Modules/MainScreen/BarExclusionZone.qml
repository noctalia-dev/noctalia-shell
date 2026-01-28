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

    // Edge to anchor to and thickness to reserve
    property string edge: Settings.getBarPositionForScreen(screen?.name)
    property real thickness: (edge === Settings.getBarPositionForScreen(screen?.name)) ? Style.getBarHeightForScreen(screen?.name) : (Settings.data.bar.frameThickness ?? 12)

    readonly property bool exclusive: Settings.data.bar.exclusive
    readonly property bool barFloating: Settings.data.bar.floating || false
    readonly property bool barIsland: Settings.data.bar.island || false
    readonly property real barMarginH: (barFloating || barIsland) ? Math.ceil(Settings.data.bar.marginHorizontal) : 0
    readonly property real barMarginV: (barFloating || barIsland) ? Math.ceil(Settings.data.bar.marginVertical) : 0
    readonly property bool barIsVertical: edge === "left" || edge === "right"
    readonly property real edgeMarginH: (barIsland && barIsVertical) ? 0 : barMarginH
    readonly property real edgeMarginV: (barIsland && !barIsVertical) ? 0 : barMarginV
    readonly property real fractOffset: CompositorService.getDisplayScale(screen?.name) % 1.0

    // Invisible - just reserves space
    color: "transparent"

    mask: Region {}

    // Wayland layer shell configuration
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "noctalia-bar-exclusion-" + edge + "-" + (screen?.name || "unknown")
    WlrLayershell.exclusionMode: exclusive ? ExclusionMode.Auto : ExclusionMode.Ignore

    // Anchor based on specified edge
    anchors {
        top: edge === "top"
        bottom: edge === "bottom"
        left: edge === "left" || edge === "top" || edge === "bottom"
        right: edge === "right" || edge === "top" || edge === "bottom"
    }

    // Size based on orientation
    implicitWidth: {
        if (barIsVertical) {
            return thickness + edgeMarginH - fractOffset;
        }
        return 0; // Auto-width when left/right anchors are true
    }

    implicitHeight: {
        if (!barIsVertical) {
            return thickness + edgeMarginV - fractOffset;
        }
        return 0; // Auto-height when top/bottom anchors are true
    }

    Component.onCompleted: {
        Logger.d("BarExclusionZone", "Created for screen:", screen?.name);
    }
}
