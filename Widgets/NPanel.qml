import QtQuick
import Quickshell
import qs.Commons
import qs.Services


/**
 * NPanel for use within NFullScreenWindow
 */
Item {
  id: root

  // Screen property provided by NFullScreenWindow
  property ShellScreen screen: null

  // Edge snapping: if panel is within this distance (in pixels) from a screen edge, snap
  property real edgeSnapDistance: 50

  property Component panelContent: null

  // Panel size properties
  property real preferredWidth: 700
  property real preferredHeight: 900
  property real preferredWidthRatio
  property real preferredHeightRatio
  property color panelBackgroundColor: Color.mSurface
  property color panelBorderColor: Color.mOutline
  property var buttonItem: null

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

  // Track whether panel is open
  property bool isPanelOpen: false

  // Animation properties
  property real animationProgress: 0
  property bool isClosing: false

  // Keyboard event handlers - override these in specific panels to handle shortcuts
  // These are called from NFullScreenWindow's centralized shortcuts
  function onEscapePressed() {
    close()
  }
  function onTabPressed() {}
  function onShiftTabPressed() {}
  function onUpPressed() {}
  function onDownPressed() {}
  function onLeftPressed() {}
  function onRightPressed() {}
  function onReturnPressed() {}
  function onHomePressed() {}
  function onEndPressed() {}
  function onPageUpPressed() {}
  function onPageDownPressed() {}
  function onCtrlJPressed() {}
  function onCtrlKPressed() {}

  Behavior on animationProgress {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutQuint
      onRunningChanged: {
        // When close animation finishes, actually hide the panel
        if (!running && root.isClosing) {
          root.isClosing = false
          root.isPanelOpen = false
        }
      }
    }
  }

  // Expose panel region for click-through mask (only when open)
  readonly property var panelRegion: panelContentContainer.item?.maskRegion || null

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property bool barFloating: Settings.data.bar.floating || false
  readonly property real barMarginH: barFloating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0
  readonly property real barMarginV: barFloating ? Settings.data.bar.marginVertical * Style.marginXL : 0

  // Helper to detect if any anchor is explicitly set
  readonly property bool hasExplicitHorizontalAnchor: panelAnchorHorizontalCenter || panelAnchorLeft || panelAnchorRight
  readonly property bool hasExplicitVerticalAnchor: panelAnchorVerticalCenter || panelAnchorTop || panelAnchorBottom

  signal opened
  signal closed

  // Panel visibility and sizing
  // Keep visible during close animation
  visible: isPanelOpen || isClosing
  width: parent ? parent.width : 0
  height: parent ? parent.height : 0

  // Panel control functions
  function toggle(buttonItem, buttonName) {
    if (!isPanelOpen) {
      open(buttonItem, buttonName)
    } else {
      close()
    }
  }

  function open(buttonItem, buttonName) {
    if (!buttonItem && buttonName) {
      buttonItem = BarService.lookupWidget(buttonName, screen.name)
    }

    if (buttonItem) {
      root.buttonItem = buttonItem
      // Map button position to screen coordinates
      var buttonPos = buttonItem.mapToItem(null, 0, 0)
      root.buttonPosition = Qt.point(buttonPos.x, buttonPos.y)
      root.buttonWidth = buttonItem.width
      root.buttonHeight = buttonItem.height
      root.useButtonPosition = true
    } else {
      // No button provided: reset button position mode
      root.buttonItem = null
      root.useButtonPosition = false
    }

    setPosition()
    isPanelOpen = true
    animationProgress = 1

    // Notify PanelService
    PanelService.willOpenPanel(root)

    // Delay the opened signal to ensure content is fully loaded
    // This ensures Component.onCompleted of the loaded content runs first
    Qt.callLater(() => {
                   opened()
                 })

    Logger.d("NPanel", "Opened panel", objectName)
    Logger.d("NPanel", "  Root size:", width, "x", height)
  }

  function close() {
    // Start close animation
    isClosing = true
    animationProgress = 0

    // Notify PanelService immediately
    PanelService.closedPanel(root)

    // Emit closed signal
    closed()

    Logger.d("NPanel", "Closing panel with animation", objectName)
    // isPanelOpen will be set to false when animation completes
  }

  function setPosition() {// Position calculation will be handled here
    // For now, panels will be positioned based on anchors
  }

  // Loader for panel content
  Loader {
    id: panelContentContainer
    anchors.fill: parent
    // Keep active during close animation
    active: root.isPanelOpen || root.isClosing
    asynchronous: false

    sourceComponent: Item {
      anchors.fill: parent

      // Screen-dependent attachment properties (moved from root to avoid race condition)
      // By the time this Loader is active, screen has been assigned by NFullScreenWindow
      readonly property bool couldAttach: Settings.data.ui.panelsAttachedToBar
      readonly property bool couldAttachToBar: {
        if (!Settings.data.ui.panelsAttachedToBar || Settings.data.bar.backgroundOpacity < 1.0) {
          return false
        }

        // A panel can only be attached to a bar if there is a bar on that screen
        var monitors = Settings.data.bar.monitors || []
        var result = monitors.length === 0 || monitors.includes(root.screen?.name || "")
        return result
      }

      // Effective anchor properties (moved from root, depend on couldAttach)
      // These are true when:
      // 1. Explicitly anchored, OR
      // 2. Using button position and bar is on that edge, OR
      // 3. Attached to bar with no explicit anchors (default centering behavior)
      readonly property bool effectivePanelAnchorTop: root.panelAnchorTop || (root.useButtonPosition && root.barPosition === "top") || (couldAttach && !root.hasExplicitVerticalAnchor && root.barPosition === "top" && !root.barIsVertical)
      readonly property bool effectivePanelAnchorBottom: root.panelAnchorBottom || (root.useButtonPosition && root.barPosition === "bottom") || (couldAttach && !root.hasExplicitVerticalAnchor && root.barPosition === "bottom" && !root.barIsVertical)
      readonly property bool effectivePanelAnchorLeft: root.panelAnchorLeft || (root.useButtonPosition && root.barPosition === "left") || (couldAttach && !root.hasExplicitHorizontalAnchor && root.barPosition === "left" && root.barIsVertical)
      readonly property bool effectivePanelAnchorRight: root.panelAnchorRight || (root.useButtonPosition && root.barPosition === "right") || (couldAttach && !root.hasExplicitHorizontalAnchor && root.barPosition === "right" && root.barIsVertical)

      // Expose panelBackground for mask region
      property alias maskRegion: panelBackground

      // The actual panel background and content
      Item {
        anchors.fill: parent

        NShapedRectangle {
          id: panelBackground

          backgroundColor: root.panelBackgroundColor

          Behavior on backgroundColor {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutQuad
            }
          }

          Behavior on width {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutQuad
            }
          }
          Behavior on height {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutQuad
            }
          }

          // Check if panel has any inverted corners
          readonly property bool hasInvertedCorners: topLeftInverted || topRightInverted || bottomLeftInverted || bottomRightInverted

          // Determine panel attachment type for animation
          readonly property bool isAttachedToFloatingBar: hasInvertedCorners && root.barFloating && couldAttach
          readonly property bool isAttachedToNonFloating: hasInvertedCorners && (!root.barFloating || !couldAttach)
          readonly property bool isDetached: !hasInvertedCorners

          // Determine closest screen edge to slide from (for full slide animation)
          readonly property string slideDirection: {
            if (!isAttachedToNonFloating)
              return "none"

            // Priority: If panel is touching the bar (but not touching any screen edge), slide from the bar direction
            // This handles cases where centered panels snap to the bar due to height constraints
            // If touching screen edges, fall through to the distance-based calculation below
            // var touchingAnyScreenEdge = touchingLeftEdge || touchingRightEdge || touchingTopEdge || touchingBottomEdge
            // if (!touchingAnyScreenEdge) {
            if (touchingTopBar && root.barPosition === "top")
              return "top"
            if (touchingBottomBar && root.barPosition === "bottom")
              return "bottom"
            if (touchingLeftBar && root.barPosition === "left")
              return "left"
            if (touchingRightBar && root.barPosition === "right")
              return "right"
            //}

            // Use panel's center point (barycenter) as reference
            var centerX = x + width / 2
            var centerY = y + height / 2

            // Calculate actual travel distances (barycenter to screen edge)
            var travelFromTop = centerY
            var travelFromBottom = parent.height - centerY
            var travelFromLeft = centerX
            var travelFromRight = parent.width - centerX

            // Find minimum travel distance
            var minTravel = Math.min(travelFromTop, travelFromBottom, travelFromLeft, travelFromRight)

            // Return the direction with least travel distance
            if (minTravel === travelFromTop)
              return "top"
            if (minTravel === travelFromBottom)
              return "bottom"
            if (minTravel === travelFromLeft)
              return "left"
            if (minTravel === travelFromRight)
              return "right"
            return "none"
          }

          // Animation offset calculation
          readonly property real slideOffset: {
            // Full slide for non-floating attached panels
            if (isAttachedToNonFloating) {
              var distance = (slideDirection === "left" || slideDirection === "right") ? width : height
              return Math.round((1 - root.animationProgress) * distance)
            }
            // Small 40px slide for floating bar attached panels
            if (isAttachedToFloatingBar) {
              return (1 - root.animationProgress) * 40
            }
            // No slide for detached panels
            return 0
          }

          // Animation properties
          opacity: isAttachedToNonFloating ? Math.min(1, root.animationProgress * 5) : root.animationProgress
          scale: {
            if (isAttachedToNonFloating)
              return 1 // No scale for full slide animation
            if (isAttachedToFloatingBar)
              return 1 // No scale for floating bar (40px slide + opacity only)
            return (0.9 + root.animationProgress * 0.1) // Scale for detached panels
          }

          // Transform origin for scale animation
          transformOrigin: Item.Center

          // Slide animation using transform
          transform: Translate {
            x: {
              // Full slide from nearest edge for non-floating attached panels
              if (panelBackground.isAttachedToNonFloating) {
                if (panelBackground.slideDirection === "left")
                  return -panelBackground.slideOffset
                if (panelBackground.slideDirection === "right")
                  return panelBackground.slideOffset
                return 0
              }
              // Small 40px slide from bar for floating bar attached panels
              if (panelBackground.isAttachedToFloatingBar) {
                if (root.barPosition === "left")
                  return -panelBackground.slideOffset
                if (root.barPosition === "right")
                  return panelBackground.slideOffset
              }
              return 0
            }
            y: {
              // Full slide from nearest edge for non-floating attached panels
              if (panelBackground.isAttachedToNonFloating) {
                if (panelBackground.slideDirection === "top")
                  return -panelBackground.slideOffset
                if (panelBackground.slideDirection === "bottom")
                  return panelBackground.slideOffset
                return 0
              }
              // Small 40px slide from bar for floating bar attached panels
              if (panelBackground.isAttachedToFloatingBar) {
                if (root.barPosition === "top")
                  return -panelBackground.slideOffset
                if (root.barPosition === "bottom")
                  return panelBackground.slideOffset
              }
              return 0
            }
          }

          topLeftRadius: Style.radiusL
          topRightRadius: Style.radiusL
          bottomLeftRadius: Style.radiusL
          bottomRightRadius: Style.radiusL

          // Inverted corners based on bar attachment
          // When attached to bar AND effectively anchored to it, the corner(s) touching the bar should be inverted
          // Also invert corners when touching screen edges (non-floating bar only)
          topLeftInverted: {
            // Bar attachment: only attach to bar if bar opacity >= 1.0 (no color clash)
            var barInverted = couldAttachToBar && ((root.barPosition === "top" && !root.barIsVertical && effectivePanelAnchorTop) || (root.barPosition === "left" && root.barIsVertical && effectivePanelAnchorLeft))
            // Also detect when panel touches bar edge (e.g., centered panel that's too tall)
            var barTouchInverted = touchingTopBar || touchingLeftBar
            // Screen edge contact: can attach to screen edges even if bar opacity < 1.0
            // For horizontal bars: invert when touching left/right edges
            // For vertical bars: invert when touching top/bottom edges
            var edgeInverted = couldAttach && ((touchingLeftEdge && !root.barIsVertical) || (touchingTopEdge && root.barIsVertical))
            // Also invert when touching screen edge opposite to bar (e.g., bottom edge when bar is at top)
            var oppositeEdgeInverted = couldAttach && (touchingTopEdge && !root.barIsVertical && root.barPosition !== "top")
            return barInverted || barTouchInverted || edgeInverted || oppositeEdgeInverted
          }
          topRightInverted: {
            var barInverted = couldAttachToBar && ((root.barPosition === "top" && !root.barIsVertical && effectivePanelAnchorTop) || (root.barPosition === "right" && root.barIsVertical && effectivePanelAnchorRight))
            var barTouchInverted = touchingTopBar || touchingRightBar
            var edgeInverted = couldAttach && ((touchingRightEdge && !root.barIsVertical) || (touchingTopEdge && root.barIsVertical))
            var oppositeEdgeInverted = couldAttach && (touchingTopEdge && !root.barIsVertical && root.barPosition !== "top")
            return barInverted || barTouchInverted || edgeInverted || oppositeEdgeInverted
          }
          bottomLeftInverted: {
            var barInverted = couldAttachToBar && ((root.barPosition === "bottom" && !root.barIsVertical && effectivePanelAnchorBottom) || (root.barPosition === "left" && root.barIsVertical && effectivePanelAnchorLeft))
            var barTouchInverted = touchingBottomBar || touchingLeftBar
            var edgeInverted = couldAttach && ((touchingLeftEdge && !root.barIsVertical) || (touchingBottomEdge && root.barIsVertical))
            var oppositeEdgeInverted = couldAttach && (touchingBottomEdge && !root.barIsVertical && root.barPosition !== "bottom")
            return barInverted || barTouchInverted || edgeInverted || oppositeEdgeInverted
          }
          bottomRightInverted: {
            var barInverted = couldAttachToBar && ((root.barPosition === "bottom" && !root.barIsVertical && effectivePanelAnchorBottom) || (root.barPosition === "right" && root.barIsVertical && effectivePanelAnchorRight))
            var barTouchInverted = touchingBottomBar || touchingRightBar
            var edgeInverted = couldAttach && ((touchingRightEdge && !root.barIsVertical) || (touchingBottomEdge && root.barIsVertical))
            var oppositeEdgeInverted = couldAttach && (touchingBottomEdge && !root.barIsVertical && root.barPosition !== "bottom")
            return barInverted || barTouchInverted || edgeInverted || oppositeEdgeInverted
          }

          // Set inverted corner direction based on which edge touches
          // Bar edges: horizontal bars → horizontal curves, vertical bars → vertical curves
          // Screen edges: opposite - left/right edges → vertical curves, top/bottom edges → horizontal curves
          topLeftInvertedDirection: {
            if (touchingLeftEdge && !root.barIsVertical)
              return "vertical"
            if (touchingTopEdge && root.barIsVertical)
              return "horizontal"
            return root.barIsVertical ? "vertical" : "horizontal"
          }
          topRightInvertedDirection: {
            if (touchingRightEdge && !root.barIsVertical)
              return "vertical"
            if (touchingTopEdge && root.barIsVertical)
              return "horizontal"
            return root.barIsVertical ? "vertical" : "horizontal"
          }
          bottomLeftInvertedDirection: {
            if (touchingLeftEdge && !root.barIsVertical)
              return "vertical"
            if (touchingBottomEdge && root.barIsVertical)
              return "horizontal"
            return root.barIsVertical ? "vertical" : "horizontal"
          }
          bottomRightInvertedDirection: {
            if (touchingRightEdge && !root.barIsVertical)
              return "vertical"
            if (touchingBottomEdge && root.barIsVertical)
              return "horizontal"
            return root.barIsVertical ? "vertical" : "horizontal"
          }
          width: {
            var w
            // Priority 1: Content-driven size (dynamic)
            if (contentLoader.item && contentLoader.item.contentPreferredWidth !== undefined) {
              w = contentLoader.item.contentPreferredWidth
            } // Priority 2: Ratio-based size
            else if (root.preferredWidthRatio !== undefined) {
              w = Math.round(Math.max((parent.width || 1920) * root.preferredWidthRatio, root.preferredWidth))
            } // Priority 3: Static preferred width
            else {
              w = root.preferredWidth
            }
            return Math.min(w, (parent.width || 1920) - Style.marginL * 2)
          }

          height: {
            var h
            // Priority 1: Content-driven size (dynamic)
            if (contentLoader.item && contentLoader.item.contentPreferredHeight !== undefined) {
              h = contentLoader.item.contentPreferredHeight
            } // Priority 2: Ratio-based size
            else if (root.preferredHeightRatio !== undefined) {
              h = Math.round(Math.max((parent.height || 1080) * root.preferredHeightRatio, root.preferredHeight))
            } // Priority 3: Static preferred height
            else {
              h = root.preferredHeight
            }
            return Math.min(h, (parent.height || 1080) - Style.barHeight - Style.marginL * 2)
          }

          // Detect if panel is touching screen edges
          readonly property bool touchingLeftEdge: couldAttach && x <= 1
          readonly property bool touchingRightEdge: couldAttach && (x + width) >= (parent.width - 1)
          readonly property bool touchingTopEdge: couldAttach && y <= 1
          readonly property bool touchingBottomEdge: couldAttach && (y + height) >= (parent.height - 1)

          // Detect if panel is touching bar edges (for cases where centered panels snap to bar due to height constraints)
          readonly property bool touchingTopBar: couldAttachToBar && root.barPosition === "top" && !root.barIsVertical && Math.abs(y - (root.barMarginV + Style.barHeight)) <= 1
          readonly property bool touchingBottomBar: couldAttachToBar && root.barPosition === "bottom" && !root.barIsVertical && Math.abs((y + height) - (parent.height - root.barMarginV - Style.barHeight)) <= 1
          readonly property bool touchingLeftBar: couldAttachToBar && root.barPosition === "left" && root.barIsVertical && Math.abs(x - (root.barMarginH + Style.barHeight)) <= 1
          readonly property bool touchingRightBar: couldAttachToBar && root.barPosition === "right" && root.barIsVertical && Math.abs((x + width) - (parent.width - root.barMarginH - Style.barHeight)) <= 1

          // Position the panel using explicit x/y coordinates (no anchors)
          // This makes coordinates clearer for the click-through mask system
          x: {
            var calculatedX

            // If useButtonPosition is enabled, align panel X with button
            // Note: We check useButtonPosition, not buttonItem, because buttonItem may become invalid
            // after the source panel (e.g., ControlCenter) closes, but we still have valid position data
            if (root.useButtonPosition && parent.width > 0 && width > 0) {
              if (root.barIsVertical) {
                // For vertical bars
                if (couldAttach) {
                  // Attached panels: align with bar edge (left or right side)
                  if (root.barPosition === "left") {
                    // Panel to the right of left bar
                    var leftBarEdge = root.barMarginH + Style.barHeight
                    // Panel sits right at bar edge (inverted corners align perfectly)
                    calculatedX = leftBarEdge
                  } else {
                    // right
                    // Panel to the left of right bar
                    var rightBarEdge = parent.width - root.barMarginH - Style.barHeight
                    // Panel sits right at bar edge (inverted corners align perfectly)
                    calculatedX = rightBarEdge - width
                  }
                } else {
                  // Detached panels: center on button X position
                  var panelX = root.buttonPosition.x + root.buttonWidth / 2 - width / 2
                  // Clamp to screen bounds with margins, accounting for bar position
                  var minX = Style.marginL
                  var maxX = parent.width - width - Style.marginL

                  // Account for vertical bar taking up space
                  if (root.barPosition === "left") {
                    minX = root.barMarginH + Style.barHeight + Style.marginL
                  } else if (root.barPosition === "right") {
                    maxX = parent.width - root.barMarginH - Style.barHeight - width - Style.marginL
                  }

                  panelX = Math.max(minX, Math.min(panelX, maxX))
                  calculatedX = panelX
                }
              } else {
                // For horizontal bars, center panel on button X position
                var panelX = root.buttonPosition.x + root.buttonWidth / 2 - width / 2
                // Clamp to bar bounds (account for floating bar margins)
                // When attached, panel should not extend beyond bar edges
                if (couldAttach) {
                  // Inverted corners with horizontal direction extend left/right by radiusL
                  // When bar is floating, it also has rounded corners, so we need extra insets
                  var cornerInset = root.barFloating ? Style.radiusL * 2 : 0
                  var barLeftEdge = root.barMarginH + cornerInset
                  var barRightEdge = parent.width - root.barMarginH - cornerInset
                  panelX = Math.max(barLeftEdge, Math.min(panelX, barRightEdge - width))
                } else {
                  panelX = Math.max(Style.marginL, Math.min(panelX, parent.width - width - Style.marginL))
                }
                calculatedX = panelX
              }
            } else {

              // Standard anchor positioning
              Logger.d("NPanel", "Fallback to standard anchor positioning")

              if (root.panelAnchorHorizontalCenter) {
                Logger.d("NPanel", "  -> Horizontal center")
                // Center horizontally, accounting for bar position and margins
                if (root.barIsVertical) {
                  // For vertical bars, center in the available space not occupied by the bar
                  if (root.barPosition === "left") {
                    var availableStart = root.barMarginH + Style.barHeight
                    var availableWidth = parent.width - availableStart
                    calculatedX = availableStart + (availableWidth - width) / 2
                  } else if (root.barPosition === "right") {
                    var availableWidth = parent.width - root.barMarginH - Style.barHeight
                    calculatedX = (availableWidth - width) / 2
                  } else {
                    // No vertical bar, center normally
                    calculatedX = (parent.width - width) / 2
                  }
                } else {
                  // For horizontal bars or no bar, center normally
                  calculatedX = (parent.width - width) / 2
                }
              } else if (effectivePanelAnchorRight) {
                Logger.d("NPanel", "  -> Right anchor")
                // When attached to right vertical bar, position next to bar (like useButtonPosition does)
                if (couldAttach && root.barIsVertical && root.barPosition === "right") {
                  var rightBarEdge = parent.width - root.barMarginH - Style.barHeight
                  calculatedX = rightBarEdge - width
                } else if (couldAttach) {
                  // Attach to right screen edge
                  calculatedX = parent.width - width
                } else {
                  // Detached: use margin
                  calculatedX = parent.width - width - Style.marginL
                }
              } else if (effectivePanelAnchorLeft) {
                Logger.d("NPanel", "  -> Left anchor")
                // When attached to left vertical bar, position next to bar (like useButtonPosition does)
                if (couldAttach && root.barIsVertical && root.barPosition === "left") {
                  var leftBarEdge = root.barMarginH + Style.barHeight
                  calculatedX = leftBarEdge
                } else if (couldAttach) {
                  // Attach to left screen edge
                  calculatedX = 0
                } else {
                  // Detached: use margin
                  calculatedX = Style.marginL
                }
              } else {
                // No explicit anchor: default to centering on bar
                Logger.d("NPanel", "  -> Default to center (no explicit anchor)")

                // For horizontal bars: center horizontally
                // For vertical bars: center horizontally in available space
                if (root.barIsVertical) {
                  // Center in the space not occupied by the bar
                  if (root.barPosition === "left") {
                    var availableStart = root.barMarginH + Style.barHeight
                    var availableWidth = parent.width - availableStart - Style.marginL
                    calculatedX = availableStart + (availableWidth - width) / 2
                  } else {
                    // right
                    var availableWidth = parent.width - root.barMarginH - Style.barHeight - Style.marginL
                    calculatedX = Style.marginL + (availableWidth - width) / 2
                  }
                } else {
                  // For horizontal bars: center horizontally, respect bar margins if attached
                  if (couldAttach) {
                    // When attached, respect bar bounds (like button position does)
                    var cornerInset = Style.radiusL + (root.barFloating ? Style.radiusL : 0)
                    var barLeftEdge = root.barMarginH + cornerInset
                    var barRightEdge = parent.width - root.barMarginH - cornerInset
                    var centeredX = (parent.width - width) / 2
                    calculatedX = Math.max(barLeftEdge, Math.min(centeredX, barRightEdge - width))
                  } else {
                    calculatedX = (parent.width - width) / 2
                  }
                }
              }
            }

            // Edge snapping: snap to screen edges if close (only when attached and bar is not floating)
            if (couldAttach && !root.barFloating && parent.width > 0 && width > 0) {
              // Calculate edge positions accounting for bar position
              // For vertical bars (left/right), we need to position panels AFTER the bar, not behind it
              var leftEdgePos = root.barMarginH
              if (root.barPosition === "left") {
                // Bar is on the left, so left edge is after the bar
                leftEdgePos = root.barMarginH + Style.barHeight
              }

              var rightEdgePos = parent.width - root.barMarginH - width
              if (root.barPosition === "right") {
                // Bar is on the right, so right edge is before the bar
                rightEdgePos = parent.width - root.barMarginH - Style.barHeight - width
              }

              // Snap to left edge if within snap distance
              if (Math.abs(calculatedX - leftEdgePos) <= root.edgeSnapDistance) {
                calculatedX = leftEdgePos
              } // Snap to right edge if within snap distance
              else if (Math.abs(calculatedX - rightEdgePos) <= root.edgeSnapDistance) {
                calculatedX = rightEdgePos
              }
            }

            return calculatedX
          }

          y: {
            var calculatedY

            // If useButtonPosition is enabled, position panel relative to bar
            // Note: We check useButtonPosition, not buttonItem, because buttonItem may become invalid
            // after the source panel (e.g., ControlCenter) closes, but we still have valid position data
            if (root.useButtonPosition && parent.height > 0 && height > 0) {
              if (root.barPosition === "top") {
                // Panel below top bar
                var topBarEdge = root.barMarginV + Style.barHeight
                if (couldAttach) {
                  // Panel sits right at bar edge (inverted corners align perfectly)
                  calculatedY = topBarEdge
                } else {
                  calculatedY = topBarEdge + Style.marginM
                }
              } else if (root.barPosition === "bottom") {
                // Panel above bottom bar
                var bottomBarEdge = parent.height - root.barMarginV - Style.barHeight
                if (couldAttach) {
                  // Panel sits right at bar edge (inverted corners align perfectly)
                  calculatedY = bottomBarEdge - height
                } else {
                  calculatedY = bottomBarEdge - height - Style.marginM
                }
              } else if (root.barIsVertical) {
                // For vertical bars, center panel on button Y position
                var panelY = root.buttonPosition.y + root.buttonHeight / 2 - height / 2
                // Clamp to bar bounds (account for floating bar margins and inverted corners)
                var extraPadding = (couldAttach && root.barFloating) ? Style.radiusL : 0
                if (couldAttach) {
                  // When attached, panel should not extend beyond bar edges (accounting for floating margins)
                  // Inverted corners with vertical direction extend up/down by radiusL
                  // When bar is floating, it also has rounded corners, so we need extra inset
                  var cornerInset = extraPadding + (root.barFloating ? Style.radiusL : 0)
                  var barTopEdge = root.barMarginV + cornerInset
                  var barBottomEdge = parent.height - root.barMarginV - cornerInset
                  panelY = Math.max(barTopEdge, Math.min(panelY, barBottomEdge - height))
                } else {
                  panelY = Math.max(Style.marginL + extraPadding, Math.min(panelY, parent.height - height - Style.marginL - extraPadding))
                }
                calculatedY = panelY
              }
            } else {

              // Standard anchor positioning
              // Calculate bar offset for detached panels - they should never overlap the bar
              var barOffset = 0
              if (!couldAttach) {
                // For detached panels, always account for bar position
                if (root.barPosition === "top") {
                  barOffset = root.barMarginV + Style.barHeight + Style.marginM
                } else if (root.barPosition === "bottom") {
                  barOffset = root.barMarginV + Style.barHeight + Style.marginM
                }
              } else {
                // For attached panels with explicit anchors
                if (effectivePanelAnchorTop && root.barPosition === "top") {
                  // When attached to top bar: position right at bar edge (inverted corners align perfectly)
                  calculatedY = root.barMarginV + Style.barHeight
                } else if (effectivePanelAnchorBottom && root.barPosition === "bottom") {
                  // When attached to bottom bar: position right at bar edge (inverted corners align perfectly)
                  calculatedY = parent.height - root.barMarginV - Style.barHeight - height
                } else if (!root.hasExplicitVerticalAnchor) {
                  // No explicit vertical anchor AND attached: default to attaching to bar edge
                  if (root.barPosition === "top") {
                    // Attach to top bar
                    calculatedY = root.barMarginV + Style.barHeight
                  } else if (root.barPosition === "bottom") {
                    // Attach to bottom bar
                    calculatedY = parent.height - root.barMarginV - Style.barHeight - height
                  }
                  // For vertical bars with no explicit anchor: fall through to center vertically on bar
                }
              }

              // Continue if calculatedY was already set above, or proceed with anchor positioning
              if (calculatedY === undefined) {
                if (root.panelAnchorVerticalCenter) {
                  // Center vertically, accounting for bar position and margins
                  if (!root.barIsVertical) {
                    // For horizontal bars, center in the available space not occupied by the bar
                    if (root.barPosition === "top") {
                      var availableStart = root.barMarginV + Style.barHeight
                      var availableHeight = parent.height - availableStart
                      calculatedY = availableStart + (availableHeight - height) / 2
                    } else if (root.barPosition === "bottom") {
                      var availableHeight = parent.height - root.barMarginV - Style.barHeight
                      calculatedY = (availableHeight - height) / 2
                    } else {
                      // No horizontal bar, center normally
                      calculatedY = (parent.height - height) / 2
                    }
                  } else {
                    // For vertical bars or no bar, center normally
                    calculatedY = (parent.height - height) / 2
                  }
                } else if (effectivePanelAnchorTop) {
                  // When couldAttach=true, attach to top screen edge; otherwise use margin
                  if (couldAttach) {
                    calculatedY = 0
                  } else {
                    // Only apply barOffset if bar is also at top (to avoid overlapping)
                    var topBarOffset = (root.barPosition === "top") ? barOffset : 0
                    calculatedY = topBarOffset + Style.marginL
                  }
                } else if (effectivePanelAnchorBottom) {
                  // When couldAttach=true, attach to bottom screen edge; otherwise use margin
                  if (couldAttach) {
                    calculatedY = parent.height - height
                  } else {
                    // Only apply barOffset if bar is also at bottom (to avoid overlapping)
                    var bottomBarOffset = (root.barPosition === "bottom") ? barOffset : 0
                    calculatedY = parent.height - height - bottomBarOffset - Style.marginL
                  }
                } else {
                  // No explicit vertical anchor
                  if (root.barIsVertical) {
                    // For vertical bars: center vertically on bar
                    if (couldAttach) {
                      // When attached, respect bar bounds
                      var cornerInset = root.barFloating ? Style.radiusL * 2 : 0
                      var barTopEdge = root.barMarginV + cornerInset
                      var barBottomEdge = parent.height - root.barMarginV - cornerInset
                      var centeredY = (parent.height - height) / 2
                      calculatedY = Math.max(barTopEdge, Math.min(centeredY, barBottomEdge - height))
                    } else {
                      calculatedY = (parent.height - height) / 2
                    }
                  } else {
                    // For horizontal bars: attach to bar edge by default
                    if (couldAttach && !root.barIsVertical) {
                      if (root.barPosition === "top") {
                        calculatedY = root.barMarginV + Style.barHeight
                      } else if (root.barPosition === "bottom") {
                        calculatedY = parent.height - root.barMarginV - Style.barHeight - height
                      }
                    } else {
                      // Detached or no bar position: use default positioning
                      if (root.barPosition === "top") {
                        calculatedY = barOffset + Style.marginL
                      } else if (root.barPosition === "bottom") {
                        calculatedY = Style.marginL
                      } else {
                        calculatedY = Style.marginL
                      }
                    }
                  }
                }
              }
            }

            // Edge snapping: snap to screen edges if close (only when attached and bar is not floating)
            if (couldAttach && !root.barFloating && parent.height > 0 && height > 0) {
              // Calculate edge positions accounting for bar position
              // For horizontal bars (top/bottom), we need to position panels AFTER the bar, not behind it
              var topEdgePos = root.barMarginV
              if (root.barPosition === "top") {
                // Bar is on the top, so top edge is after the bar
                topEdgePos = root.barMarginV + Style.barHeight
              }

              var bottomEdgePos = parent.height - root.barMarginV - height
              if (root.barPosition === "bottom") {
                // Bar is on the bottom, so bottom edge is before the bar
                bottomEdgePos = parent.height - root.barMarginV - Style.barHeight - height
              }

              // Snap to top edge if within snap distance
              if (Math.abs(calculatedY - topEdgePos) <= root.edgeSnapDistance) {
                calculatedY = topEdgePos
              } // Snap to bottom edge if within snap distance
              else if (Math.abs(calculatedY - bottomEdgePos) <= root.edgeSnapDistance) {
                calculatedY = bottomEdgePos
              }
            }

            return calculatedY
          }

          // MouseArea to catch clicks on the panel and prevent them from reaching the background
          // This prevents closing the panel when clicking inside it
          MouseArea {
            anchors.fill: parent
            z: -1 // Behind content, but on the panel background
            onClicked: {

              // Accept and ignore - prevents propagation to background
            }
          }

          // Panel content loader
          Loader {
            id: contentLoader
            anchors.fill: parent
            sourceComponent: root.panelContent
          }
        }
      }
    }
  }
}
