import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Generic full-screen popup window for menus and context menus
// This is a top-level PanelWindow (sibling to MainScreen, not nested inside it)
// Provides click-outside-to-close functionality for any popup content
// Loads TrayMenu by default but can show context menus via showContextMenu()
PanelWindow {
  id: root

  required property ShellScreen screen
  property string windowType: "popupmenu"  // Used for namespace and registration

  // Content item to display (set by the popup that uses this window)
  property var contentItem: null

  // Expose the trayMenu Loader directly (for backward compatibility)
  readonly property alias trayMenuLoader: trayMenuLoader

  // Dynamic context menu callback for items in other windows (e.g., desktop widgets)
  property var dynamicMenuCallback: null

  anchors.top: true
  anchors.left: true
  anchors.right: true
  anchors.bottom: true
  visible: false
  color: "transparent"

  // Use Top layer (same as MainScreen) for proper event handling
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: hasDialog ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  WlrLayershell.namespace: "noctalia-" + windowType + "-" + (screen?.name || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  // Track if a dialog is currently open (needed for keyboard focus)
  property bool hasDialog: false

  // Register with PanelService so widgets can find this window
  Component.onCompleted: {
    objectName = "popupMenuWindow-" + (screen?.name || "unknown");
    PanelService.registerPopupMenuWindow(screen, root);
  }

  // Load TrayMenu as the default content
  Loader {
    id: trayMenuLoader
    source: Quickshell.shellDir + "/Modules/Bar/Extras/TrayMenu.qml"
    onLoaded: {
      if (item) {
        item.screen = root.screen;
        // Set the loaded item as default content
        root.contentItem = item;
      }
    }
  }

  // Dynamic context menu - created as child of this window (Top layer) so input works correctly
  // Used for items in other windows like desktop widgets (bottom layer)
  NPopupContextMenu {
    id: dynamicMenu
    visible: false
    screen: root.screen
    minWidth: 180

    onTriggered: (action, item) => {
                   if (root.dynamicMenuCallback) {
                     // Callback returns true if it will handle closing (e.g., opening a dialog)
                     var handled = root.dynamicMenuCallback(action);
                     if (!handled) {
                       root.close();
                     }
                   } else {
                     root.close();
                   }
                 }
  }

  function open() {
    visible = true;
  }

  // Show a context menu (temporarily replaces TrayMenu as content)
  function showContextMenu(menu) {
    if (menu) {
      contentItem = menu;
      open();
    }
  }

  // Show a dynamic context menu with model and callback at screen coordinates
  // Used for items in other window layers (e.g., desktop widgets in bottom layer)
  function showDynamicContextMenu(model, screenX, screenY, callback) {
    dynamicMenu.model = model;
    dynamicMenuCallback = callback;

    // Use the anchor point item for positioning at absolute coordinates
    dynamicMenu.anchorItem = anchorPoint;
    anchorPoint.x = screenX;
    anchorPoint.y = screenY;

    contentItem = dynamicMenu;
    dynamicMenu.visible = true;
    open();
  }

  // Invisible anchor point for dynamic menu positioning
  Item {
    id: anchorPoint
    width: 1
    height: 1
  }

  // Hide just the dynamic menu without closing the popup window
  // Used when transitioning from context menu to a dialog
  function hideDynamicMenu() {
    dynamicMenu.visible = false;
  }

  function close() {
    visible = false;
    // Call close/hide method on current content
    if (contentItem) {
      if (typeof contentItem.hideMenu === "function") {
        contentItem.hideMenu();
      } else if (typeof contentItem.close === "function") {
        contentItem.close();
      }
    }
    // Hide dynamic menu
    dynamicMenu.visible = false;
    dynamicMenuCallback = null;
    // Restore TrayMenu as default content
    if (trayMenuLoader.item) {
      contentItem = trayMenuLoader.item;
    }
  }

  // Full-screen click catcher - click anywhere outside content closes the window
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: root.close()
  }

  // Container for dialogs that need a full-screen Item parent (e.g., Qt Popup)
  Item {
    id: dialogContainer
    anchors.fill: parent
  }

  // Expose the dialog container for external use
  readonly property alias dialogParent: dialogContainer
}
