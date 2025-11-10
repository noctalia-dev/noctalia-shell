import QtQuick
// import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

PopupWindow {
  id: root

  property int screenWidth: 0
  property int screenHeight: 0

  property string text: ""
  property string direction: "auto" // "auto", "left", "right", "top", "bottom"
  property int margin: Style.marginXS // distance from target
  property int padding: Style.marginM
  property int delay: 0
  property int hideDelay: 0
  property int maxWidth: 320

  property int animationDuration: Style.animationFast
  property real animationScale: 0.85

  // Internal properties
  property var targetItem: null
  property real anchorX: 0
  property real anchorY: 0
  property bool isPositioned: false
  property bool pendingShow: false
  property bool animatingOut: true

  visible: false
  color: Color.transparent

  anchor.item: targetItem
  anchor.rect.x: anchorX
  anchor.rect.y: anchorY

  // Timer for showing tooltip after delay
  Timer {
    id: showTimer
    interval: root.delay
    repeat: false
    onTriggered: {
      root.positionAndShow()
    }
  }

  // Timer for hiding tooltip after delay
  Timer {
    id: hideTimer
    interval: root.hideDelay
    repeat: false
    onTriggered: {
      root.startHideAnimation()
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
      root.completeHide()
    }
  }

  // Function to show tooltip
  function show(screen, target, tipText, customDirection, showDelay) {
    if (!screen || !target || !tipText || tipText === "")
      return

    root.screenWidth = screen.width
    root.screenHeight = screen.height

    root.delay = showDelay

    // Stop any running timers and animations
    hideTimer.stop()
    showTimer.stop()
    hideAnimation.stop()
    animatingOut = false

    // If we're already showing for a different target, hide immediately
    if (visible && targetItem !== target) {
      hideImmediately()
    }

    // Set properties
    targetItem = target
    text = tipText
    pendingShow = true

    if (customDirection !== undefined) {
      direction = customDirection
    } else {
      direction = "auto"
    }

    // Start show timer
    showTimer.start()
  }

  // Function to position and display the tooltip
  function positionAndShow() {
    if (!targetItem || !targetItem.parent || !pendingShow) {
      return
    }

    // Calculate tooltip dimensions
    const tipWidth = Math.min(tooltipText.implicitWidth + (padding * 2), maxWidth)
    root.implicitWidth = tipWidth

    const tipHeight = tooltipText.implicitHeight + (padding * 2)
    root.implicitHeight = tipHeight

    // Get target's global position
    var targetGlobal = targetItem.mapToItem(null, 0, 0)
    const targetWidth = targetItem.width
    const targetHeight = targetItem.height

    var newAnchorX = 0
    var newAnchorY = 0

    if (direction === "auto") {
      // Calculate available space in each direction
      const spaceLeft = targetGlobal.x
      const spaceRight = screenWidth - (targetGlobal.x + targetWidth)
      const spaceTop = targetGlobal.y
      const spaceBottom = screenHeight - (targetGlobal.y + targetHeight)

      // Try positions in order of available space
      const positions = [{
                           "dir": "bottom",
                           "space": spaceBottom,
                           "x": (targetWidth - tipWidth) / 2,
                           "y": targetHeight + margin,
                           "fits": spaceBottom >= tipHeight + margin
                         }, {
                           "dir": "top",
                           "space": spaceTop,
                           "x": (targetWidth - tipWidth) / 2,
                           "y": -tipHeight - margin,
                           "fits": spaceTop >= tipHeight + margin
                         }, {
                           "dir": "right",
                           "space": spaceRight,
                           "x": targetWidth + margin,
                           "y": (targetHeight - tipHeight) / 2,
                           "fits": spaceRight >= tipWidth + margin
                         }, {
                           "dir": "left",
                           "space": spaceLeft,
                           "x": -tipWidth - margin,
                           "y": (targetHeight - tipHeight) / 2,
                           "fits": spaceLeft >= tipWidth + margin
                         }]

      // Find first position that fits
      var selectedPosition = null
      for (var i = 0; i < positions.length; i++) {
        if (positions[i].fits) {
          selectedPosition = positions[i]
          break
        }
      }

      // If none fit perfectly
      if (!selectedPosition) {
        // Sort by available space and use position with most space
        positions.sort(function (a, b) {
          return b.space - a.space
        })
        selectedPosition = positions[0]
      }

      newAnchorX = selectedPosition.x
      newAnchorY = selectedPosition.y

      // Adjust horizontal position to keep tooltip on screen
      if (direction === "auto") {
        const globalX = targetGlobal.x + newAnchorX
        if (globalX < 0) {
          newAnchorX = -targetGlobal.x + margin
        } else if (globalX + tipWidth > screenWidth) {
          newAnchorX = screenWidth - targetGlobal.x - tipWidth - margin
        }
      }
    } else {
      // Manual direction positioning
      switch (direction) {
      case "left":
        newAnchorX = -tipWidth - margin
        newAnchorY = (targetHeight - tipHeight) / 2
        break
      case "right":
        newAnchorX = targetWidth + margin
        newAnchorY = (targetHeight - tipHeight) / 2
        break
      case "top":
        newAnchorX = (targetWidth - tipWidth) / 2
        newAnchorY = -tipHeight - margin
        break
      case "bottom":
        newAnchorX = (targetWidth - tipWidth) / 2
        newAnchorY = targetHeight + margin
        break
      }
    }

    // Apply position
    anchorX = newAnchorX
    anchorY = newAnchorY
    isPositioned = true
    pendingShow = false

    // Show tooltip and start animation
    visible = true

    // Initialize animation state
    tooltipContainer.opacity = 0.0
    tooltipContainer.scale = animationScale

    // Start show animation
    showAnimation.start()

    // Force anchor update after showing
    Qt.callLater(() => {
                   if (root.anchor && root.visible) {
                     root.anchor.updateAnchor()
                   }
                 })
  }

  // Function to hide tooltip
  function hide() {
    // Stop show timer if it's running
    showTimer.stop()
    pendingShow = false

    // Stop hide timer if it's running
    hideTimer.stop()

    if (hideDelay > 0 && visible && !animatingOut) {
      hideTimer.start()
    } else {
      startHideAnimation()
    }
  }

  function startHideAnimation() {
    if (!visible || animatingOut)
      return

    animatingOut = true
    showAnimation.stop() // Stop show animation if running
    hideAnimation.start()
  }

  function completeHide() {
    visible = false
    animatingOut = false
    pendingShow = false
    text = ""
    isPositioned = false
    tooltipContainer.opacity = 1.0
    tooltipContainer.scale = 1.0
  }

  // Quick hide without delay or animation
  function hideImmediately() {
    showTimer.stop()
    hideTimer.stop()
    showAnimation.stop()
    hideAnimation.stop()
    pendingShow = false
    animatingOut = false
    completeHide()
  }

  // Update text function
  function updateText(newText) {
    if (visible && targetItem) {
      text = newText

      // Recalculate dimensions
      const tipWidth = Math.min(tooltipText.implicitWidth + (padding * 2), maxWidth)
      root.implicitWidth = tipWidth

      const tipHeight = tooltipText.implicitHeight + (padding * 2)
      root.implicitHeight = tipHeight

      // Reposition if necessary
      var targetGlobal = targetItem.mapToItem(null, 0, 0)
      const targetWidth = targetItem.width

      // Adjust horizontal position to keep tooltip on screen if needed
      const globalX = targetGlobal.x + anchorX
      if (globalX < 0) {
        anchorX = -targetGlobal.x + margin
      } else if (globalX + tipWidth > screenWidth) {
        anchorX = screenWidth - targetGlobal.x - tipWidth - margin
      }

      // Force anchor update
      Qt.callLater(() => {
                     if (root.anchor && root.visible) {
                       root.anchor.updateAnchor()
                     }
                   })
    }
  }

  // Reset function to clean up state
  function reset() {
    // Stop all timers and animations
    showTimer.stop()
    hideTimer.stop()
    showAnimation.stop()
    hideAnimation.stop()

    // Clear all state
    visible = false
    pendingShow = false
    animatingOut = false
    text = ""
    isPositioned = false

    // Reset to defaults
    direction = "auto"
    delay = 0
    hideDelay = 0

    // Reset container state
    tooltipContainer.opacity = 1.0
    tooltipContainer.scale = 1.0
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

      // Only show content when we have text
      visible: root.text !== ""

      NText {
        id: tooltipText
        anchors.centerIn: parent
        anchors.margins: root.padding
        text: root.text
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        width: root.maxWidth - (root.padding * 2)
      }
    }
  }

  Component.onCompleted: {
    reset()
  }

  Component.onDestruction: {
    reset()
  }
}
