import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Bar
import qs.Services.UI

/**
* BarContentWindow - Separate transparent PanelWindow for bar content
*
* This window contains only the bar widgets (content), while the background
* is rendered in MainScreen's unified Shape system. This separation prevents
* fullscreen redraws when bar widgets redraw.
*
* This component should be instantiated once per screen by AllScreens.qml
*/
PanelWindow {
    id: barWindow

    // Note: screen property is inherited from PanelWindow and should be set by parent
    color: "transparent" // Transparent - background is in MainScreen below

    // Make window pass-through when content is unloaded or bar is hidden via IPC
    visible: contentLoaded && BarService.effectivelyVisible

    Component.onCompleted: {
        Logger.d("BarContentWindow", "Bar content window created for screen:", barWindow.screen?.name);
    }

    // Wayland layer configuration
    WlrLayershell.namespace: "noctalia-bar-content-" + (barWindow.screen?.name || "unknown")
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore // Don't reserve space - BarExclusionZone in MainScreen handles that

    // Position and size to match bar location (per-screen)
    readonly property string barPosition: Settings.getBarPositionForScreen(barWindow.screen?.name)
    readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
    readonly property bool isFramed: Settings.data.bar.barType === "framed"
    readonly property real frameThickness: Settings.data.bar.frameThickness ?? 12
    readonly property bool barFloating: Settings.data.bar.floating || false
    readonly property bool barIsland: Settings.data.bar.island || false
    readonly property real barMarginH: Math.ceil((barFloating || barIsland) ? Settings.data.bar.marginHorizontal : 0)
    readonly property real barMarginV: Math.ceil((barFloating || barIsland) ? Settings.data.bar.marginVertical : 0)
    readonly property real barHeight: Style.getBarHeightForScreen(barWindow.screen?.name)

    // Auto-hide properties
    readonly property bool autoHide: Settings.data.bar.displayMode === "auto_hide"
    readonly property int hideDelay: Settings.data.bar.autoHideDelay || 500
    readonly property int showDelay: Settings.data.bar.autoShowDelay || 100
    property bool isHidden: autoHide

    // Hover tracking
    property bool barHovered: false

    // Check if any panel is open on this screen
    readonly property bool panelOpen: PanelService.openedPanel !== null

    // Timer for delayed hide
    Timer {
        id: hideTimer
        interval: barWindow.hideDelay
        onTriggered: {
            if (barWindow.autoHide && !barWindow.barHovered && !barWindow.panelOpen && !BarService.popupOpen) {
                BarService.setScreenHidden(barWindow.screen?.name, true);
            }
        }
    }

    // Timer for delayed show
    Timer {
        id: showTimer
        interval: barWindow.showDelay
        onTriggered: {
            // Only show if still hovered (via trigger zone or bar itself)
            if (barWindow.autoHide && BarService.isBarHovered(barWindow.screen?.name)) {
                BarService.setScreenHidden(barWindow.screen?.name, false);
            }
        }
    }

    // React to auto-hide state changes from BarService
    Connections {
        target: BarService
        function onBarAutoHideStateChanged(screenName, hidden) {
            Logger.d("BarContentWindow", "onBarAutoHideStateChanged:", screenName, hidden, "my screen:", barWindow.screen?.name);
            if (screenName === barWindow.screen?.name) {
                barWindow.isHidden = hidden;
            }
        }
        function onBarHoverStateChanged(screenName, hovered) {
            if (screenName === barWindow.screen?.name && barWindow.autoHide) {
                if (hovered) {
                    hideTimer.stop();
                    // If bar is already visible, no need to delay
                    if (!barWindow.isHidden) {
                        showTimer.stop();
                    } else {
                        // Bar is hidden, use show delay
                        showTimer.restart();
                    }
                } else if (!barWindow.barHovered && !barWindow.panelOpen) {
                    showTimer.stop();
                    hideTimer.restart();
                }
            }
        }
    }

    // Don't hide when panel is open
    onPanelOpenChanged: {
        if (panelOpen && autoHide) {
            hideTimer.stop();
            BarService.setScreenHidden(barWindow.screen?.name, false);
        } else if (!panelOpen && autoHide && !barHovered) {
            hideTimer.restart();
        }
    }

    // React to popup menu closing
    Connections {
        target: BarService
        function onPopupOpenChanged() {
            if (!BarService.popupOpen && barWindow.autoHide && !barWindow.barHovered && !barWindow.panelOpen) {
                hideTimer.restart();
            }
        }
    }

    // React to displayMode changes
    onAutoHideChanged: {
        if (!autoHide) {
            // Show bar when auto-hide is disabled
            hideTimer.stop();
            showTimer.stop();
            barWindow.isHidden = false;
        }
        // When auto-hide is enabled, don't immediately hide - wait for mouse to leave
    }

    // Anchor to the bar's edge
    anchors {
        top: barPosition === "top" || barIsVertical
        bottom: barPosition === "bottom" || barIsVertical
        left: barPosition === "left" || !barIsVertical
        right: barPosition === "right" || !barIsVertical
    }

    // Track if content should be loaded (stays true during fade-out animation)
    property bool contentLoaded: !isHidden

    // Timer to delay unload until after fade animation
    Timer {
        id: unloadTimer
        interval: Style.animationFast + 50
        onTriggered: {
            // Only unload if still hidden AND not about to show (prevents unload/reload race)
            if (barWindow.isHidden && !showTimer.running) {
                // Clear hover state before unloading to prevent issues during destruction
                barWindow.barHovered = false;
                barWindow.contentLoaded = false;
            }
        }
    }

    // When hidden changes, handle load/unload
    onIsHiddenChanged: {
        if (isHidden) {
            // Start fade out, then unload after animation
            unloadTimer.restart();
        } else {
            // Load immediately when showing
            unloadTimer.stop();
            deferredUnloadTimer.stop();
            contentLoaded = true;
        }
    }

    // Debounced content unload when bar visibility is toggled.
    // Rapid toggles keep widgets alive; content is only unloaded after the bar
    // has been continuously hidden for the debounce period.
    Timer {
        id: deferredUnloadTimer
        interval: 1000
        onTriggered: {
            if (!BarService.effectivelyVisible) {
                barWindow.barHovered = false;
                barWindow.contentLoaded = false;
                Logger.d("BarContentWindow", "Debounced content unload for screen:", barWindow.screen?.name);
            }
        }
    }

    Connections {
        target: BarService
        function onEffectivelyVisibleChanged() {
            if (!BarService.effectivelyVisible) {
                // Bar hidden — start debounced unload
                deferredUnloadTimer.restart();
            } else {
                // Bar shown — cancel pending unload, ensure content is loaded
                deferredUnloadTimer.stop();
                if (!barWindow.isHidden) {
                    barWindow.contentLoaded = true;
                }
            }
        }
    }

    // Handle floating/island margins and framed mode offsets
    margins {
        top: {
            if (barIsland)
                return barPosition === "top" ? 0 : (barIsVertical ? barMarginV : 0);
            if (barPosition === "top")
                return barMarginV;
            if (isFramed)
                return frameThickness;
            return barIsVertical ? barMarginV : 0;
        }
        bottom: {
            if (barIsland)
                return barPosition === "bottom" ? 0 : (barIsVertical ? barMarginV : 0);
            if (barPosition === "bottom")
                return barMarginV;
            if (isFramed)
                return frameThickness;
            return barIsVertical ? barMarginV : 0;
        }
        left: {
            if (barIsland)
                return barPosition === "left" ? 0 : (!barIsVertical ? barMarginH : 0);
            if (barPosition === "left")
                return barMarginH;
            if (isFramed)
                return frameThickness;
            return !barIsVertical ? barMarginH : 0;
        }
        right: {
            if (barIsland)
                return barPosition === "right" ? 0 : (!barIsVertical ? barMarginH : 0);
            if (barPosition === "right")
                return barMarginH;
            if (isFramed)
                return frameThickness;
            return !barIsVertical ? barMarginH : 0;
        }
    }

    // Set a tight window size
    implicitWidth: barIsVertical ? barHeight : barWindow.screen.width
    implicitHeight: barIsVertical ? barWindow.screen.height : barHeight

    // Bar content loader - unloads when hidden to prevent input
    Loader {
        id: barLoader
        anchors.fill: parent
        active: barWindow.contentLoaded

        sourceComponent: Item {
            anchors.fill: parent

            // Fade animation
            opacity: barWindow.isHidden ? 0 : 1

            Behavior on opacity {
                enabled: barWindow.autoHide
                NumberAnimation {
                    duration: Style.animationFast
                    easing.type: Easing.OutQuad
                }
            }

            Bar {
                id: barContent
                anchors.fill: parent
                screen: barWindow.screen

                // Hover detection using HoverHandler (doesn't block child hover events)
                HoverHandler {
                    id: hoverHandler

                    onHoveredChanged: {
                        if (hovered) {
                            barWindow.barHovered = true;
                            BarService.setScreenHovered(barWindow.screen?.name, true);
                            if (barWindow.autoHide) {
                                hideTimer.stop();
                                showTimer.restart();
                            }
                        } else {
                            // Skip if already hidden (being destroyed)
                            if (barWindow.isHidden)
                                return;
                            barWindow.barHovered = false;
                            BarService.setScreenHovered(barWindow.screen?.name, false);
                            if (barWindow.autoHide && !barWindow.panelOpen) {
                                showTimer.stop();
                                hideTimer.restart();
                            }
                        }
                    }
                }
            }
        }
    }
}
