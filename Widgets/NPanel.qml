import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

Loader {
  id: root

  property ShellScreen screen

  readonly property real opacityThreshold: 0.33
  property bool attachedToBar: (Settings.data.ui.panelsAttachedToBar && Settings.data.bar.backgroundOpacity > opacityThreshold)
  property bool useOverlay: Settings.data.ui.panelsOverlayLayer

  property Component panelContent: null

  // Panel size properties. Can be set directly on NPanel, or dynamically by the content.
  // For dynamic sizing, the content should expose contentPreferredWidth, contentPreferredHeight,
  // contentPreferredWidthRatio, or contentPreferredHeightRatio properties.
  // Changes to these properties will be animated smoothly (except during panel dragging).
  property real preferredWidth: 700
  property real preferredHeight: 900
  property real preferredWidthRatio
  property real preferredHeightRatio
  property color panelBackgroundColor: Color.mSurface
  property color panelBorderColor: Color.mOutline
  property bool draggable: false
  property var buttonItem: null
  property string buttonName: ""

  property bool panelAnchorHorizontalCenter: false
  property bool panelAnchorVerticalCenter: false
  property bool panelAnchorTop: false
  property bool panelAnchorBottom: false
  property bool panelAnchorLeft: false
  property bool panelAnchorRight: false

  // Properties to support positioning relative to the opener (button)
  property bool useButtonPosition: false
  property point buttonPosition: Qt.point(0, 0)
  property int buttonWidth: 0
  property int buttonHeight: 0

  property bool panelKeyboardFocus: false
  property bool backgroundClickEnabled: true

  // Animation properties
  property real panelBackgroundOpacity: 0
  property real panelContentOpacity: 0
  property real dimmingOpacity: 0

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property real verticalBarWidth: Style.barHeight

  // Effective anchor properties - combines explicit anchors with implicit anchoring from useButtonPosition
  readonly property bool effectivePanelAnchorTop: panelAnchorTop || (useButtonPosition && barPosition === "top")
  readonly property bool effectivePanelAnchorBottom: panelAnchorBottom || (useButtonPosition && barPosition === "bottom")
  readonly property bool effectivePanelAnchorLeft: panelAnchorLeft || (useButtonPosition && barPosition === "left")
  readonly property bool effectivePanelAnchorRight: panelAnchorRight || (useButtonPosition && barPosition === "right")

  signal opened
  signal closed

  active: false
  asynchronous: true

  Component.onCompleted: {
    PanelService.registerPanel(root)
  }

  // -----------------------------------------
  // Functions to control background click behavior
  function disableBackgroundClick() {
    backgroundClickEnabled = false
  }

  function enableBackgroundClick() {
    // Add a small delay to prevent immediate close after drag release
    enableBackgroundClickTimer.restart()
  }

  Timer {
    id: enableBackgroundClickTimer
    interval: 100
    repeat: false
    onTriggered: backgroundClickEnabled = true
  }

  // -----------------------------------------
  function toggle(buttonItem, buttonName) {
    if (!active) {
      open(buttonItem, buttonName)
    } else {
      close()
    }
  }

  // -----------------------------------------
  function open(buttonItem, buttonName) {
    root.buttonItem = buttonItem
    root.buttonName = buttonName || ""

    setPosition()

    PanelService.willOpenPanel(root)

    backgroundClickEnabled = true
    active = true
    root.opened()
  }

  // -----------------------------------------
  function close() {
    dimmingOpacity = 0
    panelBackgroundOpacity = 0
    panelContentOpacity = 0
    root.closed()
    active = false
    useButtonPosition = false
    backgroundClickEnabled = true
    PanelService.closedPanel(root)
  }

  // -----------------------------------------
  function setPosition() {
    // If we have a button name, we are landing here from an IPC call.
    // IPC calls have no idead on which screen they panel will spawn.
    // Resolve the button name to a proper button item now that we have a screen.
    if (buttonName !== "" && root.screen !== null) {
      buttonItem = BarService.lookupWidget(buttonName, root.screen.name)
    }

    // Get the button position if provided
    if (buttonItem !== undefined && buttonItem !== null) {
      useButtonPosition = true
      var itemPos = buttonItem.mapToItem(null, 0, 0)
      buttonPosition = Qt.point(itemPos.x, itemPos.y)
      buttonWidth = buttonItem.width
      buttonHeight = buttonItem.height
    } else {
      useButtonPosition = false
    }
  }

  // -----------------------------------------
  sourceComponent: Component {
    // PanelWindow has its own screen property inherited of QsWindow
    PanelWindow {
      id: panelWindow

      readonly property bool barIsVisible: (screen !== null) && (Settings.data.bar.monitors.includes(screen.name) || (Settings.data.bar.monitors.length === 0))

      Component.onCompleted: {
        Logger.d("NPanel", "Opened", root.objectName, "on", screen.name)
        dimmingOpacity = Style.opacityHeavy
      }

      Connections {
        target: panelWindow
        function onScreenChanged() {
          root.screen = screen

          // If called from IPC always reposition if screen is updated
          if (buttonName) {
            setPosition()
          }
          Logger.d("NPanel", "OnScreenChanged", root.screen.name)
        }
      }

      color: Color.transparent

      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-panel"
      WlrLayershell.layer: useOverlay ? WlrLayer.Overlay : WlrLayer.Top
      WlrLayershell.keyboardFocus: root.panelKeyboardFocus ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

      Region {
        id: maskRegion
      }

      Behavior on color {
        ColorAnimation {
          duration: Style.animationNormal
        }
      }

      anchors.top: true
      anchors.left: true
      anchors.right: true
      anchors.bottom: true

      // Close any panel with Esc without requiring focus
      Shortcut {
        sequences: ["Escape"]
        enabled: root.active
        onActivated: root.close()
        context: Qt.WindowShortcut
      }

      // Clicking outside of the rectangle to close
      MouseArea {
        anchors.fill: parent
        enabled: root.backgroundClickEnabled
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: root.close()
      }

      // The actual panel's content
      NShapedRectangle {
        id: panelBackground

        backgroundColor: (attachedToBar && (topLeftInverted || topRightInverted || bottomLeftInverted || bottomRightInverted)) ? Qt.alpha(panelBackgroundColor, Settings.data.bar.backgroundOpacity) : panelBackgroundColor

        topLeftRadius: Style.radiusL
        topRightRadius: Style.radiusL
        bottomLeftRadius: Style.radiusL
        bottomRightRadius: Style.radiusL

        // Set inverted corners based on panel anchors and bar position

        // Top-left corner
        topLeftInverted: {
          if (!attachedToBar)
            return false

          // Inverted if panel is anchored to top edge (bar is at top)
          if (effectivePanelAnchorTop)
            return true
          // Or if panel is anchored to left edge (bar is at left)
          if (effectivePanelAnchorLeft)
            return true
          return false
        }
        topLeftInvertedDirection: effectivePanelAnchorTop ? "horizontal" : "vertical"

        // Top-right corner
        topRightInverted: {
          if (!attachedToBar)
            return false

          // Inverted if panel is anchored to top edge (bar is at top)
          if (effectivePanelAnchorTop)
            return true
          // Or if panel is anchored to right edge (bar is at right)
          if (effectivePanelAnchorRight)
            return true
          return false
        }
        topRightInvertedDirection: effectivePanelAnchorTop ? "horizontal" : "vertical"

        // Bottom-left corner
        bottomLeftInverted: {
          if (!attachedToBar)
            return false

          // Inverted if panel is anchored to bottom edge (bar is at bottom)
          if (effectivePanelAnchorBottom)
            return true
          // Or if panel is anchored to left edge (bar is at left)
          if (effectivePanelAnchorLeft)
            return true
          return false
        }
        bottomLeftInvertedDirection: effectivePanelAnchorBottom ? "horizontal" : "vertical"

        // Bottom-right corner
        bottomRightInverted: {
          if (!attachedToBar)
            return false

          // Inverted if panel is anchored to bottom edge (bar is at bottom)
          if (effectivePanelAnchorBottom)
            return true
          // Or if panel is anchored to right edge (bar is at right)
          if (effectivePanelAnchorRight)
            return true
          return false
        }
        bottomRightInvertedDirection: effectivePanelAnchorBottom ? "horizontal" : "vertical"

        // Dragging support
        property bool draggable: root.draggable
        property bool isDragged: false
        property real manualX: 0
        property real manualY: 0
        width: {
          var w
          if (root.preferredWidthRatio !== undefined) {
            w = Math.round(Math.max(screen?.width * root.preferredWidthRatio, root.preferredWidth))
          } else {
            w = root.preferredWidth
          }
          // Clamp width so it is never bigger than the screen
          return Math.min(w, screen?.width - Style.marginL * 2)
        }
        height: {
          var h
          if (root.preferredHeightRatio !== undefined) {
            h = Math.round(Math.max(screen?.height * root.preferredHeightRatio, root.preferredHeight))
          } else {
            h = root.preferredHeight
          }

          // Clamp height so it is never bigger than the screen
          return Math.min(h, screen?.height - Style.barHeight - Style.marginL * 2)
        }

        opacity: root.panelBackgroundOpacity
        x: isDragged ? manualX : calculatedX
        y: isDragged ? manualY : calculatedY

        // Animate width and height changes smoothly
        Behavior on width {
          enabled: !panelBackground.isDragged
          NumberAnimation {
            duration: Style.animationFast
            easing.type: Easing.InOutQuad
          }
        }

        Behavior on height {
          enabled: !panelBackground.isDragged
          NumberAnimation {
            duration: Style.animationFast
            easing.type: Easing.InOutQuad
          }
        }

        // ---------------------------------------------
        // Does not account for corners are they are negligible and helps keep the code clean.
        // ---------------------------------------------
        property real marginTop: {
          if (!barIsVisible) {
            return 0
          }

          switch (barPosition) {
          case "top":
            return (Style.barHeight + (attachedToBar ? 0 : Style.marginS)) + (Settings.data.bar.floating ? Math.round(Settings.data.bar.marginVertical * Style.marginXL) : 0)
          default:
            return attachedToBar ? 0 : Style.marginS
          }
        }

        property real marginBottom: {
          if (!barIsVisible) {
            return 0
          }
          switch (barPosition) {
          case "bottom":
            return (Style.barHeight + (attachedToBar ? 0 : Style.marginS)) + (Settings.data.bar.floating ? Math.round(Settings.data.bar.marginVertical * Style.marginXL) : 0)
          default:
            return attachedToBar ? 0 : Style.marginS
          }
        }

        property real marginLeft: {
          if (!barIsVisible) {
            return 0
          }
          switch (barPosition) {
          case "left":
            return (Style.barHeight + (attachedToBar ? 0 : Style.marginS)) + (Settings.data.bar.floating ? Math.round(Settings.data.bar.marginHorizontal * Style.marginXL) : 0)
          default:
            return attachedToBar ? 0 : Style.marginS
          }
        }

        property real marginRight: {
          if (!barIsVisible) {
            return 0
          }
          switch (barPosition) {
          case "right":
            return (Style.barHeight + (attachedToBar ? 0 : Style.marginS)) + (Settings.data.bar.floating ? Math.round(Settings.data.bar.marginHorizontal * Style.marginXL) : 0)
          default:
            return attachedToBar ? 0 : Style.marginS
          }
        }

        // ---------------------------------------------
        property int calculatedX: {
          // Priority to fixed anchoring
          if (panelAnchorHorizontalCenter) {
            // Center horizontally but respect bar margins
            var centerX = Math.round((panelWindow.width - panelBackground.width) / 2)
            var minX = marginLeft
            var maxX = panelWindow.width - panelBackground.width - marginRight
            return Math.round(Math.max(minX, Math.min(centerX, maxX)))
          } else if (panelAnchorLeft) {
            return marginLeft
          } else if (panelAnchorRight) {
            return Math.round(panelWindow.width - panelBackground.width - marginRight)
          }

          // No fixed anchoring
          if (barIsVertical) {
            // Vertical bar
            if (barPosition === "right") {
              // To the left of the right bar
              return Math.round(panelWindow.width - panelBackground.width - marginRight)
            } else {
              // To the right of the left bar
              return marginLeft
            }
          } else {
            // Horizontal bar
            if (root.useButtonPosition) {
              // Position panel relative to button
              var targetX = buttonPosition.x + (buttonWidth / 2) - (panelBackground.width / 2)
              // Keep panel within screen bounds
              var maxX = panelWindow.width - panelBackground.width - marginRight
              var minX = marginLeft

              if (Settings.data.bar.floating) {
                maxX -= Settings.data.bar.marginHorizontal * Style.marginXL * 10
                minX += Settings.data.bar.marginHorizontal * Style.marginXL * 10
              }
              return Math.round(Math.max(minX, Math.min(targetX, maxX)))
            } else {
              // Fallback to center horizontally
              return Math.round((panelWindow.width - panelBackground.width) / 2)
            }
          }
        }

        // ---------------------------------------------
        property int calculatedY: {
          // Priority to fixed anchoring
          if (panelAnchorVerticalCenter) {
            // Center vertically but respect bar margins
            var centerY = Math.round((panelWindow.height - panelBackground.height) / 2)
            var minY = marginTop
            var maxY = panelWindow.height - panelBackground.height - marginBottom
            return Math.round(Math.max(minY, Math.min(centerY, maxY)))
          } else if (panelAnchorTop) {
            return marginTop
          } else if (panelAnchorBottom) {
            return Math.round(panelWindow.height - panelBackground.height - marginBottom)
          }

          // No fixed anchoring
          if (barIsVertical) {
            // Vertical bar
            if (useButtonPosition) {
              // Position panel relative to button
              var targetY = buttonPosition.y + (buttonHeight / 2) - (panelBackground.height / 2)
              // Keep panel within screen bounds
              var maxY = panelWindow.height - panelBackground.height - marginBottom
              var minY = marginTop

              if (Settings.data.bar.floating) {
                maxY -= Settings.data.bar.marginHorizontal * Style.marginXL * 10
                minY += Settings.data.bar.marginHorizontal * Style.marginXL * 10
              }

              return Math.round(Math.max(minY, Math.min(targetY, maxY)))
            } else {
              // Fallback to center vertically
              return Math.round((panelWindow.height - panelBackground.height) / 2)
            }
          } else {
            // Horizontal bar
            if (barPosition === "bottom") {
              // Above the bottom bar
              return Math.round(panelWindow.height - panelBackground.height - marginBottom)
            } else {
              // Below the top bar
              return marginTop
            }
          }
        }

        // Animate in when component is completed
        Component.onCompleted: {
          // Start invisible
          // Use a timer to delay the animation start, allowing QML to properly set up initial state
          fadeInTimer.start()
        }

        Timer {
          id: fadeInTimer
          interval: 1
          repeat: false
          onTriggered: {
            // Fade in background
            root.panelBackgroundOpacity = 1.0
          }
        }

        // Timer to fade in content after slide animation completes
        Timer {
          id: contentFadeInTimer
          interval: Style.animationFast
          repeat: false
          running: true
          onTriggered: root.panelContentOpacity = 1.0
        }

        // Reset drag position when panel closes
        Connections {
          target: root
          function onClosed() {
            panelBackground.isDragged = false
          }
        }

        // Prevent closing when clicking in the panel bg
        MouseArea {
          anchors.fill: parent
        }

        // Animation behavior
        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationFast
            easing.type: Easing.OutQuad
          }
        }

        Loader {
          id: panelContentLoader
          anchors.fill: parent
          sourceComponent: root.panelContent
          opacity: root.panelContentOpacity

          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.OutQuad
            }
          }

          // Allow content to dynamically resize the panel
          onItemChanged: {
            if (item) {
              // Bind to content's preferredWidth/Height if they exist
              if (item.hasOwnProperty('contentPreferredWidth')) {
                root.preferredWidth = Qt.binding(() => item.contentPreferredWidth)
              }
              if (item.hasOwnProperty('contentPreferredHeight')) {
                root.preferredHeight = Qt.binding(() => item.contentPreferredHeight)
              }
              if (item.hasOwnProperty('contentPreferredWidthRatio')) {
                root.preferredWidthRatio = Qt.binding(() => item.contentPreferredWidthRatio)
              }
              if (item.hasOwnProperty('contentPreferredHeightRatio')) {
                root.preferredHeightRatio = Qt.binding(() => item.contentPreferredHeightRatio)
              }
            }
          }
        }

        // Handle drag move on the whole panel area
        DragHandler {
          id: dragHandler
          target: null
          enabled: panelBackground.draggable
          property real dragStartX: 0
          property real dragStartY: 0
          onActiveChanged: {
            if (active) {
              // Capture current position into manual coordinates BEFORE toggling isDragged
              panelBackground.manualX = panelBackground.x
              panelBackground.manualY = panelBackground.y
              dragStartX = panelBackground.x
              dragStartY = panelBackground.y
              panelBackground.isDragged = true
              if (root.enableBackgroundClick)
                root.disableBackgroundClick()
            } else {
              // Keep isDragged true so we continue using the manual x/y after release
              if (root.enableBackgroundClick)
                root.enableBackgroundClick()
            }
          }
          onTranslationChanged: {
            // Proposed new coordinates from fixed drag origin
            var nx = dragStartX + translation.x
            var ny = dragStartY + translation.y

            // Calculate gaps so we never overlap the bar on any side
            var baseGap = Style.marginS
            var floatExtraH = Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * 2 * Style.marginXL : 0
            var floatExtraV = Settings.data.bar.floating ? Settings.data.bar.marginVertical * 2 * Style.marginXL : 0

            var insetLeft = baseGap + ((barIsVisible && barPosition === "left") ? (Style.barHeight + floatExtraH) : 0)
            var insetRight = baseGap + ((barIsVisible && barPosition === "right") ? (Style.barHeight + floatExtraH) : 0)
            var insetTop = baseGap + ((barIsVisible && barPosition === "top") ? (Style.barHeight + floatExtraV) : 0)
            var insetBottom = baseGap + ((barIsVisible && barPosition === "bottom") ? (Style.barHeight + floatExtraV) : 0)

            // Clamp within screen bounds accounting for insets
            var maxX = panelWindow.width - panelBackground.width - insetRight
            var minX = insetLeft
            var maxY = panelWindow.height - panelBackground.height - insetBottom
            var minY = insetTop

            panelBackground.manualX = Math.round(Math.max(minX, Math.min(nx, maxX)))
            panelBackground.manualY = Math.round(Math.max(minY, Math.min(ny, maxY)))
          }
        }

        // Drag indicator border
        Rectangle {
          anchors.fill: parent
          anchors.margins: 0
          color: Color.transparent
          border.color: Color.mTertiary
          border.width: Style.borderM
          radius: Style.radiusL
          visible: panelBackground.isDragged && dragHandler.active
          opacity: 0.8
          z: 3000

          // Subtle glow effect
          Rectangle {
            anchors.fill: parent
            anchors.margins: 0
            color: Color.transparent
            border.color: Color.mTertiary
            border.width: Style.borderS
            radius: Style.radiusL
            opacity: 0.3
          }
        }
      }
    }
  }
}
