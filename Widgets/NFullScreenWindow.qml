import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services


/**
 * NFullScreenWindow - Single PanelWindow per screen that manages all panels and the bar
 */
PanelWindow {
  id: root

  required property var barComponent
  required property var panelComponents

  // Shadow properties
  property real shadowOpacity: 1.0
  property real shadowBlur: 1.0
  property real shadowHorizontalOffset: Settings.data.general.shadowOffsetX
  property real shadowVerticalOffset: Settings.data.general.shadowOffsetY

  property color black: "#000000"
  property color white: "#ffffff"

  Component.onCompleted: {
    Logger.d("NFullScreenWindow", "Initialized for screen:", screen?.name, "- Dimensions:", screen?.width, "x", screen?.height, "- Position:", screen?.x, ",", screen?.y)
  }

  // Debug: Log mask region changes
  onMaskChanged: {
    Logger.d("NFullScreenWindow", "Mask changed!")
    Logger.d("NFullScreenWindow", "  Bar region:", barLoader.item?.barRegion)
    Logger.d("NFullScreenWindow", "  Panel count:", panelsRepeater.count)
    for (var i = 0; i < panelsRepeater.count; i++) {
      var panelItem = panelsRepeater.itemAt(i)?.item
      Logger.d("NFullScreenWindow", "  Panel", i, "- open:", panelItem?.isPanelOpen, "- region:", panelItem?.panelRegion)
    }
  }

  // Wayland
  // Always use Exclusive keyboard focus when a panel is open
  // This ensures all keyboard shortcuts work reliably (Escape, etc.)
  // The centralized shortcuts in this window handle delegation to panels
  WlrLayershell.keyboardFocus: root.isPanelOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  WlrLayershell.layer: Settings.data.ui.panelsOverlayLayer ? WlrLayer.Overlay : WlrLayer.Top
  WlrLayershell.namespace: "noctalia-screen-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore // Don't reserve space - BarExclusionZone handles that

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Desktop dimming when panels are open
  property bool dimDesktop: Settings.data.general.dimDesktop
  property bool isPanelOpen: PanelService.openedPanel !== null
  color: {
    if (dimDesktop && isPanelOpen) {
      return Qt.alpha(Color.mSurfaceVariant, Style.opacityHeavy)
    }
    return Color.transparent
  }

  Behavior on color {
    ColorAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutQuad
    }
  }

  function updateMask() {
    // Build the regions list
    var regionsList = [barMaskRegion]

    // Add background region if a panel is open
    // This makes the background clickable (not click-through) so we can detect clicks to close panels
    if (root.isPanelOpen) {
      regionsList.push(backgroundMaskRegion)
    }

    // Add regions for each open panel
    // Only include panels that are open AND not closing (to allow click-through during close animation)
    for (var i = 0; i < panelMaskRepeater.count; i++) {
      var wrapperItem = panelMaskRepeater.itemAt(i)
      if (wrapperItem && wrapperItem.maskRegion) {
        var panelItem = wrapperItem.panelItem
        if (panelItem && panelItem.isPanelOpen && !panelItem.isClosing) {
          var panelRegion = panelItem.panelRegion
          // Update the mask region's coordinates from the panel's actual region
          if (panelRegion) {
            wrapperItem.maskRegion.x = panelRegion.x
            wrapperItem.maskRegion.y = panelRegion.y
            wrapperItem.maskRegion.width = panelRegion.width
            wrapperItem.maskRegion.height = panelRegion.height
            regionsList.push(wrapperItem.maskRegion)
          }
        }
      }
    }

    // Update the mask's regions
    clickableMask.regions = regionsList
  }

  // Listen to PanelService to update mask when panels open/close
  Connections {
    target: PanelService
    function onWillOpen() {
      root.updateMask()
    }
    function onDidClose() {
      // Delay mask update to ensure panel's isPanelOpen is updated first
      Qt.callLater(() => root.updateMask())
    }
  }

  // Background region - for closing panels when clicking outside (separate from mask)
  Region {
    id: backgroundMaskRegion
    x: 0
    y: 0
    width: root.width
    height: root.height
    intersection: Intersection.Subtract
  }

  // Smart mask: Make everything click-through except bar and open panels
  mask: Region {
    id: clickableMask

    // Cover entire window (everything is masked/click-through)
    x: 0
    y: 0
    width: root.width
    height: root.height
    intersection: Intersection.Xor

    // Regions list is set programmatically in updateMask()
    // Initially just the bar
    regions: [barMaskRegion]

    // Bar region - subtract bar area from mask
    Region {
      id: barMaskRegion
      property var barRegion: barLoader.item && barLoader.item.barRegion ? barLoader.item.barRegion : null

      x: barRegion ? barRegion.x : 0
      y: barRegion ? barRegion.y : 0
      width: barRegion ? barRegion.width : 0
      height: barRegion ? barRegion.height : 0
      intersection: Intersection.Subtract

      // Update mask when bar geometry changes
      onWidthChanged: Qt.callLater(() => root.updateMask())
      onHeightChanged: Qt.callLater(() => root.updateMask())
    }
  }

  // Container for panel mask regions (created dynamically)
  Item {
    id: panelMaskRegions

    // Create a Region for each panel
    Repeater {
      id: panelMaskRepeater
      model: panelsRepeater.count

      delegate: Item {
        required property int index
        property var panelItem: panelsRepeater.itemAt(index)?.item
        property var region: panelItem && panelItem.panelRegion ? panelItem.panelRegion : null

        // The actual mask region as a child
        property alias maskRegion: panelMask

        Region {
          id: panelMask
          // Coordinates are set programmatically in updateMask()
          intersection: Intersection.Subtract
        }
      }
    }
  }

  // Container for all UI elements
  Item {
    id: container
    width: root.width
    height: root.height

    // Apply shadow effect
    layer.enabled: Settings.data.general.enableShadows
    layer.smooth: true
    // layer.textureSize: {
    //   var dpr = CompositorService.getDisplayScale(screen.name)
    //   return Qt.size(width * dpr, height * dpr)
    // }
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowOpacity: root.shadowOpacity
      shadowHorizontalOffset: root.shadowHorizontalOffset
      shadowVerticalOffset: root.shadowVerticalOffset
      shadowColor: black
      blur: root.shadowBlur
      blurMax: 32
    }

    // Screen corners (integrated to avoid separate PanelWindow)
    // Always positioned at actual screen edges
    Loader {
      id: screenCornersLoader
      active: Settings.data.general.showScreenCorners

      anchors.fill: parent
      z: 1000 // Very high z-index to be on top of everything

      sourceComponent: Item {
        id: cornersRoot
        anchors.fill: parent

        property color cornerColor: Settings.data.general.forceBlackScreenCorners ? black : Qt.alpha(Color.mSurface, Settings.data.bar.backgroundOpacity)
        property real cornerRadius: Style.screenRadius
        property real cornerSize: Style.screenRadius

        // Top-left concave corner
        Canvas {
          id: topLeftCorner
          anchors.top: parent.top
          anchors.left: parent.left
          width: cornersRoot.cornerSize
          height: cornersRoot.cornerSize
          antialiasing: true
          renderTarget: Canvas.FramebufferObject
          smooth: true

          onPaint: {
            const ctx = getContext("2d")
            if (!ctx)
              return

            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = Qt.rgba(cornersRoot.cornerColor.r, cornersRoot.cornerColor.g, cornersRoot.cornerColor.b, cornersRoot.cornerColor.a)
            ctx.fillRect(0, 0, width, height)
            ctx.globalCompositeOperation = "destination-out"
            ctx.fillStyle = white
            ctx.beginPath()
            ctx.arc(width, height, cornersRoot.cornerRadius, 0, 2 * Math.PI)
            ctx.fill()
          }

          onWidthChanged: if (available)
                            requestPaint()
          onHeightChanged: if (available)
                             requestPaint()
        }

        // Top-right concave corner
        Canvas {
          id: topRightCorner
          anchors.top: parent.top
          anchors.right: parent.right
          width: cornersRoot.cornerSize
          height: cornersRoot.cornerSize
          antialiasing: true
          renderTarget: Canvas.FramebufferObject
          smooth: true

          onPaint: {
            const ctx = getContext("2d")
            if (!ctx)
              return

            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = Qt.rgba(cornersRoot.cornerColor.r, cornersRoot.cornerColor.g, cornersRoot.cornerColor.b, cornersRoot.cornerColor.a)
            ctx.fillRect(0, 0, width, height)
            ctx.globalCompositeOperation = "destination-out"
            ctx.fillStyle = white
            ctx.beginPath()
            ctx.arc(0, height, cornersRoot.cornerRadius, 0, 2 * Math.PI)
            ctx.fill()
          }

          onWidthChanged: if (available)
                            requestPaint()
          onHeightChanged: if (available)
                             requestPaint()
        }

        // Bottom-left concave corner
        Canvas {
          id: bottomLeftCorner
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          width: cornersRoot.cornerSize
          height: cornersRoot.cornerSize
          antialiasing: true
          renderTarget: Canvas.FramebufferObject
          smooth: true

          onPaint: {
            const ctx = getContext("2d")
            if (!ctx)
              return

            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = Qt.rgba(cornersRoot.cornerColor.r, cornersRoot.cornerColor.g, cornersRoot.cornerColor.b, cornersRoot.cornerColor.a)
            ctx.fillRect(0, 0, width, height)
            ctx.globalCompositeOperation = "destination-out"
            ctx.fillStyle = white
            ctx.beginPath()
            ctx.arc(width, 0, cornersRoot.cornerRadius, 0, 2 * Math.PI)
            ctx.fill()
          }

          onWidthChanged: if (available)
                            requestPaint()
          onHeightChanged: if (available)
                             requestPaint()
        }

        // Bottom-right concave corner
        Canvas {
          id: bottomRightCorner
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          width: cornersRoot.cornerSize
          height: cornersRoot.cornerSize
          antialiasing: true
          renderTarget: Canvas.FramebufferObject
          smooth: true

          onPaint: {
            const ctx = getContext("2d")
            if (!ctx)
              return

            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = Qt.rgba(cornersRoot.cornerColor.r, cornersRoot.cornerColor.g, cornersRoot.cornerColor.b, cornersRoot.cornerColor.a)
            ctx.fillRect(0, 0, width, height)
            ctx.globalCompositeOperation = "destination-out"
            ctx.fillStyle = white
            ctx.beginPath()
            ctx.arc(0, 0, cornersRoot.cornerRadius, 0, 2 * Math.PI)
            ctx.fill()
          }

          onWidthChanged: if (available)
                            requestPaint()
          onHeightChanged: if (available)
                             requestPaint()
        }

        // Repaint all corners when color or radius changes
        onCornerColorChanged: {
          if (topLeftCorner.available)
            topLeftCorner.requestPaint()
          if (topRightCorner.available)
            topRightCorner.requestPaint()
          if (bottomLeftCorner.available)
            bottomLeftCorner.requestPaint()
          if (bottomRightCorner.available)
            bottomRightCorner.requestPaint()
        }

        onCornerRadiusChanged: {
          if (topLeftCorner.available)
            topLeftCorner.requestPaint()
          if (topRightCorner.available)
            topRightCorner.requestPaint()
          if (bottomLeftCorner.available)
            bottomLeftCorner.requestPaint()
          if (bottomRightCorner.available)
            bottomRightCorner.requestPaint()
        }
      }
    }

    // Background MouseArea for closing panels when clicking outside
    // Active whenever a panel is open - the mask ensures it only receives clicks when panel is open
    MouseArea {
      anchors.fill: parent
      enabled: root.isPanelOpen
      onClicked: {
        if (PanelService.openedPanel) {
          PanelService.openedPanel.close()
        }
      }
      z: 0 // Behind panels and bar
    }

    // All panels (as Items, not PanelWindows)
    Repeater {
      id: panelsRepeater
      model: root.panelComponents

      delegate: Loader {
        id: panelLoader

        // Lazy load panels - only create when first requested
        // Panel stays loaded once created for faster subsequent opens
        active: false
        asynchronous: false
        sourceComponent: modelData.component

        // Fill the container so panels have proper parent dimensions
        anchors.fill: parent

        // Panel properties binding
        property var panelScreen: root.screen
        property string panelId: modelData.id
        property int panelZIndex: modelData.zIndex || 50
        property bool hasBeenRequested: false

        Component.onCompleted: {
          // Register the loader immediately so PanelService can load it on-demand
          var objectName = panelId + "-" + (panelScreen?.name || "unknown")
          PanelService.registerPanelLoader(panelLoader, objectName)
        }

        // Activate loader when panel is first requested
        function ensureLoaded() {
          if (!hasBeenRequested) {
            Logger.d("NFullScreenWindow", "Loading panel on-demand:", panelId)
            hasBeenRequested = true
            active = true
          }
        }

        onLoaded: {
          if (item) {
            // Set unique objectName per screen BEFORE registration: "calendarPanel-DP-1"
            item.objectName = panelId + "-" + (panelScreen?.name || "unknown")
            item.screen = panelScreen
            PanelService.registerPanel(item)
            Logger.d("NFullScreenWindow", "Panel loaded with objectName:", item.objectName, "on screen:", panelScreen?.name)
          }
        }
      }
    }

    // Bar (always on top)
    Loader {
      id: barLoader
      asynchronous: false
      sourceComponent: root.barComponent
      // Keep bar loaded but hide it when BarService.isVisible is false
      // This allows panels to remain accessible via IPC
      visible: BarService.isVisible

      // Fill parent to provide dimensions for Bar to reference
      anchors.fill: parent

      property ShellScreen screen: root.screen

      onLoaded: {
        Logger.d("NFullScreenWindow", "Bar loaded:", item !== null)
        if (item) {
          Logger.d("NFullScreenWindow", "Bar screen", item.screen?.name, "size:", item.width, "x", item.height)
          // Bind screen to bar component (use binding for reactivity)
          item.screen = Qt.binding(function () {
            return barLoader.screen
          })
        }
      }
    }
  }

  // Centralized keyboard shortcuts - delegate to opened panel
  // This ensures shortcuts work regardless of panel focus state
  Shortcut {
    sequence: "Escape"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onEscapePressed) {
        PanelService.openedPanel.onEscapePressed()
      } else if (PanelService.openedPanel) {
        PanelService.openedPanel.close()
      }
    }
  }

  Shortcut {
    sequence: "Tab"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onTabPressed) {
        PanelService.openedPanel.onTabPressed()
      }
    }
  }

  Shortcut {
    sequence: "Shift+Tab"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onShiftTabPressed) {
        PanelService.openedPanel.onShiftTabPressed()
      }
    }
  }

  Shortcut {
    sequence: "Up"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onUpPressed) {
        PanelService.openedPanel.onUpPressed()
      }
    }
  }

  Shortcut {
    sequence: "Down"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onDownPressed) {
        PanelService.openedPanel.onDownPressed()
      }
    }
  }

  Shortcut {
    sequence: "Return"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onReturnPressed) {
        PanelService.openedPanel.onReturnPressed()
      }
    }
  }

  Shortcut {
    sequence: "Enter"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onReturnPressed) {
        PanelService.openedPanel.onReturnPressed()
      }
    }
  }

  Shortcut {
    sequence: "Home"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onHomePressed) {
        PanelService.openedPanel.onHomePressed()
      }
    }
  }

  Shortcut {
    sequence: "End"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onEndPressed) {
        PanelService.openedPanel.onEndPressed()
      }
    }
  }

  Shortcut {
    sequence: "PgUp"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onPageUpPressed) {
        PanelService.openedPanel.onPageUpPressed()
      }
    }
  }

  Shortcut {
    sequence: "PgDown"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onPageDownPressed) {
        PanelService.openedPanel.onPageDownPressed()
      }
    }
  }

  Shortcut {
    sequence: "Ctrl+J"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onCtrlJPressed) {
        PanelService.openedPanel.onCtrlJPressed()
      }
    }
  }

  Shortcut {
    sequence: "Ctrl+K"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onCtrlKPressed) {
        PanelService.openedPanel.onCtrlKPressed()
      }
    }
  }

  Shortcut {
    sequence: "Left"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onLeftPressed) {
        PanelService.openedPanel.onLeftPressed()
      }
    }
  }

  Shortcut {
    sequence: "Right"
    enabled: root.isPanelOpen
    onActivated: {
      if (PanelService.openedPanel && PanelService.openedPanel.onRightPressed) {
        PanelService.openedPanel.onRightPressed()
      }
    }
  }
}
