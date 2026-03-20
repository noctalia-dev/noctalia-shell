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

  // Window invisible when auto-hidden (blocks input) or toggled off via IPC.
  // windowVisible stays true briefly after isHidden to allow fade-out animation.
  property bool windowVisible: !isHidden
  visible: contentLoaded && windowVisible && BarService.effectivelyVisible

  Component.onCompleted: {
    Logger.d("BarContentWindow", "Bar content window created for screen:", barWindow.screen?.name);
    if (!isHidden)
      contentLoaded = true;
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
  readonly property bool barFloating: Settings.data.bar.barType === "floating"
  readonly property real barMarginH: Math.ceil(barFloating ? Settings.data.bar.marginHorizontal : 0)
  readonly property real barMarginV: Math.ceil(barFloating ? Settings.data.bar.marginVertical : 0)
  readonly property real barHeight: Style.getBarHeightForScreen(barWindow.screen?.name)

  // Auto-hide properties
  readonly property bool autoHide: Settings.getBarDisplayModeForScreen(barWindow.screen?.name) === "auto_hide"
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

  // Content stays loaded once initialized — never unloaded during auto-hide.
  // Destroying and recreating widgets on every hide/show cycle caused nested
  // QML incubation crashes (SIGSEGV in QV4::Object::insertMember) because
  // async widget Loaders complete during incubateFor() and their onLoaded
  // handlers trigger signal cascades mid-incubation.
  // The bar is hidden via opacity + window visibility instead.
  property bool contentLoaded: false

  // Delay window hide to allow fade-out animation to complete
  Timer {
    id: windowHideTimer
    interval: Style.animationFast
    onTriggered: {
      if (barWindow.isHidden)
        barWindow.windowVisible = false;
    }
  }

  onIsHiddenChanged: {
    if (isHidden) {
      // Delay window hide so fade-out is visible
      windowHideTimer.restart();
    } else {
      windowHideTimer.stop();
      windowVisible = true;
      if (!contentLoaded)
        contentLoaded = true;
    }
  }

  Connections {
    target: BarService
    function onEffectivelyVisibleChanged() {
      if (BarService.effectivelyVisible && !barWindow.isHidden && !barWindow.contentLoaded) {
        barWindow.contentLoaded = true;
      }
    }
  }

  // Handle floating margins and framed mode offsets
  margins {
    top: (barPosition === "top") ? barMarginV : (isFramed ? frameThickness : barMarginV)
    bottom: (barPosition === "bottom") ? barMarginV : (isFramed ? frameThickness : barMarginV)
    left: (barPosition === "left") ? barMarginH : (isFramed ? frameThickness : barMarginH)
    right: (barPosition === "right") ? barMarginH : (isFramed ? frameThickness : barMarginH)
  }

  // Set a tight window size
  implicitWidth: barIsVertical ? barHeight : barWindow.screen.width
  implicitHeight: barIsVertical ? barWindow.screen.height : barHeight

  // Bar content loader - loaded once, stays active for lifetime
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
