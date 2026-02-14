import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI

/**
* SmartPanel for use within MainScreen
*/
Item {
  id: root

  // Screen property provided by MainScreen
  property ShellScreen screen: null

  // Panel content: Text, icons, etc...
  property Component panelContent: null

  // PanelID for binding panels to widgets of the same type
  property var panelID: null

  // Panel size properties
  property real preferredWidth: 700
  property real preferredHeight: 900
  property real preferredWidthRatio
  property real preferredHeightRatio
  property color panelBackgroundColor: Color.mSurface
  property color panelBorderColor: Color.mOutline
  property var buttonItem: null
  property bool forceAttachToBar: false

  // Anchoring properties
  property bool panelAnchorHorizontalCenter: false
  property bool panelAnchorVerticalCenter: false
  property bool panelAnchorTop: false
  property bool panelAnchorBottom: false
  property bool panelAnchorLeft: false
  property bool panelAnchorRight: false

  // Button position properties
  property bool useButtonPosition: false
  property point buttonPosition: Qt.point(0, 0)
  property int buttonWidth: 0
  property int buttonHeight: 0

  // Edge snapping: if panel is within this distance (in pixels) from a screen edge, snap
  property real edgeSnapDistance: 50

  // Track whether panel is open
  property bool isPanelOpen: false

  // Track actual visibility (delayed until content is loaded and sized)
  property bool isPanelVisible: false

  // Track size animation completion for sequential opacity animation
  property bool sizeAnimationComplete: false

  // Derived state: track opening transition
  readonly property bool isOpening: isPanelVisible && !isClosing && !sizeAnimationComplete

  // Track close animation state: fade opacity first, then shrink size
  property bool isClosing: false
  property bool opacityFadeComplete: false
  property bool closeFinalized: false // Prevent double-finalization

  // Safety: Watchdog timers to prevent stuck states
  property bool closeWatchdogActive: false
  property bool openWatchdogActive: false

  // Cached animation direction - set when panel opens, doesn't change during animation
  // These are computed once when opening and used for the entire open/close cycle
  property bool cachedAnimateFromTop: false
  property bool cachedAnimateFromBottom: false
  property bool cachedAnimateFromLeft: false
  property bool cachedAnimateFromRight: false
  property bool cachedShouldAnimateWidth: false
  property bool cachedShouldAnimateHeight: false

  // Close with escape key
  property bool closeWithEscape: true

  property bool exclusiveKeyboard: true

  // Keyboard event handler
  // These are called from MainScreen's centralized shortcuts
  // override these in specific panels to handle shortcuts
  function onEscapePressed() {
    if (closeWithEscape)
      close();
  }

  // Expose panel region for background rendering
  readonly property var panelRegion: panelContent.geometryPlaceholder

  readonly property string barPosition: Settings.getBarPositionForScreen(screen?.name)
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property real barHeight: barShouldShow ? Style.getBarHeightForScreen(screen?.name) : 0
  readonly property bool hasBar: modelData && modelData.name ? (Settings.data.bar.monitors.includes(modelData.name) || (Settings.data.bar.monitors.length === 0)) : false
  readonly property bool isFramed: Settings.data.bar.barType === "framed" && hasBar
  readonly property real frameThickness: Settings.data.bar.frameThickness ?? 12
  readonly property bool barFloating: Settings.data.bar.floating
  readonly property real barMarginH: (barFloating && barShouldShow) ? Math.ceil(Settings.data.bar.marginHorizontal) : 0
  readonly property real barMarginV: (barFloating && barShouldShow) ? Math.ceil(Settings.data.bar.marginVertical) : 0
  readonly property real attachmentOverlap: 1 // Panel extends into bar area to fix hairline gap with fractional scaling

  // Check if bar should be visible on this screen
  readonly property bool barShouldShow: {
    if (!BarService.effectivelyVisible)
      return false;
    var monitors = Settings.data.bar.monitors || [];
    var screenName = screen?.name || "";
    return monitors.length === 0 || monitors.includes(screenName);
  }

  // Helper to detect if any anchor is explicitly set
  readonly property bool hasExplicitHorizontalAnchor: panelAnchorHorizontalCenter || panelAnchorLeft || panelAnchorRight
  readonly property bool hasExplicitVerticalAnchor: panelAnchorVerticalCenter || panelAnchorTop || panelAnchorBottom

  // Effective anchor properties (depend on allowAttach)
  // These are true when allowAttach is enabled AND:
  // 1. Explicitly anchored to that edge, OR
  // 2. Using button position and bar is on that edge, OR
  // 3. No explicit anchors and bar is on that edge (default centering behavior)
  readonly property bool effectivePanelAnchorTop: panelContent.allowAttach && (panelAnchorTop || (useButtonPosition && barPosition === "top") || (!hasExplicitVerticalAnchor && barPosition === "top" && !barIsVertical))
  readonly property bool effectivePanelAnchorBottom: panelContent.allowAttach && (panelAnchorBottom || (useButtonPosition && barPosition === "bottom") || (!hasExplicitVerticalAnchor && barPosition === "bottom" && !barIsVertical))
  readonly property bool effectivePanelAnchorLeft: panelContent.allowAttach && (panelAnchorLeft || (useButtonPosition && barPosition === "left") || (!hasExplicitHorizontalAnchor && barPosition === "left" && barIsVertical))
  readonly property bool effectivePanelAnchorRight: panelContent.allowAttach && (panelAnchorRight || (useButtonPosition && barPosition === "right") || (!hasExplicitHorizontalAnchor && barPosition === "right" && barIsVertical))

  signal opened
  signal closed

  Connections {
    target: Style

    function onUiScaleRatioChanged() {
      if (root.isPanelOpen && root.isPanelVisible) {
        root.setPosition();
      }
    }
  }

  // Panel visibility and sizing
  visible: isPanelVisible
  width: parent ? parent.width : 0
  height: parent ? parent.height : 0

  // Panel control functions
  function toggle(buttonItem, buttonName) {
    if (!isPanelOpen) {
      open(buttonItem, buttonName);
    } else {
      close();
    }
  }

  function open(buttonItem, buttonName) {
    // Reset immediate close flag to ensure animations work properly
    PanelService.closedImmediately = false;

    if (!buttonItem && buttonName) {
      // Check if buttonName is actually a point object (click coordinates)
      if (typeof buttonName === "object" && buttonName.x !== undefined && buttonName.y !== undefined) {
        root.buttonItem = null;
        root.buttonPosition = buttonName;
        root.buttonWidth = 0;
        root.buttonHeight = 0;
        root.useButtonPosition = true;
      } else {
        // buttonName is a widget name, look it up
        buttonItem = BarService.lookupWidget(buttonName, screen.name);
      }
    }

    // Validate buttonItem is a valid QML Item with mapToItem function
    if (buttonItem && typeof buttonItem.mapToItem === "function") {
      try {
        root.buttonItem = buttonItem;
        // Map button position within its window
        var buttonLocal = buttonItem.mapToItem(null, 0, 0);

        // Calculate the bar window's position on screen based on bar settings
        // The BarContentWindow uses anchors, so we need to compute its position
        var barWindowX = 0;
        var barWindowY = 0;
        var screenWidth = root.screen?.width || 0;
        var screenHeight = root.screen?.height || 0;

        if (root.barPosition === "right") {
          barWindowX = screenWidth - root.barMarginH - root.barHeight;
        } else if (root.barPosition === "left") {
          barWindowX = root.barMarginH;
        } else if (root.isFramed) {
          barWindowX = root.frameThickness;
        }
        // For top/bottom bars, barWindowX stays 0 (full width window) unless framed

        if (root.barPosition === "bottom") {
          barWindowY = screenHeight - root.barMarginV - root.barHeight;
        } else if (root.barPosition === "top") {
          barWindowY = root.barMarginV;
        } else if (root.isFramed) {
          barWindowY = root.frameThickness;
        }
        // For left/right bars, barWindowY stays 0 (full height window) unless framed

        root.buttonPosition = Qt.point(barWindowX + buttonLocal.x, barWindowY + buttonLocal.y);
        root.buttonWidth = buttonItem.width;
        root.buttonHeight = buttonItem.height;
        root.useButtonPosition = true;
      } catch (e) {
        Logger.w("SmartPanel", "Failed to get button position, using default positioning:", e);
        root.buttonItem = null;
        root.useButtonPosition = false;
      }
    } else if (!root.useButtonPosition) {
      // No valid button provided and no click position: reset button position mode
      root.buttonItem = null;
    }

    // Set isPanelOpen to trigger content loading, but don't show yet
    isPanelOpen = true;

    // Notify PanelService
    PanelService.willOpenPanel(root);

    // Position and visibility will be set by Loader.onLoaded
    // This ensures no flicker from default size to content size
  }

  function close() {
    // Reset immediate close flag to ensure animations work properly
    PanelService.closedImmediately = false;

    // Start close sequence: fade opacity first
    isClosing = true;
    sizeAnimationComplete = false;
    closeFinalized = false;

    // Stop the open animation timer if it's still running
    opacityTrigger.stop();
    openWatchdogActive = false;
    openWatchdogTimer.stop();

    // Start close watchdog timer
    closeWatchdogActive = true;
    closeWatchdogTimer.restart();

    // If opacity is already 0 (closed during open animation before fade-in),
    // skip directly to size animation
    if (root.opacity === 0.0) {
      opacityFadeComplete = true;
    } else {
      opacityFadeComplete = false;
    }

    // Opacity will fade out, then size will shrink, then finalizeClose() will complete
    Logger.d("SmartPanel", "Closing panel", objectName);
  }

  function closeImmediately() {
    // Close without any animation, useful for app launches to avoid focus issues
    opacityTrigger.stop();
    openWatchdogActive = false;
    openWatchdogTimer.stop();
    closeWatchdogActive = false;
    closeWatchdogTimer.stop();

    // Don't set opacity directly as it breaks the binding
    root.isPanelVisible = false;
    root.sizeAnimationComplete = false;
    root.isClosing = false;
    root.opacityFadeComplete = false;
    root.closeFinalized = true;
    root.isPanelOpen = false;
    panelBackground.dimensionsInitialized = false;

    // Signal immediate close so MainScreen can skip dimmer animation
    PanelService.closedImmediately = true;
    PanelService.closedPanel(root);
    closed();

    Logger.d("SmartPanel", "Panel closed immediately", objectName);
  }

  function finalizeClose() {
    // Prevent double-finalization
    if (root.closeFinalized) {
      Logger.w("SmartPanel", "finalizeClose called but already finalized - ignoring", objectName);
      return;
    }

    // Complete the close sequence after animations finish
    root.closeFinalized = true;
    root.closeWatchdogActive = false;
    closeWatchdogTimer.stop();

    root.isPanelVisible = false;
    root.isPanelOpen = false;
    root.isClosing = false;
    root.opacityFadeComplete = false;

    // Reset dimensionsInitialized for next opening
    panelBackground.dimensionsInitialized = false;

    PanelService.closedPanel(root);
    closed();

    Logger.d("SmartPanel", "Panel close finalized", objectName);
  }

  function setPosition() {
    // Don't calculate position if parent dimensions aren't available yet
    // This prevents centering around (0,0) when width/height are still 0
    if (!root.width || !root.height) {
      Logger.d("SmartPanel", "Skipping setPosition - dimensions not ready:", root.width, "x", root.height);
      // Retry on next frame when dimensions should be available
      Qt.callLater(setPosition);
      return;
    }

    // Effective screen margins (account for frame thickness)
    var effMarginL = Style.marginL + (root.isFramed ? root.frameThickness : 0);
    var effMarginR = Style.marginL + (root.isFramed ? root.frameThickness : 0);
    var effMarginT = Style.marginL + (root.isFramed ? root.frameThickness : 0);
    var effMarginB = Style.marginL + (root.isFramed ? root.frameThickness : 0);

    // Calculate panel dimensions first (needed for positioning)
    var w;
    // Priority 1: Content-driven size (dynamic)
    if (contentLoader.item && contentLoader.item.contentPreferredWidth !== undefined) {
      w = contentLoader.item.contentPreferredWidth;
    } // Priority 2: Ratio-based size
    else if (root.preferredWidthRatio !== undefined) {
      w = Math.round(Math.max(root.width * root.preferredWidthRatio, root.preferredWidth));
    } // Priority 3: Static preferred width
    else {
      w = root.preferredWidth;
    }
    var panelWidth = Math.min(w, root.width - effMarginL - effMarginR);

    var h;
    // Priority 1: Content-driven size (dynamic)
    if (contentLoader.item && contentLoader.item.contentPreferredHeight !== undefined) {
      h = contentLoader.item.contentPreferredHeight;
    } // Priority 2: Ratio-based size
    else if (root.preferredHeightRatio !== undefined) {
      h = Math.round(Math.max(root.height * root.preferredHeightRatio, root.preferredHeight));
    } // Priority 3: Static preferred height
    else {
      h = root.preferredHeight;
    }
    var panelHeight = Math.min(h, root.height - root.barHeight - effMarginT - effMarginB);

    // Update panelBackground target size (will be animated)
    panelBackground.targetWidth = panelWidth;
    panelBackground.targetHeight = panelHeight;

    // Pre-compute bar edge positions with overlap (used multiple times below)
    // For attached panels, we extend slightly into the bar area to prevent hairline gaps
    var leftBarEdgeWithOverlap = root.barMarginH + root.barHeight - root.attachmentOverlap;
    var rightBarEdgeWithOverlap = root.width - root.barMarginH - root.barHeight + root.attachmentOverlap;
    var topBarEdgeWithOverlap = root.barMarginV + root.barHeight - root.attachmentOverlap;
    var bottomBarEdgeWithOverlap = root.height - root.barMarginV - root.barHeight + root.attachmentOverlap;

    if (root.isFramed) {
      if (root.barPosition === "left")
        leftBarEdgeWithOverlap = root.barHeight - root.attachmentOverlap;
      if (root.barPosition === "right")
        rightBarEdgeWithOverlap = root.width - root.barHeight + root.attachmentOverlap;
      if (root.barPosition === "top")
        topBarEdgeWithOverlap = root.barHeight - root.attachmentOverlap;
      if (root.barPosition === "bottom")
        bottomBarEdgeWithOverlap = root.height - root.barHeight + root.attachmentOverlap;
    }

    // Calculate position
    var calculatedX;
    var calculatedY;

    // ===== X POSITIONING =====
    if (root.useButtonPosition && root.width > 0 && panelWidth > 0) {
      if (root.barIsVertical) {
        // For vertical bars
        if (panelContent.allowAttach) {
          // Attached panels: align with bar edge (left or right side)
          if (root.barPosition === "left") {
            calculatedX = leftBarEdgeWithOverlap;
          } else {
            calculatedX = rightBarEdgeWithOverlap - panelWidth;
          }
        } else {
          // Detached panels: center on button X position
          var panelX = root.buttonPosition.x + root.buttonWidth / 2 - panelWidth / 2;
          var minX = effMarginL;
          var maxX = root.width - panelWidth - effMarginR;

          // Account for vertical bar taking up space
          if (root.barPosition === "left") {
            minX = (root.isFramed ? 0 : root.barMarginH) + root.barHeight + Style.marginL;
          } else if (root.barPosition === "right") {
            maxX = root.width - (root.isFramed ? 0 : root.barMarginH) - root.barHeight - panelWidth - Style.marginL;
          }

          panelX = Math.max(minX, Math.min(panelX, maxX));
          calculatedX = panelX;
        }
      } else {
        // For horizontal bars, center panel on button X position
        var panelX = root.buttonPosition.x + root.buttonWidth / 2 - panelWidth / 2;
        if (panelContent.allowAttach) {
          var cornerInset = root.barFloating ? Style.radiusL * 2 : 0;
          var barLeftEdge = (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginH) + cornerInset;
          var barRightEdge = root.width - (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginH) - cornerInset;
          panelX = Math.max(barLeftEdge, Math.min(panelX, barRightEdge - panelWidth));
        } else {
          panelX = Math.max(effMarginL, Math.min(panelX, root.width - panelWidth - effMarginR));
        }
        calculatedX = panelX;
      }
    } else {
      // Standard anchor positioning
      if (root.panelAnchorHorizontalCenter) {
        if (root.barIsVertical) {
          if (root.barPosition === "left") {
            var availableStart = (root.isFramed ? 0 : root.barMarginH) + root.barHeight;
            var availableWidth = root.width - availableStart - (root.isFramed ? root.frameThickness : 0);
            calculatedX = availableStart + (availableWidth - panelWidth) / 2;
          } else if (root.barPosition === "right") {
            var availableWidth = root.width - (root.isFramed ? 0 : root.barMarginH) - root.barHeight - (root.isFramed ? root.frameThickness : 0);
            calculatedX = (root.isFramed ? root.frameThickness : 0) + (availableWidth - panelWidth) / 2;
          } else {
            calculatedX = (root.width - panelWidth) / 2;
          }
        } else {
          calculatedX = (root.width - panelWidth) / 2;
        }
      } else if (root.panelAnchorRight) {
        // Use raw panelAnchorRight for positioning decision
        if (root.effectivePanelAnchorRight) {
          // Attached: snap to edge/bar
          if (root.barIsVertical && root.barPosition === "right") {
            calculatedX = rightBarEdgeWithOverlap - panelWidth;
          } else {
            var panelOnSameEdgeAsBar = (root.barPosition === "top" && root.effectivePanelAnchorTop) || (root.barPosition === "bottom" && root.effectivePanelAnchorBottom);
            if (!root.barIsVertical && root.barFloating && panelOnSameEdgeAsBar) {
              var rightCornerInset = Style.radiusL * 2;
              calculatedX = root.width - root.barMarginH - rightCornerInset - panelWidth;
            } else {
              calculatedX = root.width - panelWidth - (root.isFramed ? root.frameThickness - root.attachmentOverlap : 0);
            }
          }
        } else {
          // Not attached: position at right with margin
          calculatedX = root.width - panelWidth - effMarginR;
        }
      } else if (root.panelAnchorLeft) {
        // Use raw panelAnchorLeft for positioning decision
        if (root.effectivePanelAnchorLeft) {
          // Attached: snap to edge/bar
          if (root.barIsVertical && root.barPosition === "left") {
            calculatedX = leftBarEdgeWithOverlap;
          } else {
            var panelOnSameEdgeAsBar = (root.barPosition === "top" && root.effectivePanelAnchorTop) || (root.barPosition === "bottom" && root.effectivePanelAnchorBottom);
            if (!root.barIsVertical && root.barFloating && panelOnSameEdgeAsBar) {
              var leftCornerInset = Style.radiusL * 2;
              calculatedX = root.barMarginH + leftCornerInset;
            } else {
              calculatedX = (root.isFramed ? root.frameThickness - root.attachmentOverlap : 0);
            }
          }
        } else {
          // Not attached: position at left with margin
          calculatedX = effMarginL;
        }
      } else {
        // No explicit anchor: attach to bar if allowAttach, otherwise center
        if (root.barIsVertical) {
          if (panelContent.allowAttach) {
            // Attach to the bar edge (with overlap into bar area)
            if (root.barPosition === "left") {
              calculatedX = leftBarEdgeWithOverlap;
            } else {
              calculatedX = rightBarEdgeWithOverlap - panelWidth;
            }
          } else {
            // Not attached: center in available space
            if (root.barPosition === "left") {
              var availableStart = (root.isFramed ? 0 : root.barMarginH) + root.barHeight;
              var availableWidth = root.width - availableStart - effMarginR;
              calculatedX = availableStart + (availableWidth - panelWidth) / 2;
            } else {
              var availableWidth = root.width - (root.isFramed ? 0 : root.barMarginH) - root.barHeight - effMarginL;
              calculatedX = effMarginL + (availableWidth - panelWidth) / 2;
            }
          }
        } else {
          if (panelContent.allowAttach) {
            var cornerInset = Style.radiusL + (root.barFloating ? Style.radiusL : 0);
            var barLeftEdge = (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginH) + cornerInset;
            var barRightEdge = root.width - (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginH) - cornerInset;
            var centeredX = (root.width - panelWidth) / 2;
            calculatedX = Math.max(barLeftEdge, Math.min(centeredX, barRightEdge - panelWidth));
          } else {
            calculatedX = (root.width - panelWidth) / 2;
          }
        }
      }
    }

    // Edge snapping for X
    if (panelContent.allowAttach && !root.barFloating && root.width > 0 && panelWidth > 0) {
      var leftEdgePos = root.barPosition === "left" ? leftBarEdgeWithOverlap : (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginH);
      var rightEdgePos = root.barPosition === "right" ? rightBarEdgeWithOverlap - panelWidth : root.width - (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginH) - panelWidth;

      // Only snap to left edge if panel is actually meant to be at left (or no explicit anchor)
      var shouldSnapToLeft = root.effectivePanelAnchorLeft || (!root.hasExplicitHorizontalAnchor && root.barPosition === "left");
      // Only snap to right edge if panel is actually meant to be at right (or no explicit anchor)
      var shouldSnapToRight = root.effectivePanelAnchorRight || (!root.hasExplicitHorizontalAnchor && root.barPosition === "right");

      if (shouldSnapToLeft && Math.abs(calculatedX - leftEdgePos) <= root.edgeSnapDistance) {
        calculatedX = leftEdgePos;
      } else if (shouldSnapToRight && Math.abs(calculatedX - rightEdgePos) <= root.edgeSnapDistance) {
        calculatedX = rightEdgePos;
      }
    }

    // ===== Y POSITIONING =====
    if (root.useButtonPosition && root.height > 0 && panelHeight > 0) {
      if (root.barPosition === "top") {
        if (panelContent.allowAttach) {
          calculatedY = topBarEdgeWithOverlap;
        } else {
          calculatedY = (root.isFramed ? 0 : root.barMarginV) + root.barHeight + Style.marginM;
        }
      } else if (root.barPosition === "bottom") {
        if (panelContent.allowAttach) {
          calculatedY = bottomBarEdgeWithOverlap - panelHeight;
        } else {
          calculatedY = root.height - (root.isFramed ? 0 : root.barMarginV) - root.barHeight - panelHeight - Style.marginM;
        }
      } else if (root.barIsVertical) {
        var panelY = root.buttonPosition.y + root.buttonHeight / 2 - panelHeight / 2;
        var extraPadding = (panelContent.allowAttach && root.barFloating) ? Style.radiusL : 0;
        if (panelContent.allowAttach) {
          var cornerInset = extraPadding + (root.barFloating ? Style.radiusL : 0);
          var barTopEdge = (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginV) + cornerInset;
          var barBottomEdge = root.height - (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginV) - cornerInset;
          panelY = Math.max(barTopEdge, Math.min(panelY, barBottomEdge - panelHeight));
        } else {
          panelY = Math.max(effMarginT + extraPadding, Math.min(panelY, root.height - panelHeight - effMarginB - extraPadding));
        }
        calculatedY = panelY;
      }
    } else {
      // Standard anchor positioning
      var barOffset = !panelContent.allowAttach && (root.barPosition === "top" || root.barPosition === "bottom") ? (root.isFramed ? 0 : root.barMarginV) + root.barHeight + Style.marginM : 0;

      if (panelContent.allowAttach && !root.barIsVertical) {
        // Attached to horizontal bar: position with overlap
        if ((root.effectivePanelAnchorTop && root.barPosition === "top") || (!root.hasExplicitVerticalAnchor && root.barPosition === "top")) {
          calculatedY = topBarEdgeWithOverlap;
        } else if ((root.effectivePanelAnchorBottom && root.barPosition === "bottom") || (!root.hasExplicitVerticalAnchor && root.barPosition === "bottom")) {
          calculatedY = bottomBarEdgeWithOverlap - panelHeight;
        }
      }

      if (calculatedY === undefined) {
        if (root.panelAnchorVerticalCenter) {
          if (!root.barIsVertical) {
            if (root.barPosition === "top") {
              var availableStart = (root.isFramed ? 0 : root.barMarginV) + root.barHeight;
              var availableHeight = root.height - availableStart - (root.isFramed ? root.frameThickness : 0);
              calculatedY = availableStart + (availableHeight - panelHeight) / 2;
            } else if (root.barPosition === "bottom") {
              var availableHeight = root.height - (root.isFramed ? 0 : root.barMarginV) - root.barHeight - (root.isFramed ? root.frameThickness : 0);
              calculatedY = (root.isFramed ? root.frameThickness : 0) + (availableHeight - panelHeight) / 2;
            } else {
              calculatedY = (root.height - panelHeight) / 2;
            }
          } else {
            calculatedY = (root.height - panelHeight) / 2;
          }
        } else if (root.panelAnchorTop) {
          if (root.effectivePanelAnchorTop) {
            calculatedY = root.barPosition === "top" ? topBarEdgeWithOverlap : (root.isFramed ? root.frameThickness - root.attachmentOverlap : 0);
          } else {
            var topBarOffset = (root.barPosition === "top") ? barOffset : 0;
            calculatedY = topBarOffset + effMarginT;
          }
        } else if (root.panelAnchorBottom) {
          if (root.effectivePanelAnchorBottom) {
            calculatedY = root.barPosition === "bottom" ? bottomBarEdgeWithOverlap - panelHeight : root.height - panelHeight - (root.isFramed ? root.frameThickness - root.attachmentOverlap : 0);
          } else {
            var bottomBarOffset = (root.barPosition === "bottom") ? barOffset : 0;
            calculatedY = root.height - panelHeight - bottomBarOffset - effMarginB;
          }
        } else {
          // No explicit vertical anchor
          if (root.barIsVertical) {
            if (panelContent.allowAttach) {
              var cornerInset = root.barFloating ? Style.radiusL * 2 : 0;
              var barTopEdge = (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginV) + cornerInset;
              var barBottomEdge = root.height - (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginV) - cornerInset;
              var centeredY = (root.height - panelHeight) / 2;
              calculatedY = Math.max(barTopEdge, Math.min(centeredY, barBottomEdge - panelHeight));
            } else {
              calculatedY = (root.height - panelHeight) / 2;
            }
          } else {
            // Horizontal bar, not attached
            if (root.barPosition === "top") {
              calculatedY = barOffset + effMarginT;
            } else if (root.barPosition === "bottom") {
              calculatedY = effMarginT;
            } else {
              calculatedY = effMarginT;
            }
          }
        }
      }
    }

    // Edge snapping for Y
    if (panelContent.allowAttach && !root.barFloating && root.height > 0 && panelHeight > 0) {
      var topEdgePos = root.barPosition === "top" ? topBarEdgeWithOverlap : (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginV);
      var bottomEdgePos = root.barPosition === "bottom" ? bottomBarEdgeWithOverlap - panelHeight : root.height - (root.isFramed ? root.frameThickness - root.attachmentOverlap : root.barMarginV) - panelHeight;

      // Only snap to top edge if panel is actually meant to be at top (or no explicit anchor)
      var shouldSnapToTop = root.effectivePanelAnchorTop || (!root.hasExplicitVerticalAnchor && root.barPosition === "top");
      // Only snap to bottom edge if panel is actually meant to be at bottom (or no explicit anchor)
      var shouldSnapToBottom = root.effectivePanelAnchorBottom || (!root.hasExplicitVerticalAnchor && root.barPosition === "bottom");

      if (shouldSnapToTop && Math.abs(calculatedY - topEdgePos) <= root.edgeSnapDistance) {
        calculatedY = topEdgePos;
      } else if (shouldSnapToBottom && Math.abs(calculatedY - bottomEdgePos) <= root.edgeSnapDistance) {
        calculatedY = bottomEdgePos;
      }
    }

    // Apply calculated positions (set targets for animation)
    panelBackground.targetX = calculatedX;
    panelBackground.targetY = calculatedY;

    // Logger.d("SmartPanel", "Position calculated:", calculatedX, calculatedY);
    // Logger.d("SmartPanel", "  Panel size:", panelWidth, "x", panelHeight);
    // Logger.d("SmartPanel", "  Parent size:", root.width, "x", root.height);
  }

  // Watch for changes in content-driven sizes and update position
  Connections {
    target: contentLoader.item
    ignoreUnknownSignals: true

    function onContentPreferredWidthChanged() {
      if (root.isPanelOpen && root.isPanelVisible) {
        root.setPosition();
      }
    }

    function onContentPreferredHeightChanged() {
      if (root.isPanelOpen && root.isPanelVisible) {
        root.setPosition();
      }
    }
  }

  // Opacity animation
  // Opening: fade in after size animation reaches 75%
  // Closing: fade out immediately
  opacity: {
    if (isClosing)
      return 0.0; // Fade out when closing
    if (isPanelVisible && sizeAnimationComplete)
      return 1.0; // Fade in when opening
    return 0.0;
  }

  Behavior on opacity {
    enabled: !PanelService.closedImmediately
    NumberAnimation {
      id: opacityAnimation
      duration: root.isClosing ? Style.animationFaster : Style.animationFast
      easing.type: Easing.OutQuad

      onRunningChanged: {
        // Safety: If animation didn't run (zero duration), handle immediately
        if (!running && duration === 0) {
          if (root.isClosing && root.opacity === 0.0) {
            root.opacityFadeComplete = true;
            var shouldFinalizeNow = panelContent.geometryPlaceholder && !panelContent.geometryPlaceholder.shouldAnimateWidth && !panelContent.geometryPlaceholder.shouldAnimateHeight;
            if (shouldFinalizeNow) {
              // Logger.d("SmartPanel", "Zero-duration opacity + no size animation - finalizing", root.objectName);
              Qt.callLater(root.finalizeClose);
            }
          } else if (root.isPanelVisible && root.opacity === 1.0) {
            // Open completed with zero duration
            root.openWatchdogActive = false;
            openWatchdogTimer.stop();
          }
          return;
        }

        // When opacity fade completes during close, trigger size animation
        if (!running && root.isClosing && root.opacity === 0.0) {
          root.opacityFadeComplete = true;
          // If no size animation will run (centered attached panels only), finalize immediately
          // Detached panels (allowAttach === false) should always animate from top
          var shouldFinalizeNow = panelContent.geometryPlaceholder && !panelContent.geometryPlaceholder.shouldAnimateWidth && !panelContent.geometryPlaceholder.shouldAnimateHeight;
          if (shouldFinalizeNow) {
            //Logger.d("SmartPanel", "No animation - finalizing immediately", root.objectName);
            Qt.callLater(root.finalizeClose);
          } else {
            //Logger.d("SmartPanel", "Animation will run - waiting for size animation", root.objectName, "shouldAnimateHeight:", panelContent.geometryPlaceholder.shouldAnimateHeight, "shouldAnimateWidth:", panelContent.geometryPlaceholder.shouldAnimateWidth);
          }
        } // When opacity fade completes during open, stop watchdog
        else if (!running && root.isPanelVisible && root.opacity === 1.0) {
          root.openWatchdogActive = false;
          openWatchdogTimer.stop();
        }
      }
    }
  }

  // Timer to trigger opacity fade at 50% of size animation
  Timer {
    id: opacityTrigger
    interval: Style.animationNormal * 0.5
    repeat: false
    onTriggered: {
      if (root.isPanelVisible) {
        root.sizeAnimationComplete = true;
      }
    }
  }

  // Watchdog timer for open sequence (safety mechanism)
  Timer {
    id: openWatchdogTimer
    interval: Style.animationNormal * 3 // 3x normal animation time
    repeat: false
    onTriggered: {
      if (root.openWatchdogActive) {
        Logger.w("SmartPanel", "Open watchdog timeout - forcing panel visible state", root.objectName);
        root.openWatchdogActive = false;
        // Force completion of open sequence
        if (root.isPanelOpen && !root.isPanelVisible) {
          root.isPanelVisible = true;
          root.sizeAnimationComplete = true;
        }
      }
    }
  }

  // Watchdog timer for close sequence (safety mechanism)
  Timer {
    id: closeWatchdogTimer
    interval: Style.animationFast * 3 // 3x fast animation time
    repeat: false
    onTriggered: {
      if (root.closeWatchdogActive && !root.closeFinalized) {
        Logger.w("SmartPanel", "Close watchdog timeout - forcing panel close", root.objectName);
        // Force finalization
        Qt.callLater(root.finalizeClose);
      }
    }
  }

  // ------------------------------------------------
  // Panel Content
  Item {
    id: panelContent
    anchors.fill: parent

    // Screen-dependent attachment properties
    // Allow panel content to override allowAttach (e.g., plugin panels)
    readonly property bool allowAttach: {
      if (contentLoader.item && contentLoader.item.allowAttach !== undefined) {
        return contentLoader.item.allowAttach;
      }
      return Settings.data.ui.panelsAttachedToBar || root.forceAttachToBar;
    }
    readonly property bool allowAttachToBar: {
      if (!(Settings.data.ui.panelsAttachedToBar || root.forceAttachToBar)) {
        return false;
      }

      // A panel can only be attached to a bar if there is a bar on that screen
      var monitors = Settings.data.bar.monitors || [];
      var result = monitors.length === 0 || monitors.includes(root.screen?.name || "");
      return result;
    }

    // Edge detection - detect if panel is touching screen edges
    readonly property bool touchingLeftEdge: allowAttach && panelBackground.x <= (isFramed ? frameThickness + 1 : 1)
    readonly property bool touchingRightEdge: allowAttach && (panelBackground.x + panelBackground.width) >= (root.width - (isFramed ? frameThickness + 1 : 1))
    readonly property bool touchingTopEdge: allowAttach && panelBackground.y <= (isFramed ? frameThickness + 1 : 1)
    readonly property bool touchingBottomEdge: allowAttach && (panelBackground.y + panelBackground.height) >= (root.height - (isFramed ? frameThickness + 1 : 1))

    // Bar edge detection - detect if panel is touching bar edges (for cases where centered panels snap to bar due to height constraints)
    readonly property bool touchingTopBar: allowAttachToBar && root.barPosition === "top" && !root.barIsVertical && Math.abs(panelBackground.y - ((isFramed ? 0 : root.barMarginV) + root.barHeight)) <= 1
    readonly property bool touchingBottomBar: allowAttachToBar && root.barPosition === "bottom" && !root.barIsVertical && Math.abs((panelBackground.y + panelBackground.height) - (root.height - (isFramed ? 0 : root.barMarginV) - root.barHeight)) <= 1
    readonly property bool touchingLeftBar: allowAttachToBar && root.barPosition === "left" && root.barIsVertical && Math.abs(panelBackground.x - ((isFramed ? 0 : root.barMarginH) + root.barHeight)) <= 1
    readonly property bool touchingRightBar: allowAttachToBar && root.barPosition === "right" && root.barIsVertical && Math.abs((panelBackground.x + panelBackground.width) - (root.width - (isFramed ? 0 : root.barMarginH) - root.barHeight)) <= 1

    // Expose panelBackground for geometry placeholder
    property alias geometryPlaceholder: panelBackground

    // The actual panel background - provides geometry for PanelBackground rendering
    Item {
      id: panelBackground

      // Expose self as panelItem for PanelBackground compatibility
      readonly property var panelItem: panelBackground

      // Store target dimensions (Initialize to 0, set by setPosition())
      property real targetWidth: 0
      property real targetHeight: 0
      property real targetX: root.x
      property real targetY: root.y

      // Track whether dimensions have been initialized (to prevent initial changes from animating)
      property bool dimensionsInitialized: false

      property var bezierCurve: [0.05, 0, 0.133, 0.06, 0.166, 0.4, 0.208, 0.82, 0.25, 1, 1, 1]

      // Determine which edges the panel is closest to for animation direction
      // Use target position (not animated position) to avoid binding loops
      readonly property bool willTouchTopBar: {
        if (!panelContent.allowAttachToBar || root.barPosition !== "top" || root.barIsVertical)
          return false;
        var targetTopBarY = (isFramed ? 0 : root.barMarginV) + root.barHeight;
        return Math.abs(panelBackground.targetY - targetTopBarY) <= 1;
      }
      readonly property bool willTouchBottomBar: {
        if (!panelContent.allowAttachToBar || root.barPosition !== "bottom" || root.barIsVertical)
          return false;
        var targetBottomBarY = root.height - (isFramed ? 0 : root.barMarginV) - root.barHeight - panelBackground.targetHeight;
        return Math.abs(panelBackground.targetY - targetBottomBarY) <= 1;
      }
      readonly property bool willTouchLeftBar: {
        if (!panelContent.allowAttachToBar || root.barPosition !== "left" || !root.barIsVertical)
          return false;
        var targetLeftBarX = (isFramed ? 0 : root.barMarginH) + root.barHeight;
        return Math.abs(panelBackground.targetX - targetLeftBarX) <= 1;
      }
      readonly property bool willTouchRightBar: {
        if (!panelContent.allowAttachToBar || root.barPosition !== "right" || !root.barIsVertical)
          return false;
        var targetRightBarX = root.width - (isFramed ? 0 : root.barMarginH) - root.barHeight - panelBackground.targetWidth;
        return Math.abs(panelBackground.targetX - targetRightBarX) <= 1;
      }
      readonly property bool willTouchTopEdge: panelContent.allowAttach && panelBackground.targetY <= (isFramed ? frameThickness + 1 : 1)
      readonly property bool willTouchBottomEdge: panelContent.allowAttach && (panelBackground.targetY + panelBackground.targetHeight) >= (root.height - (isFramed ? frameThickness + 1 : 1))
      readonly property bool willTouchLeftEdge: panelContent.allowAttach && panelBackground.targetX <= (isFramed ? frameThickness + 1 : 1)
      readonly property bool willTouchRightEdge: panelContent.allowAttach && (panelBackground.targetX + panelBackground.targetWidth) >= (root.width - (isFramed ? frameThickness + 1 : 1))

      readonly property bool isActuallyAttachedToAnyEdge: {
        return willTouchTopBar || willTouchBottomBar || willTouchLeftBar || willTouchRightBar || willTouchTopEdge || willTouchBottomEdge || willTouchLeftEdge || willTouchRightEdge;
      }

      readonly property bool animateFromTop: {
        // Non-attached panels always roll down from top
        // Check both the setting and whether panel actually touches any edge
        if (!panelContent.allowAttach || !isActuallyAttachedToAnyEdge) {
          return true;
        }
        // When panel is opening, use effective anchors and calculated positions
        if (!root.isPanelVisible) {
          // Attached to horizontal bar at top
          if (panelContent.allowAttachToBar && root.effectivePanelAnchorTop && !root.barIsVertical) {
            return true;
          }
          // Attached to vertical bar (left/right) - don't animate from top
          // Panels attach to bar if they have allowAttach (with or without explicit anchor)
          var attachedToVerticalBar = panelContent.allowAttachToBar && root.barIsVertical && ((root.effectivePanelAnchorLeft && root.barPosition === "left") || (root.effectivePanelAnchorRight && root.barPosition === "right"));
          if (attachedToVerticalBar) {
            return false;
          }
          // Panel touching left/right/bottom screen edge - animate from that edge instead
          var touchingNonTopEdge = (willTouchLeftEdge || willTouchRightEdge || willTouchBottomEdge) && !willTouchTopBar && !willTouchBottomBar && !willTouchLeftBar && !willTouchRightBar;
          if (touchingNonTopEdge) {
            return false;
          }
          // Panel touching top screen edge (not bar)
          if (willTouchTopEdge && !willTouchTopBar && !willTouchBottomBar && !willTouchLeftBar && !willTouchRightBar) {
            return true;
          }
          // Panel anchored to left/right/bottom edge - animate from that edge instead
          if (root.panelAnchorLeft || root.panelAnchorRight || root.panelAnchorBottom) {
            return false;
          }
          // Attached to top edge
          if (panelContent.allowAttach && root.panelAnchorTop) {
            return true;
          }
          // Default: animate from top (for floating panels with no explicit anchors)
          return true;
        }
        // Panel is visible - use calculated positions
        if (willTouchTopBar) {
          return true;
        }
        if (willTouchTopEdge && !willTouchTopBar && !willTouchBottomBar && !willTouchLeftBar && !willTouchRightBar) {
          return true;
        }
        if (!isActuallyAttachedToAnyEdge) {
          return true;
        }
        return false;
      }
      readonly property bool animateFromBottom: {
        // Non-attached panels always roll down from top, not bottom
        if (!panelContent.allowAttach || !isActuallyAttachedToAnyEdge) {
          return false;
        }
        if (!root.isPanelVisible) {
          // Attached to horizontal bar at bottom
          if (panelContent.allowAttachToBar && root.effectivePanelAnchorBottom && !root.barIsVertical) {
            return true;
          }
          // Attached to vertical bar (left/right) - don't animate from bottom
          var attachedToVerticalBar = panelContent.allowAttachToBar && root.barIsVertical && ((root.effectivePanelAnchorLeft && root.barPosition === "left") || (root.effectivePanelAnchorRight && root.barPosition === "right"));
          if (attachedToVerticalBar) {
            return false;
          }
          // Panel touching bottom screen edge (not bar)
          if (willTouchBottomEdge && !willTouchTopBar && !willTouchBottomBar && !willTouchLeftBar && !willTouchRightBar) {
            return true;
          }
          // Panel anchored to top/left/right edge - don't animate from bottom
          if (root.panelAnchorTop || root.panelAnchorLeft || root.panelAnchorRight) {
            return false;
          }
          // Attached to bottom edge (when bar is vertical, panel can still be anchored to bottom)
          if (panelContent.allowAttach && root.panelAnchorBottom) {
            return true;
          }
          return false;
        }
        if (willTouchBottomBar) {
          return true;
        }
        if (willTouchBottomEdge && !willTouchTopBar && !willTouchBottomBar && !willTouchLeftBar && !willTouchRightBar) {
          return true;
        }
        return false;
      }
      readonly property bool animateFromLeft: {
        // Non-attached panels always roll down from top, not left
        if (!panelContent.allowAttach || !isActuallyAttachedToAnyEdge) {
          return false;
        }
        if (!root.isPanelVisible) {
          // Attached to vertical bar on left - must verify bar is actually on left
          if (panelContent.allowAttachToBar && root.effectivePanelAnchorLeft && root.barIsVertical && root.barPosition === "left") {
            return true;
          }
          // Panel touching left screen edge (not bar)
          if (willTouchLeftEdge && !willTouchTopBar && !willTouchBottomBar && !willTouchLeftBar && !willTouchRightBar) {
            return true;
          }
          // Panel anchored to left edge - animate from left
          // Takes precedence over top/bottom when bar is vertical
          if (root.panelAnchorLeft) {
            return true;
          }
          return false;
        }
        if (willTouchTopBar || willTouchBottomBar) {
          return false;
        }
        if (willTouchLeftBar) {
          return true;
        }
        if (willTouchTopEdge || willTouchBottomEdge) {
          return false;
        }
        if (willTouchLeftEdge && !willTouchLeftBar && !willTouchTopBar && !willTouchBottomBar && !willTouchRightBar) {
          return true;
        }
        return false;
      }
      readonly property bool animateFromRight: {
        // Non-attached panels always roll down from top, not right
        if (!panelContent.allowAttach || !isActuallyAttachedToAnyEdge) {
          return false;
        }
        if (!root.isPanelVisible) {
          // Attached to vertical bar on right - must verify bar is actually on right
          if (panelContent.allowAttachToBar && root.effectivePanelAnchorRight && root.barIsVertical && root.barPosition === "right") {
            return true;
          }
          // Panel touching right screen edge (not bar)
          if (willTouchRightEdge && !willTouchTopBar && !willTouchBottomBar && !willTouchLeftBar && !willTouchRightBar) {
            return true;
          }
          // Panel anchored to right edge - animate from right
          // Takes precedence over top/bottom when bar is vertical
          if (root.panelAnchorRight) {
            return true;
          }
          return false;
        }
        if (willTouchTopBar || willTouchBottomBar) {
          return false;
        }
        if (willTouchRightBar) {
          return true;
        }
        if (willTouchTopEdge || willTouchBottomEdge) {
          return false;
        }
        if (willTouchRightEdge && !willTouchLeftBar && !willTouchTopBar && !willTouchBottomBar && !willTouchRightBar) {
          return true;
        }
        return false;
      }

      // Determine animation axis based on which edge is closest
      // Priority: horizontal edges (top/bottom) take precedence over vertical edges (left/right)
      // This prevents diagonal animations when panel is attached to a corner
      // Use reactive values here - they're evaluated BEFORE isPanelVisible becomes true
      readonly property bool shouldAnimateWidth: !shouldAnimateHeight && (animateFromLeft || animateFromRight)
      readonly property bool shouldAnimateHeight: animateFromTop || animateFromBottom

      // Current animated width/height (referenced by x/y for right/bottom positioning)
      readonly property real currentWidth: {
        if (isClosing && opacityFadeComplete && shouldAnimateWidth)
          return 0;
        if (isClosing || isPanelVisible)
          return targetWidth;
        // If not animating width, start at target (no visual change)
        // If animating width, start at 0 (will animate to target)
        return shouldAnimateWidth ? 0 : targetWidth;
      }
      readonly property real currentHeight: {
        if (isClosing && opacityFadeComplete && shouldAnimateHeight)
          return 0;
        if (isClosing || isPanelVisible)
          return targetHeight;
        // If not animating height, start at target (no visual change)
        // If animating height, start at 0 (will animate to target)
        return shouldAnimateHeight ? 0 : targetHeight;
      }

      width: currentWidth
      height: currentHeight

      x: {
        // Offset x to make panel grow/shrink from the appropriate edge
        // Use CACHED values to prevent recalculation during animation
        if (root.cachedAnimateFromRight && root.cachedShouldAnimateWidth) {
          // Keep the RIGHT edge fixed at its target position
          var targetRightEdge = targetX + targetWidth;
          return targetRightEdge - width;
        }
        return targetX;
      }
      y: {
        // Offset y to make panel grow/shrink from the appropriate edge
        // Use CACHED values to prevent recalculation during animation
        if (root.cachedAnimateFromBottom && root.cachedShouldAnimateHeight) {
          // Keep the BOTTOM edge fixed at its target position
          var targetBottomEdge = targetY + targetHeight;
          return targetBottomEdge - height;
        }
        return targetY;
      }

      Behavior on width {
        enabled: !PanelService.closedImmediately
        NumberAnimation {
          id: widthAnimation
          // Use 0ms if dimensions not initialized to prevent initial changes from animating
          // During opening: use 0ms if not animating width, otherwise use normal duration
          // During closing: use 0ms if not animating width, otherwise use fast duration
          // During normal content resizing: always use normal duration
          duration: !panelBackground.dimensionsInitialized ? 0 : (root.isOpening && !panelBackground.shouldAnimateWidth) ? 0 : root.isOpening ? Style.animationNormal : (root.isClosing && !panelBackground.shouldAnimateWidth) ? 0 : root.isClosing ? Style.animationFast : Style.animationNormal
          easing.type: Easing.BezierSpline
          easing.bezierCurve: panelBackground.bezierCurve

          onRunningChanged: {
            // Safety: Zero-duration animation handling
            if (!running && duration === 0) {
              if (root.isClosing && panelBackground.width === 0 && panelBackground.shouldAnimateWidth) {
                Logger.d("SmartPanel", "Zero-duration width animation - finalizing", root.objectName);
                Qt.callLater(root.finalizeClose);
              }
              return;
            }

            // When width shrink completes during close, finalize
            if (!running && root.isClosing && panelBackground.width === 0 && panelBackground.shouldAnimateWidth) {
              Qt.callLater(root.finalizeClose);
            }
          }
        }
      }

      Behavior on height {
        enabled: !PanelService.closedImmediately
        NumberAnimation {
          id: heightAnimation
          // Use 0ms if dimensions not initialized to prevent initial changes from animating
          // During opening: use 0ms if not animating height, otherwise use normal duration
          // During closing: use 0ms if not animating height, otherwise use fast duration
          // During normal content resizing: always use normal duration
          duration: !panelBackground.dimensionsInitialized ? 0 : (root.isOpening && !panelBackground.shouldAnimateHeight) ? 0 : root.isOpening ? Style.animationNormal : (root.isClosing && !panelBackground.shouldAnimateHeight) ? 0 : root.isClosing ? Style.animationFast : Style.animationNormal
          easing.type: Easing.BezierSpline
          easing.bezierCurve: panelBackground.bezierCurve

          onRunningChanged: {
            // Safety: Zero-duration animation handling
            if (!running && duration === 0) {
              if (root.isClosing && panelBackground.height === 0 && panelBackground.shouldAnimateHeight) {
                Logger.d("SmartPanel", "Zero-duration height animation - finalizing", root.objectName);
                Qt.callLater(root.finalizeClose);
              }
              return;
            }

            // When height shrink completes during close, finalize
            if (!running && root.isClosing && panelBackground.height === 0 && panelBackground.shouldAnimateHeight) {
              Qt.callLater(root.finalizeClose);
            }
          }
        }
      }

      // Corner states for PanelBackground to read
      // State -1: No radius (flat/square corner)
      // State 0: Normal (inner curve)
      // State 1: Horizontal inversion (outer curve on X-axis)
      // State 2: Vertical inversion (outer curve on Y-axis)

      // Smart corner state calculation based on bar attachment and edge touching
      property int topLeftCornerState: {
        // If bar is not visible, don't show outer corners based on bar attachment
        if (!root.barShouldShow) {
          // Only check edge touching, not bar touching
          var edgeInverted = panelContent.allowAttach && (panelContent.touchingLeftEdge || panelContent.touchingTopEdge);
          if (edgeInverted) {
            if (panelContent.touchingLeftEdge && panelContent.touchingTopEdge)
              return 0; // Both edges: no inversion (normal rounded corner)
            if (panelContent.touchingLeftEdge)
              return 2; // Left edge: vertical inversion
            if (panelContent.touchingTopEdge)
              return 1; // Top edge: horizontal inversion
          }
          return 0;
        }

        var barTouchInverted = panelContent.touchingTopBar || panelContent.touchingLeftBar;
        // Invert if touching either edge that forms this corner (left OR top), regardless of bar position
        var edgeInverted = panelContent.allowAttach && (panelContent.touchingLeftEdge || panelContent.touchingTopEdge);

        if (barTouchInverted || edgeInverted) {
          // Determine inversion direction based on which edge is touched
          if (panelContent.touchingLeftEdge && panelContent.touchingTopEdge)
            return 0; // Both edges: no inversion (normal rounded corner)
          if (panelContent.touchingLeftEdge)
            return 2; // Left edge: vertical inversion
          if (panelContent.touchingTopEdge)
            return 1; // Top edge: horizontal inversion
          return root.barIsVertical ? 2 : 1;
        }
        return 0;
      }

      property int topRightCornerState: {
        // If bar is not visible, don't show outer corners based on bar attachment
        if (!root.barShouldShow) {
          // Only check edge touching, not bar touching
          var edgeInverted = panelContent.allowAttach && (panelContent.touchingRightEdge || panelContent.touchingTopEdge);
          if (edgeInverted) {
            if (panelContent.touchingRightEdge && panelContent.touchingTopEdge)
              return 0; // Both edges: no inversion (normal rounded corner)
            if (panelContent.touchingRightEdge)
              return 2; // Right edge: vertical inversion
            if (panelContent.touchingTopEdge)
              return 1; // Top edge: horizontal inversion
          }
          return 0;
        }

        var barTouchInverted = panelContent.touchingTopBar || panelContent.touchingRightBar;
        // Invert if touching either edge that forms this corner (right OR top), regardless of bar position
        var edgeInverted = panelContent.allowAttach && (panelContent.touchingRightEdge || panelContent.touchingTopEdge);

        if (barTouchInverted || edgeInverted) {
          // Determine inversion direction based on which edge is touched
          if (panelContent.touchingRightEdge && panelContent.touchingTopEdge)
            return 0; // Both edges: no inversion (normal rounded corner)
          if (panelContent.touchingRightEdge)
            return 2; // Right edge: vertical inversion
          if (panelContent.touchingTopEdge)
            return 1; // Top edge: horizontal inversion
          return root.barIsVertical ? 2 : 1;
        }
        return 0;
      }

      property int bottomLeftCornerState: {
        // If bar is not visible, don't show outer corners based on bar attachment
        if (!root.barShouldShow) {
          // Only check edge touching, not bar touching
          var edgeInverted = panelContent.allowAttach && (panelContent.touchingLeftEdge || panelContent.touchingBottomEdge);
          if (edgeInverted) {
            if (panelContent.touchingLeftEdge && panelContent.touchingBottomEdge)
              return 0; // Both edges: no inversion (normal rounded corner)
            if (panelContent.touchingLeftEdge)
              return 2; // Left edge: vertical inversion
            if (panelContent.touchingBottomEdge)
              return 1; // Bottom edge: horizontal inversion
          }
          return 0;
        }

        var barTouchInverted = panelContent.touchingBottomBar || panelContent.touchingLeftBar;
        // Invert if touching either edge that forms this corner (left OR bottom), regardless of bar position
        var edgeInverted = panelContent.allowAttach && (panelContent.touchingLeftEdge || panelContent.touchingBottomEdge);

        if (barTouchInverted || edgeInverted) {
          // Determine inversion direction based on which edge is touched
          if (panelContent.touchingLeftEdge && panelContent.touchingBottomEdge)
            return 0; // Both edges: no inversion (normal rounded corner)
          if (panelContent.touchingLeftEdge)
            return 2; // Left edge: vertical inversion
          if (panelContent.touchingBottomEdge)
            return 1; // Bottom edge: horizontal inversion
          return root.barIsVertical ? 2 : 1;
        }
        return 0;
      }

      property int bottomRightCornerState: {
        // If bar is not visible, don't show outer corners based on bar attachment
        if (!root.barShouldShow) {
          // Only check edge touching, not bar touching
          var edgeInverted = panelContent.allowAttach && (panelContent.touchingRightEdge || panelContent.touchingBottomEdge);
          if (edgeInverted) {
            if (panelContent.touchingRightEdge && panelContent.touchingBottomEdge)
              return 0; // Both edges: no inversion (normal rounded corner)
            if (panelContent.touchingRightEdge)
              return 2; // Right edge: vertical inversion
            if (panelContent.touchingBottomEdge)
              return 1; // Bottom edge: horizontal inversion
          }
          return 0;
        }

        var barTouchInverted = panelContent.touchingBottomBar || panelContent.touchingRightBar;
        // Invert if touching either edge that forms this corner (right OR bottom), regardless of bar position
        var edgeInverted = panelContent.allowAttach && (panelContent.touchingRightEdge || panelContent.touchingBottomEdge);

        if (barTouchInverted || edgeInverted) {
          // Determine inversion direction based on which edge is touched
          if (panelContent.touchingRightEdge && panelContent.touchingBottomEdge)
            return 0; // Both edges: no inversion (normal rounded corner)
          if (panelContent.touchingRightEdge)
            return 2; // Right edge: vertical inversion
          if (panelContent.touchingBottomEdge)
            return 1; // Bottom edge: horizontal inversion
          return root.barIsVertical ? 2 : 1;
        }
        return 0;
      }

      // MouseArea to catch clicks on the panel and prevent them from reaching the background
      // This prevents closing the panel when clicking inside it
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        z: -1 // Behind content, but on the panel background
        onClicked: mouse => {
                     mouse.accepted = true; // Accept and ignore - prevents propagation to background
                   }
      }
    }

    // Panel top content: Text, icons, etc...
    Loader {
      id: contentLoader
      active: isPanelOpen
      x: panelBackground.x
      y: panelBackground.y
      width: panelBackground.width
      height: panelBackground.height
      sourceComponent: root.panelContent

      onLoaded: {
        // Wait for contentPreferredWidth/Height to be available before making visible
        Qt.callLater(function () {
          // Calculate position with stable contentPreferredWidth/Height values
          setPosition();

          // Mark dimensions as initialized to enable animations
          panelBackground.dimensionsInitialized = true;

          // Cache animation direction BEFORE isPanelVisible becomes true
          // This locks in the direction for the entire open/close cycle
          root.cachedAnimateFromTop = panelBackground.animateFromTop;
          root.cachedAnimateFromBottom = panelBackground.animateFromBottom;
          root.cachedAnimateFromLeft = panelBackground.animateFromLeft;
          root.cachedAnimateFromRight = panelBackground.animateFromRight;
          root.cachedShouldAnimateWidth = panelBackground.shouldAnimateWidth;
          root.cachedShouldAnimateHeight = panelBackground.shouldAnimateHeight;

          // Make panel visible, now only the intended dimension will animate
          root.isPanelVisible = true;
          opacityTrigger.start();

          // Start open watchdog timer
          root.openWatchdogActive = true;
          openWatchdogTimer.start();

          opened();
        });
      }
    }
  }

  Component.onCompleted: {
    PanelService.registerPanel(root);
  }
}
