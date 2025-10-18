import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

Loader {
  id: root

  property ShellScreen screen

  property Component panelContent: null
  property real preferredWidth: 700
  property real preferredHeight: 900
  property real preferredWidthRatio
  property real preferredHeightRatio
  property color panelBackgroundColor: Color.mSurface
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
  readonly property real originalScale: 0.0
  property real scaleValue: originalScale
  property real dimmingOpacity: 0

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
    scaleValue = originalScale
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

      readonly property string barPosition: Settings.data.bar.position
      readonly property bool isVertical: barPosition === "left" || barPosition === "right"
      readonly property bool barIsVisible: (screen !== null) && (Settings.data.bar.monitors.includes(screen.name) || (Settings.data.bar.monitors.length === 0))
      readonly property real verticalBarWidth: Style.barHeight

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

      visible: true
      color: Settings.data.general.dimDesktop ? Qt.alpha(Color.mShadow, dimmingOpacity) : Color.transparent

      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-panel"
      WlrLayershell.layer: WlrLayer.Overlay
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
        onClicked: root.close()
      }

      // The actual panel's content
      Rectangle {
        id: panelBackground
        color: panelBackgroundColor
        radius: Style.radiusL
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS)
        // Dragging support
        property bool draggable: root.draggable
        property bool isDragged: false
        property real manualX: 0
        property real manualY: 0
        width: {
          var w
          if (preferredWidthRatio !== undefined) {
            w = Math.round(Math.max(screen?.width * preferredWidthRatio, preferredWidth))
          } else {
            w = preferredWidth
          }
          // Clamp width so it is never bigger than the screen
          return Math.min(w, screen?.width - Style.marginL * 2)
        }
        height: {
          var h
          if (preferredHeightRatio !== undefined) {
            h = Math.round(Math.max(screen?.height * preferredHeightRatio, preferredHeight))
          } else {
            h = preferredHeight
          }

          // Clamp width so it is never bigger than the screen
          return Math.min(h, screen?.height - Style.barHeight - Style.marginL * 2)
        }

        scale: root.scaleValue
        x: isDragged ? manualX : calculatedX
        y: isDragged ? manualY : calculatedY

        // ---------------------------------------------
        // Does not account for corners are they are negligible and helps keep the code clean.
        // ---------------------------------------------
        property real marginTop: {
          if (!barIsVisible) {
            return 0
          }
          switch (barPosition) {
          case "top":
            return (Style.barHeight + Style.marginS) + (Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL : 0)
          default:
            return Style.marginS
          }
        }

        property real marginBottom: {
          if (!barIsVisible) {
            return 0
          }
          switch (barPosition) {
          case "bottom":
            return (Style.barHeight + Style.marginS) + (Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL : 0)
          default:
            return Style.marginS
          }
        }

        property real marginLeft: {
          if (!barIsVisible) {
            return 0
          }
          switch (barPosition) {
          case "left":
            return (Style.barHeight + Style.marginS) + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0)
          default:
            return Style.marginS
          }
        }

        property real marginRight: {
          if (!barIsVisible) {
            return 0
          }
          switch (barPosition) {
          case "right":
            return (Style.barHeight + Style.marginS) + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0)
          default:
            return Style.marginS
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
          if (isVertical) {
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
          if (isVertical) {
            // Vertical bar
            if (useButtonPosition) {
              // Position panel relative to button
              var targetY = buttonPosition.y + (buttonHeight / 2) - (panelBackground.height / 2)
              // Keep panel within screen bounds
              var maxY = panelWindow.height - panelBackground.height - marginBottom
              var minY = marginTop
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
          root.scaleValue = 1.0
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

        // Animation behaviors
        Behavior on scale {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutExpo
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutQuad
          }
        }

        Loader {
          id: panelContentLoader
          anchors.fill: parent
          sourceComponent: root.panelContent
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
          border.color: Color.mPrimary
          border.width: Math.max(2, Style.borderL)
          radius: parent.radius
          visible: panelBackground.isDragged && dragHandler.active
          opacity: 0.8
          z: 3000

          // Subtle glow effect
          Rectangle {
            anchors.fill: parent
            anchors.margins: 0
            color: Color.transparent
            border.color: Color.mPrimary
            border.width: Math.max(1, Style.borderS)
            radius: parent.radius
            opacity: 0.3
          }
        }
      }
    }
  }
}
