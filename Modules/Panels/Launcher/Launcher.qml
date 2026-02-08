import QtQuick
import QtQuick.Controls
import Quickshell

import qs.Commons
import qs.Modules.MainScreen
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  // Disable when overlay mode is enabled (LauncherOverlayWindow handles it)
  enabled: !Settings.data.appLauncher.overviewLayer
  visible: !Settings.data.appLauncher.overviewLayer

  // Reference to core (set after panelContent loads)
  property var launcherCoreRef: null

  // Expose core launcher for external access (e.g., IPC)
  readonly property string searchText: launcherCoreRef ? launcherCoreRef.searchText : ""
  readonly property int selectedIndex: launcherCoreRef ? launcherCoreRef.selectedIndex : 0
  readonly property var results: launcherCoreRef ? launcherCoreRef.results : []
  readonly property var activeProvider: launcherCoreRef ? launcherCoreRef.activeProvider : null
  readonly property var currentProvider: launcherCoreRef ? launcherCoreRef.currentProvider : null
  readonly property bool isGridView: launcherCoreRef ? launcherCoreRef.isGridView : false
  readonly property int gridColumns: launcherCoreRef ? launcherCoreRef.gridColumns : 5

  function setSearchText(text) {
    if (launcherCoreRef)
      launcherCoreRef.setSearchText(text);
  }

  // Preview panel support
  readonly property bool previewActive: {
    if (!launcherCoreRef)
      return false;
    var provider = launcherCoreRef.activeProvider;
    if (!provider || !provider.hasPreview)
      return false;
    if (!Settings.data.appLauncher.enableClipPreview)
      return false;
    return selectedIndex >= 0 && results && !!results[selectedIndex];
  }
  readonly property int previewPanelWidth: Math.round(400 * Style.uiScaleRatio)

  // Panel sizing
  readonly property int listPanelWidth: Math.round(500 * Style.uiScaleRatio)
  readonly property int totalBaseWidth: listPanelWidth + (Style.marginL * 2)

  preferredWidth: totalBaseWidth
  preferredHeight: Math.round(600 * Style.uiScaleRatio)
  preferredWidthRatio: 0.25
  preferredHeightRatio: 0.5

  // Positioning
  readonly property string screenBarPosition: Settings.getBarPositionForScreen(screen?.name)
  readonly property string panelPosition: {
    if (Settings.data.appLauncher.position === "follow_bar") {
      if (screenBarPosition === "left" || screenBarPosition === "right") {
        return `center_${screenBarPosition}`;
      } else {
        return `${screenBarPosition}_center`;
      }
    } else {
      return Settings.data.appLauncher.position;
    }
  }
  panelAnchorHorizontalCenter: panelPosition === "center" || panelPosition.endsWith("_center")
  panelAnchorVerticalCenter: panelPosition === "center"
  panelAnchorLeft: panelPosition !== "center" && panelPosition.endsWith("_left")
  panelAnchorRight: panelPosition !== "center" && panelPosition.endsWith("_right")
  panelAnchorBottom: panelPosition.startsWith("bottom_")
  panelAnchorTop: panelPosition.startsWith("top_")

  panelContent: Rectangle {
    id: ui
    color: "transparent"
    opacity: launcherCore.resultsReady ? 1.0 : 0.0

    Component.onCompleted: root.launcherCoreRef = launcherCore

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCirc
      }
    }

    // Preview Panel (external) - uses provider's preview component
    NBox {
      id: previewBox
      visible: root.previewActive
      width: root.previewPanelWidth
      height: Math.round(400 * Style.uiScaleRatio)
      x: root.panelAnchorRight ? -(root.previewPanelWidth + Style.marginM) : ui.width + Style.marginM
      y: {
        var view = launcherCore.resultsView;
        if (!view)
          return Style.marginL;
        var row = launcherCore.isGridView ? Math.floor(launcherCore.selectedIndex / launcherCore.gridColumns) : launcherCore.selectedIndex;
        var gridCellSize = Math.floor((root.listPanelWidth - (2 * Style.marginXS) - ((launcherCore.targetGridColumns - 1) * Style.marginS)) / launcherCore.targetGridColumns);
        var itemHeight = launcherCore.isGridView ? (gridCellSize + Style.marginXXS) : (launcherCore.entryHeight + (view.spacing || 0));
        var yPos = row * itemHeight - (view.contentY || 0);
        var mapped = view.mapToItem(ui, 0, yPos);
        return Math.max(Style.marginL, Math.min(mapped.y, ui.height - previewBox.height - Style.marginL));
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
        active: root.previewActive
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

    // Core launcher (state, providers, UI)
    LauncherCore {
      id: launcherCore
      anchors.fill: parent
      screen: root.screen
      isOpen: root.isPanelOpen
      onRequestClose: root.close()
      onRequestCloseImmediately: root.closeImmediately()
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
