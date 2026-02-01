import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

PopupWindow {
  id: root

  property string text: ""
  property var rows: null // Array of arrays for grid mode: [["col1", "col2"], ["row2col1", "row2col2"]]
  property bool isGridMode: rows !== null && Array.isArray(rows) && rows.length > 0
  property int columnCount: isGridMode && rows.length > 0 ? rows[0].length : 0
  property string direction: "auto" // "auto", "left", "right", "top", "bottom"
  property int margin: Style.marginXS // distance from target
  property int padding: Style.marginM
  property int gridPaddingVertical: Style.marginXS // extra vertical padding for grid mode
  property int delay: 0
  property int hideDelay: 0
  property int maxWidth: 320

  property int animationDuration: Style.animationFast
  property real animationScale: 0.85

  // For measuring grid cell sizes
  TextMetrics {
    id: cellMetrics
    font.family: Settings.data.ui.fontFixed
    font.pointSize: Style.fontSizeS
  }

  // Internal properties
  property var targetItem: null
  property real anchorX: 0
  property real anchorY: 0
  property bool isPositioned: false
  property bool animatingOut: true
  property int screenWidth: 1920
  property int screenHeight: 1080
  property int screenX: 0
  property int screenY: 0

  visible: false
  color: "transparent"

  anchor.item: targetItem
  anchor.rect.x: anchorX
  anchor.rect.y: anchorY

  // Timer for showing tooltip after delay
  Timer {
    id: showTimer
    interval: root.delay
    repeat: false
    onTriggered: {
      root.positionAndShow();
    }
  }

  // Timer for hiding tooltip after delay
  Timer {
    id: hideTimer
    interval: root.hideDelay
    repeat: false
    onTriggered: {
      root.startHideAnimation();
    }
  }

  // Show animation
  ParallelAnimation {
    id: showAnimation

    PropertyAnimation {
      target: tooltipContainer
      property: "opacity"
      from: 0.0
      to: 1.0
      duration: root.animationDuration
      easing.type: Easing.OutCubic
    }

    PropertyAnimation {
      target: tooltipContainer
      property: "scale"
      from: root.animationScale
      to: 1.0
      duration: root.animationDuration
      easing.type: Easing.OutBack
      easing.overshoot: 1.2
    }
  }

  // Hide animation
  ParallelAnimation {
    id: hideAnimation

    PropertyAnimation {
      target: tooltipContainer
      property: "opacity"
      from: 1.0
      to: 0.0
      duration: root.animationDuration * 0.75 // Slightly faster hide
      easing.type: Easing.InCubic
    }

    PropertyAnimation {
      target: tooltipContainer
      property: "scale"
      from: 1.0
      to: root.animationScale
      duration: root.animationDuration * 0.75
      easing.type: Easing.InCubic
    }

    onFinished: {
      root.completeHide();
    }
  }

  // Function to show tooltip (content can be string or array of arrays for grid mode)
  function show(target, content, customDirection, showDelay, fontFamily) {
    if (!target || !content || content === "" || (Array.isArray(content) && content.length === 0))
      return;

    root.delay = showDelay;

    // Stop any running timers and animations
    hideTimer.stop();
    showTimer.stop();
    hideAnimation.stop();
    animatingOut = false;

    // If we're already showing for a different target, hide immediately
    if (visible && targetItem !== target) {
      hideImmediately();
    }

    // Set content based on type
    if (Array.isArray(content)) {
      rows = content;
      text = "";
    } else {
      // Convert \n to <br> for RichText format
      const processedText = content.replace(/\n/g, '<br>');
      text = processedText;
      rows = null;
    }

    targetItem = target;

    // Find the correct screen dimensions based on target's global position
    // Respect all screens positionning
    const targetGlobal = target.mapToGlobal(target.width / 2, target.height / 2);
    let foundScreen = false;
    for (let i = 0; i < Quickshell.screens.length; i++) {
      const s = Quickshell.screens[i];
      if (targetGlobal.x >= s.x && targetGlobal.x < s.x + s.width && targetGlobal.y >= s.y && targetGlobal.y < s.y + s.height) {
        screenWidth = s.width;
        screenHeight = s.height;
        screenX = s.x;
        screenY = s.y;
        foundScreen = true;
        break;
      }
    }
    if (!foundScreen) {
      Logger.w("Tooltip", "No screen found for target position!");
    }

    // Initialize animation state (hidden)
    tooltipContainer.opacity = 0.0;
    tooltipContainer.scale = root.animationScale;

    // Start show timer (will position and then make visible)
    showTimer.start();

    if (customDirection !== undefined) {
      direction = customDirection;
    } else {
      direction = "auto";
    }

    tooltipText.family = fontFamily ? fontFamily : Settings.data.ui.fontDefault;
  }

  // Calculate grid dimensions using TextMetrics
  function calculateGridSize() {
    if (!rows || rows.length === 0)
      return {
        width: 0,
        height: 0
      };

    const numCols = rows[0].length;
    const numRows = rows.length;
    let columnWidths = [];

    // Find max width for each column
    for (let col = 0; col < numCols; col++) {
      let maxWidth = 0;
      for (let row = 0; row < numRows; row++) {
        cellMetrics.text = rows[row][col] || "";
        if (cellMetrics.width > maxWidth) {
          maxWidth = cellMetrics.width;
        }
      }
      columnWidths.push(maxWidth);
    }

    // Calculate total width: sum of columns + spacing between columns
    let totalWidth = 0;
    for (let i = 0; i < columnWidths.length; i++) {
      totalWidth += columnWidths[i];
    }
    totalWidth += (numCols - 1) * Style.marginM; // columnSpacing

    // Calculate total height: rows * row height + spacing + extra vertical padding
    const rowHeight = cellMetrics.height;
    const totalHeight = (numRows * rowHeight) + ((numRows - 1) * 0) + (gridPaddingVertical * 2); // rowSpacing is 0

    return {
      width: totalWidth,
      height: totalHeight
    };
  }

  // Function to position and display the tooltip
  function positionAndShow() {
    if (!targetItem || !targetItem.parent) {
      return;
    }

    // Calculate tooltip dimensions based on content mode
    let contentWidth, contentHeight;
    if (isGridMode) {
      const gridSize = calculateGridSize();
      contentWidth = gridSize.width;
      contentHeight = gridSize.height;
    } else {
      contentWidth = tooltipText.implicitWidth;
      contentHeight = tooltipText.implicitHeight;
    }

    const tipWidth = Math.min(contentWidth + (padding * 2), maxWidth);
    root.implicitWidth = tipWidth;

    const tipHeight = contentHeight + (padding * 2);
    root.implicitHeight = tipHeight;

    // Get target's global position and convert to screen-relative
    var targetGlobalAbs = targetItem.mapToGlobal(0, 0);
    var targetGlobal = {
      "x": targetGlobalAbs.x - screenX,
      "y": targetGlobalAbs.y - screenY
    };
    const targetWidth = targetItem.width;
    const targetHeight = targetItem.height;

    var newAnchorX = 0;
    var newAnchorY = 0;

    if (direction === "auto") {
      // Calculate available space in each direction (screen-relative)
      const spaceLeft = targetGlobal.x;
      const spaceRight = screenWidth - (targetGlobal.x + targetWidth);
      const spaceTop = targetGlobal.y;
      const spaceBottom = screenHeight - (targetGlobal.y + targetHeight);

      // Try positions in order of available space
      const positions = [
              {
                "dir": "bottom",
                "space": spaceBottom,
                "x": (targetWidth - tipWidth) / 2,
                "y": targetHeight + margin,
                "fits": spaceBottom >= tipHeight + margin
              },
              {
                "dir": "top",
                "space": spaceTop,
                "x": (targetWidth - tipWidth) / 2,
                "y": -tipHeight - margin,
                "fits": spaceTop >= tipHeight + margin
              },
              {
                "dir": "right",
                "space": spaceRight,
                "x": targetWidth + margin,
                "y": (targetHeight - tipHeight) / 2,
                "fits": spaceRight >= tipWidth + margin
              },
              {
                "dir": "left",
                "space": spaceLeft,
                "x": -tipWidth - margin,
                "y": (targetHeight - tipHeight) / 2,
                "fits": spaceLeft >= tipWidth + margin
              }
            ];

      // Find first position that fits
      var selectedPosition = null;
      for (var i = 0; i < positions.length; i++) {
        if (positions[i].fits) {
          selectedPosition = positions[i];
          break;
        }
      }

      // If none fit perfectly
      if (!selectedPosition) {
        // Sort by available space and use position with most space
        positions.sort(function (a, b) {
          return b.space - a.space;
        });
        selectedPosition = positions[0];
      }

      newAnchorX = selectedPosition.x;
      newAnchorY = selectedPosition.y;
    } else {
      // Manual direction positioning
      switch (direction) {
      case "left":
        newAnchorX = -tipWidth - margin;
        newAnchorY = (targetHeight - tipHeight) / 2;
        break;
      case "right":
        newAnchorX = targetWidth + margin;
        newAnchorY = (targetHeight - tipHeight) / 2;
        break;
      case "top":
        newAnchorX = (targetWidth - tipWidth) / 2;
        newAnchorY = -tipHeight - margin;
        break;
      case "bottom":
        newAnchorX = (targetWidth - tipWidth) / 2;
        newAnchorY = targetHeight + margin;
        break;
      }
    }

    // Adjust horizontal position to keep tooltip on screen
    // For top/bottom tooltips, always adjust horizontally (they don't overlap horizontally)
    // For left/right tooltips, check for overlap before adjusting
    const globalX = targetGlobal.x + newAnchorX;
    const isHorizontalTooltip = (direction === "top" || direction === "bottom");

    if (globalX < 0) {
      // Clipping at left - only adjust if tooltip won't overlap target
      const adjustedX = -targetGlobal.x + margin;
      if (isHorizontalTooltip) {
        // Top/bottom tooltips: always allow horizontal adjustment
        newAnchorX = adjustedX;
      } else {
        // Left/right tooltips: check for vertical overlap
        const wouldOverlap = adjustedX < targetWidth && adjustedX + tipWidth > 0;
        if (!wouldOverlap) {
          newAnchorX = adjustedX;
        }
      }
    } else if (globalX + tipWidth > screenWidth) {
      // Clipping at right - only adjust if tooltip won't overlap target
      const adjustedX = screenWidth - targetGlobal.x - tipWidth - margin;
      if (isHorizontalTooltip) {
        // Top/bottom tooltips: always allow horizontal adjustment
        newAnchorX = adjustedX;
      } else {
        // Left/right tooltips: check for vertical overlap
        const wouldOverlap = adjustedX < targetWidth && adjustedX + tipWidth > 0;
        if (!wouldOverlap) {
          newAnchorX = adjustedX;
        }
      }
    }

    // Adjust vertical position to keep tooltip on screen
    // For left/right tooltips, always adjust vertically (they don't overlap vertically)
    // For top/bottom tooltips, check for overlap before adjusting
    const globalY = targetGlobal.y + newAnchorY;
    const isVerticalTooltip = (direction === "left" || direction === "right");

    if (globalY < 0) {
      // Clipping at top - only adjust if tooltip won't overlap target
      const adjustedY = -targetGlobal.y + margin;
      if (isVerticalTooltip) {
        // Left/right tooltips: always allow vertical adjustment
        newAnchorY = adjustedY;
      } else {
        // Top/bottom tooltips: check for horizontal overlap
        const wouldOverlap = adjustedY < targetHeight && adjustedY + tipHeight > 0;
        if (!wouldOverlap) {
          newAnchorY = adjustedY;
        }
      }
    } else if (globalY + tipHeight > screenHeight) {
      // Clipping at bottom - only adjust if tooltip won't overlap target
      const adjustedY = screenHeight - targetGlobal.y - tipHeight - margin;
      if (isVerticalTooltip) {
        // Left/right tooltips: always allow vertical adjustment
        newAnchorY = adjustedY;
      } else {
        // Top/bottom tooltips: check for horizontal overlap
        const wouldOverlap = adjustedY < targetHeight && adjustedY + tipHeight > 0;
        if (!wouldOverlap) {
          newAnchorY = adjustedY;
        }
      }
    }

    // Apply position first (before making visible)
    anchorX = newAnchorX;
    anchorY = newAnchorY;
    isPositioned = true;

    // Now make visible and start animation
    root.visible = true;
    showAnimation.start();
  }

  // Function to hide tooltip
  function hide() {
    // Stop show timer if it's running
    showTimer.stop();

    // Stop hide timer if it's running
    hideTimer.stop();

    if (hideDelay > 0 && visible && !animatingOut) {
      hideTimer.start();
    } else {
      startHideAnimation();
    }
  }

  function startHideAnimation() {
    if (!visible || animatingOut)
      return;
    animatingOut = true;
    showAnimation.stop(); // Stop show animation if running
    hideAnimation.start();
  }

  function completeHide() {
    visible = false;
    animatingOut = false;
    text = "";
    rows = null;
    isPositioned = false;
    tooltipContainer.opacity = 1.0;
    tooltipContainer.scale = 1.0;
  }

  // Quick hide without delay or animation
  function hideImmediately() {
    showTimer.stop();
    hideTimer.stop();
    showAnimation.stop();
    hideAnimation.stop();
    animatingOut = false;
    completeHide();
  }

  // Update content function (supports both text and rows)
  function updateContent(newContent) {
    if (visible && targetItem) {
      if (Array.isArray(newContent)) {
        rows = newContent;
        text = "";
      } else {
        // Convert \n to <br> for RichText format
        const processedText = newContent.replace(/\n/g, '<br>');
        text = processedText;
        rows = null;
      }

      // Recalculate dimensions based on content mode
      let contentWidth, contentHeight;
      if (isGridMode) {
        const gridSize = calculateGridSize();
        contentWidth = gridSize.width;
        contentHeight = gridSize.height;
      } else {
        contentWidth = tooltipText.implicitWidth;
        contentHeight = tooltipText.implicitHeight;
      }

      const tipWidth = Math.min(contentWidth + (padding * 2), maxWidth);
      root.implicitWidth = tipWidth;

      const tipHeight = contentHeight + (padding * 2);
      root.implicitHeight = tipHeight;

      // Reposition based on current direction (screen-relative)
      var targetGlobalAbs = targetItem.mapToGlobal(0, 0);
      var targetGlobal = {
        "x": targetGlobalAbs.x - screenX,
        "y": targetGlobalAbs.y - screenY
      };
      const targetWidth = targetItem.width;
      const targetHeight = targetItem.height;

      // Recalculate base anchor position (center on target for top/bottom, etc.)
      var newAnchorX = anchorX;
      var newAnchorY = anchorY;

      // Determine which direction the tooltip is currently positioned
      // and recalculate the centering for that direction
      var isHorizontalTooltip = false;
      var isVerticalTooltip = false;
      if (anchorY > targetHeight / 2) {
        // Tooltip is below target
        newAnchorX = (targetWidth - tipWidth) / 2;
        isHorizontalTooltip = true;
      } else if (anchorY < -tipHeight / 2) {
        // Tooltip is above target
        newAnchorX = (targetWidth - tipWidth) / 2;
        isHorizontalTooltip = true;
      } else if (anchorX > targetWidth / 2) {
        // Tooltip is to the right
        newAnchorY = (targetHeight - tipHeight) / 2;
        isVerticalTooltip = true;
      } else if (anchorX < -tipWidth / 2) {
        // Tooltip is to the left
        newAnchorY = (targetHeight - tipHeight) / 2;
        isVerticalTooltip = true;
      }

      // Adjust horizontal position to keep tooltip on screen if needed
      // For top/bottom tooltips, always adjust horizontally (they don't overlap horizontally)
      // For left/right tooltips, check for overlap before adjusting
      const globalX = targetGlobal.x + newAnchorX;
      if (globalX < 0) {
        const adjustedX = -targetGlobal.x + margin;
        if (isHorizontalTooltip) {
          newAnchorX = adjustedX;
        } else {
          const wouldOverlap = adjustedX < targetWidth && adjustedX + tipWidth > 0;
          if (!wouldOverlap) {
            newAnchorX = adjustedX;
          }
        }
      } else if (globalX + tipWidth > screenWidth) {
        const adjustedX = screenWidth - targetGlobal.x - tipWidth - margin;
        if (isHorizontalTooltip) {
          newAnchorX = adjustedX;
        } else {
          const wouldOverlap = adjustedX < targetWidth && adjustedX + tipWidth > 0;
          if (!wouldOverlap) {
            newAnchorX = adjustedX;
          }
        }
      }

      // Adjust vertical position to keep tooltip on screen if needed
      // For left/right tooltips, always adjust vertically (they don't overlap vertically)
      // For top/bottom tooltips, check for overlap before adjusting
      const globalY = targetGlobal.y + newAnchorY;
      if (globalY < 0) {
        const adjustedY = -targetGlobal.y + margin;
        if (isVerticalTooltip) {
          newAnchorY = adjustedY;
        } else {
          const wouldOverlap = adjustedY < targetHeight && adjustedY + tipHeight > 0;
          if (!wouldOverlap) {
            newAnchorY = adjustedY;
          }
        }
      } else if (globalY + tipHeight > screenHeight) {
        const adjustedY = screenHeight - targetGlobal.y - tipHeight - margin;
        if (isVerticalTooltip) {
          newAnchorY = adjustedY;
        } else {
          const wouldOverlap = adjustedY < targetHeight && adjustedY + tipHeight > 0;
          if (!wouldOverlap) {
            newAnchorY = adjustedY;
          }
        }
      }

      // Apply the new anchor positions
      anchorX = newAnchorX;
      anchorY = newAnchorY;

      // Force anchor update
      Qt.callLater(() => {
                     if (root.anchor && root.visible) {
                       root.anchor.updateAnchor();
                     }
                   });
    }
  }

  // Backward compatibility alias
  function updateText(newText) {
    updateContent(newText);
  }

  // Reset function to clean up state
  function reset() {
    // Stop all timers and animations
    showTimer.stop();
    hideTimer.stop();
    showAnimation.stop();
    hideAnimation.stop();

    // Clear all state
    visible = false;
    animatingOut = false;
    text = "";
    rows = null;
    isPositioned = false;

    // Reset to defaults
    direction = "auto";
    delay = 0;
    hideDelay = 0;

    // Reset container state
    tooltipContainer.opacity = 1.0;
    tooltipContainer.scale = 1.0;
  }

  // Tooltip content container for animations
  Item {
    id: tooltipContainer
    anchors.fill: parent

    // Animation properties
    opacity: 1.0
    scale: 1.0
    transformOrigin: Item.Center

    Rectangle {
      anchors.fill: parent
      color: Color.mSurface
      border.color: Color.mOutline
      border.width: Style.borderS
      radius: Style.radiusS

      // Only show content when we have content
      visible: root.text !== "" || root.isGridMode

      // Text content (default mode)
      NText {
        id: tooltipText
        visible: !root.isGridMode
        anchors.centerIn: parent
        anchors.margins: root.padding
        text: root.text
        pointSize: Style.fontSizeS
        family: Settings.data.ui.fontFixed
        color: Color.mOnSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        width: Math.min(implicitWidth, root.maxWidth - (root.padding * 2))
        richTextEnabled: true
      }

      // Grid content (grid mode)
      GridLayout {
        id: gridContent
        visible: root.isGridMode
        anchors.centerIn: parent
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        anchors.topMargin: root.padding + root.gridPaddingVertical
        anchors.bottomMargin: root.padding + root.gridPaddingVertical
        columns: root.columnCount
        rowSpacing: 0
        columnSpacing: Style.marginM

        Repeater {
          model: root.isGridMode ? [].concat.apply([], root.rows) : []

          NText {
            text: modelData
            pointSize: Style.fontSizeS
            family: tooltipText.family
            color: Color.mOnSurfaceVariant
          }
        }
      }
    }
  }

  Component.onCompleted: {
    reset();
  }

  Component.onDestruction: {
    reset();
  }
}
