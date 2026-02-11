import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

import qs.Commons
import qs.Modules.MainScreen.Backgrounds
import qs.Services.UI
import qs.Widgets

// Standalone launcher window for Overlay layer mode.
// This window appears above fullscreen windows and does not attach to the bar.
Variants {
  id: launcherVariants

  model: Quickshell.screens.filter(screen => Settings.data.appLauncher.overviewLayer)

  delegate: Loader {
    id: windowLoader

    required property ShellScreen modelData

    active: PanelService.overlayLauncherOpen && PanelService.overlayLauncherScreen === modelData

    sourceComponent: PanelWindow {
      id: launcherWindow
      screen: windowLoader.modelData

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      color: "transparent"

      WlrLayershell.namespace: "noctalia-launcher-overlay-" + (screen?.name || "unknown")
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.exclusionMode: ExclusionMode.Ignore

      // Positioning logic (respects settings but doesn't attach to bar)
      readonly property string barPosition: Settings.data.bar.position
      readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
      readonly property int barThickness: Math.round(Style.barHeight + Style.marginL)

      readonly property string panelPosition: {
        var pos = Settings.data.appLauncher.position;
        if (pos === "follow_bar") {
          if (barIsVertical) {
            return "center_" + barPosition;
          } else {
            return barPosition + "_center";
          }
        }
        return pos;
      }

      // Preview panel support
      readonly property int listPanelWidth: Math.round(500 * Style.uiScaleRatio)
      readonly property int previewPanelWidth: Math.round(400 * Style.uiScaleRatio)
      readonly property bool previewActive: {
        if (!launcherCore)
          return false;
        var provider = launcherCore.activeProvider;
        if (!provider || !provider.hasPreview)
          return false;
        if (!Settings.data.appLauncher.enableClipPreview)
          return false;
        return launcherCore.selectedIndex >= 0 && launcherCore.results && !!launcherCore.results[launcherCore.selectedIndex];
      }

      // Dimmer background (click to close)
      Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Color.mSurface, Settings.data.general.dimmerOpacity)

        MouseArea {
          anchors.fill: parent
          onClicked: PanelService.closeOverlayLauncher()
        }
      }

      // Shadow for launcher panel
      NDropShadow {
        source: launcherPanel
        anchors.fill: launcherPanel
        autoPaddingEnabled: true
      }

      // Launcher panel with position-based anchoring
      Item {
        id: launcherPanel
        width: Math.round(Math.max(parent.width * 0.25, launcherWindow.listPanelWidth + (Style.marginL * 2)))
        height: Math.round(Math.max(parent.height * 0.5, 600 * Style.uiScaleRatio))
        clip: false

        // Entrance animation
        opacity: 0
        transformOrigin: {
          if (touchingTop && touchingLeft)
            return Item.TopLeft;
          if (touchingTop && touchingRight)
            return Item.TopRight;
          if (touchingBottom && touchingLeft)
            return Item.BottomLeft;
          if (touchingBottom && touchingRight)
            return Item.BottomRight;
          if (touchingTop)
            return Item.Top;
          if (touchingBottom)
            return Item.Bottom;
          if (touchingLeft)
            return Item.Left;
          if (touchingRight)
            return Item.Right;
          return Item.Center;
        }

        Component.onCompleted: {
          opacity = 1;
        }

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutCubic
          }
        }

        // Horizontal positioning
        anchors.horizontalCenter: (panelPosition === "center" || panelPosition.endsWith("_center")) ? parent.horizontalCenter : undefined
        anchors.left: panelPosition.endsWith("_left") ? parent.left : undefined
        anchors.right: panelPosition.endsWith("_right") ? parent.right : undefined

        // Vertical positioning
        anchors.verticalCenter: (panelPosition === "center" || panelPosition.startsWith("center_")) ? parent.verticalCenter : undefined
        anchors.top: panelPosition.startsWith("top_") ? parent.top : undefined
        anchors.bottom: panelPosition.startsWith("bottom_") ? parent.bottom : undefined

        // Margins - only add bar clearance on the bar's edge
        anchors.leftMargin: barPosition === "left" ? barThickness : 0
        anchors.rightMargin: barPosition === "right" ? barThickness : 0
        anchors.topMargin: barPosition === "top" ? barThickness : 0
        anchors.bottomMargin: barPosition === "bottom" ? barThickness : 0

        // Edge detection - based on position setting and bar location
        readonly property bool touchingLeft: panelPosition.endsWith("_left") && barPosition !== "left"
        readonly property bool touchingRight: panelPosition.endsWith("_right") && barPosition !== "right"
        readonly property bool touchingTop: panelPosition.startsWith("top_") && barPosition !== "top"
        readonly property bool touchingBottom: panelPosition.startsWith("bottom_") && barPosition !== "bottom"

        // Corner states based on edge touching
        // State 0: Normal rounded, State 1: Horizontal inversion, State 2: Vertical inversion
        readonly property int topLeftCornerState: {
          if (touchingLeft && touchingTop)
            return 0;
          if (touchingLeft)
            return 2;
          if (touchingTop)
            return 1;
          return 0;
        }
        readonly property int topRightCornerState: {
          if (touchingRight && touchingTop)
            return 0;
          if (touchingRight)
            return 2;
          if (touchingTop)
            return 1;
          return 0;
        }
        readonly property int bottomLeftCornerState: {
          if (touchingLeft && touchingBottom)
            return 0;
          if (touchingLeft)
            return 2;
          if (touchingBottom)
            return 1;
          return 0;
        }
        readonly property int bottomRightCornerState: {
          if (touchingRight && touchingBottom)
            return 0;
          if (touchingRight)
            return 2;
          if (touchingBottom)
            return 1;
          return 0;
        }

        // Background with inverted corners - extends beyond panel for inverted corners
        Shape {
          id: panelShape
          // Extend shape to allow inverted corners to render outside panel bounds
          x: -radius
          y: -radius
          width: launcherPanel.width + radius * 2
          height: launcherPanel.height + radius * 2
          opacity: launcherPanel.opacity
          layer.enabled: true

          readonly property real radius: Style.radiusL

          // Panel dimensions (for path calculations)
          readonly property real panelW: launcherPanel.width
          readonly property real panelH: launcherPanel.height

          // Helper functions for corner rendering
          function getMultX(state) {
            return state === 1 ? -1 : 1;
          }
          function getMultY(state) {
            return state === 2 ? -1 : 1;
          }
          function getArcDir(multX, multY) {
            return ((multX < 0) !== (multY < 0)) ? PathArc.Counterclockwise : PathArc.Clockwise;
          }

          readonly property real tlMultX: getMultX(launcherPanel.topLeftCornerState)
          readonly property real tlMultY: getMultY(launcherPanel.topLeftCornerState)
          readonly property real trMultX: getMultX(launcherPanel.topRightCornerState)
          readonly property real trMultY: getMultY(launcherPanel.topRightCornerState)
          readonly property real blMultX: getMultX(launcherPanel.bottomLeftCornerState)
          readonly property real blMultY: getMultY(launcherPanel.bottomLeftCornerState)
          readonly property real brMultX: getMultX(launcherPanel.bottomRightCornerState)
          readonly property real brMultY: getMultY(launcherPanel.bottomRightCornerState)

          ShapePath {
            strokeWidth: -1
            fillColor: Color.mSurfaceVariant

            // Offset by radius to account for Shape's extended bounds
            startX: panelShape.radius + panelShape.radius * panelShape.tlMultX
            startY: panelShape.radius

            // Top edge
            PathLine {
              relativeX: panelShape.panelW - panelShape.radius * panelShape.tlMultX - panelShape.radius * panelShape.trMultX
              relativeY: 0
            }
            // Top-right corner
            PathArc {
              relativeX: panelShape.radius * panelShape.trMultX
              relativeY: panelShape.radius * panelShape.trMultY
              radiusX: panelShape.radius
              radiusY: panelShape.radius
              direction: panelShape.getArcDir(panelShape.trMultX, panelShape.trMultY)
            }
            // Right edge
            PathLine {
              relativeX: 0
              relativeY: panelShape.panelH - panelShape.radius * panelShape.trMultY - panelShape.radius * panelShape.brMultY
            }
            // Bottom-right corner
            PathArc {
              relativeX: -panelShape.radius * panelShape.brMultX
              relativeY: panelShape.radius * panelShape.brMultY
              radiusX: panelShape.radius
              radiusY: panelShape.radius
              direction: panelShape.getArcDir(panelShape.brMultX, panelShape.brMultY)
            }
            // Bottom edge
            PathLine {
              relativeX: -(panelShape.panelW - panelShape.radius * panelShape.brMultX - panelShape.radius * panelShape.blMultX)
              relativeY: 0
            }
            // Bottom-left corner
            PathArc {
              relativeX: -panelShape.radius * panelShape.blMultX
              relativeY: -panelShape.radius * panelShape.blMultY
              radiusX: panelShape.radius
              radiusY: panelShape.radius
              direction: panelShape.getArcDir(panelShape.blMultX, panelShape.blMultY)
            }
            // Left edge
            PathLine {
              relativeX: 0
              relativeY: -(panelShape.panelH - panelShape.radius * panelShape.blMultY - panelShape.radius * panelShape.tlMultY)
            }
            // Top-left corner
            PathArc {
              relativeX: panelShape.radius * panelShape.tlMultX
              relativeY: -panelShape.radius * panelShape.tlMultY
              radiusX: panelShape.radius
              radiusY: panelShape.radius
              direction: panelShape.getArcDir(panelShape.tlMultX, panelShape.tlMultY)
            }
          }
        }

        // Border
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          radius: Style.radiusL
          border.color: Style.boxBorderColor
          border.width: Style.borderS
          visible: !launcherPanel.touchingLeft && !launcherPanel.touchingRight && !launcherPanel.touchingTop && !launcherPanel.touchingBottom
        }

        LauncherCore {
          id: launcherCore
          anchors.fill: parent
          screen: windowLoader.modelData
          isOpen: true
          onRequestClose: PanelService.closeOverlayLauncher()
          onRequestCloseImmediately: PanelService.closeOverlayLauncherImmediately()

          Component.onCompleted: PanelService.overlayLauncherCore = launcherCore
          Component.onDestruction: PanelService.overlayLauncherCore = null
        }

        // Preview Panel - clipboard preview positioned outside panel bounds
        NDropShadow {
          source: previewBox
          anchors.fill: previewBox
          autoPaddingEnabled: true
          visible: previewBox.visible
        }

        NBox {
          id: previewBox
          visible: launcherWindow.previewActive
          width: launcherWindow.previewPanelWidth
          height: Math.round(400 * Style.uiScaleRatio)
          x: panelPosition.endsWith("_right") ? -(launcherWindow.previewPanelWidth + Style.marginM) : launcherPanel.width + Style.marginM
          y: {
            var view = launcherCore.resultsView;
            if (!view)
              return Style.marginL;
            var row = launcherCore.isGridView ? Math.floor(launcherCore.selectedIndex / launcherCore.gridColumns) : launcherCore.selectedIndex;
            var gridCellSize = Math.floor((launcherWindow.listPanelWidth - (2 * Style.marginXS) - ((launcherCore.targetGridColumns - 1) * Style.marginS)) / launcherCore.targetGridColumns);
            var itemHeight = launcherCore.isGridView ? (gridCellSize + Style.marginXXS) : (launcherCore.entryHeight + (view.spacing || 0));
            var yPos = row * itemHeight - (view.contentY || 0);
            var mapped = view.mapToItem(launcherPanel, 0, yPos);
            return Math.max(Style.marginL, Math.min(mapped.y, launcherPanel.height - previewBox.height - Style.marginL));
          }
          z: -1

          opacity: visible ? 1.0 : 0.0
          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
            }
          }
          Behavior on y {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.OutCubic
            }
          }

          Loader {
            id: previewLoader
            anchors.fill: parent
            active: launcherWindow.previewActive
            source: {
              if (!active)
                return "";
              var provider = launcherCore.activeProvider;
              if (provider && provider.previewComponentPath)
                return provider.previewComponentPath;
              return "";
            }

            onLoaded: updatePreviewItem()
            onItemChanged: updatePreviewItem()

            function updatePreviewItem() {
              if (!item || launcherCore.selectedIndex < 0 || !launcherCore.results[launcherCore.selectedIndex])
                return;
              var provider = launcherCore.activeProvider;
              if (provider && provider.getPreviewData) {
                item.currentItem = provider.getPreviewData(launcherCore.results[launcherCore.selectedIndex]);
              } else {
                item.currentItem = launcherCore.results[launcherCore.selectedIndex];
              }
            }
          }
        }

        // Update preview when selection changes
        Connections {
          target: launcherCore
          function onSelectedIndexChanged() {
            if (previewLoader.item)
              previewLoader.updatePreviewItem();
          }
        }
      }
    }
  }
}
