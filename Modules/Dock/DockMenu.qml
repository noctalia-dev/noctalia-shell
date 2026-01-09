import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Widgets

PopupWindow {
  id: root

  property var toplevel: null
  property Item anchorItem: null

  property bool hovered: menuMouseArea.containsMouse
  property var onAppClosed: null // Callback function for when an app is closed
  property bool canAutoClose: false

  // Track which menu item is hovered
  property int hoveredItem: -1 // -1: none, otherwise the index of the item in `items`

  property var items: []

  signal requestClose

  property real menuContentWidth: 160

  implicitWidth: menuContentWidth + (Style.marginM * 2)
  implicitHeight: contextMenuColumn.implicitHeight + (Style.marginM * 2)
  color: "transparent"
  visible: false

  // Hidden text element for measuring text width
  NText {
    id: textMeasure
    visible: false
    pointSize: Style.fontSizeS
    family: "Sans Serif" // Match your NText font if different
    wrapMode: Text.NoWrap
    elide: Text.ElideNone
  }

  // Calculate the maximum width needed for all menu items
  function calculateMenuWidth() {
    let maxWidth = 0; // Start with 0, we'll apply minimum later
    if (root.items && root.items.length > 0) {
      for (let i = 0; i < root.items.length; i++) {
        const item = root.items[i];
        if (item && item.text) {
          // Calculate width: margins + icon (if present) + spacing + text width
          let itemWidth = Style.marginS * 2; // left and right margins

          if (item.icon && item.icon !== "") {
            itemWidth += Style.fontSizeL + Style.marginS; // icon + spacing
          }

          // Measure actual text width
          textMeasure.text = item.text;
          const textWidth = textMeasure.contentWidth;
          itemWidth += textWidth;

          if (itemWidth > maxWidth) {
            maxWidth = itemWidth;
          }
        }
      }
    }
    // Apply a reasonable minimum width (like 120px)
    menuContentWidth = Math.max(120, Math.ceil(maxWidth));
  }

  function initItems() {
    // Is this a running app?
    const isRunning = root.toplevel && ToplevelManager && ToplevelManager.toplevels.values.includes(root.toplevel);

    // Is this a pinned app?
    const isPinned = root.toplevel && root.isAppPinned(root.toplevel.appId);

    var next = [];
    if (isRunning) {
      // Focus item
      next.push({
                  "icon": "eye",
                  "text": I18n.tr("common.focus"),
                  "action": function () {
                    handleFocus();
                  }
                });
    }

    // Pin/Unpin item
    next.push({
                "icon": !isPinned ? "pin" : "unpin",
                "text": !isPinned ? I18n.tr("common.pin") : I18n.tr("common.unpin"),
                "action": function () {
                  handlePin();
                }
              });

    if (isRunning) {
      // Close item
      next.push({
                  "icon": "close",
                  "text": I18n.tr("common.close"),
                  "action": function () {
                    handleClose();
                  }
                });
    }

    // Create a menu entry for each app-specific action definied in its .desktop file
    if (typeof DesktopEntries !== 'undefined' && DesktopEntries.byId && root.toplevel?.appId) {
      const appId = root.toplevel.appId;
      const entry = (DesktopEntries.heuristicLookup) ? DesktopEntries.heuristicLookup(appId) : DesktopEntries.byId(appId);
      if (entry != null) {
        entry.actions.forEach(function (action) {
          next.push({
                      "icon": "chevron-right",
                      "text": action.name,
                      "action": function () {
                        if (action.command && action.command.length > 0) {
                          Quickshell.execDetached(action.command);
                        } else if (action.execute) {
                          action.execute();
                        }
                      }
                    });
        });
      }
    }

    root.items = next;
    // Force width recalculation when items change
    calculateMenuWidth();
  }

  // Helper function to normalize app IDs for case-insensitive matching
  function normalizeAppId(appId) {
    if (!appId || typeof appId !== 'string')
      return "";
    return appId.toLowerCase().trim();
  }

  // Helper function to get desktop entry ID from an app ID
  function getDesktopEntryId(appId) {
    if (!appId)
      return appId;

    // Try to find the desktop entry using heuristic lookup
    if (typeof DesktopEntries !== 'undefined' && DesktopEntries.heuristicLookup) {
      try {
        const entry = DesktopEntries.heuristicLookup(appId);
        if (entry && entry.id) {
          return entry.id;
        }
      } catch (e)
        // Fall through to return original appId
      {}
    }

    // Try direct lookup
    if (typeof DesktopEntries !== 'undefined' && DesktopEntries.byId) {
      try {
        const entry = DesktopEntries.byId(appId);
        if (entry && entry.id) {
          return entry.id;
        }
      } catch (e)
        // Fall through to return original appId
      {}
    }

    // Return original appId if we can't find a desktop entry
    return appId;
  }

  // Helper functions for pin/unpin functionality
  function isAppPinned(appId) {
    if (!appId)
      return false;
    const pinnedApps = Settings.data.dock.pinnedApps || [];
    const normalizedId = normalizeAppId(appId);
    return pinnedApps.some(pinnedId => normalizeAppId(pinnedId) === normalizedId);
  }

  function toggleAppPin(appId) {
    if (!appId)
      return;

    // Get the desktop entry ID for consistent pinning
    const desktopEntryId = getDesktopEntryId(appId);
    const normalizedId = normalizeAppId(desktopEntryId);

    let pinnedApps = (Settings.data.dock.pinnedApps || []).slice(); // Create a copy

    // Find existing pinned app with case-insensitive matching
    const existingIndex = pinnedApps.findIndex(pinnedId => normalizeAppId(pinnedId) === normalizedId);
    const isPinned = existingIndex >= 0;

    if (isPinned) {
      // Unpin: remove from array
      pinnedApps.splice(existingIndex, 1);
    } else {
      // Pin: add desktop entry ID to array
      pinnedApps.push(desktopEntryId);
    }

    // Update the settings
    Settings.data.dock.pinnedApps = pinnedApps;
  }

  anchor.item: anchorItem
  anchor.rect.x: anchorItem ? (anchorItem.width - implicitWidth) / 2 : 0
  anchor.rect.y: anchorItem ? -implicitHeight - (Style.marginM) : 0

  function show(item, toplevelData) {
    if (!item) {
      return;
    }

    // First hide completely
    visible = false;

    // Then set up new data
    anchorItem = item;
    toplevel = toplevelData;
    initItems();

    // Force a complete re-evaluation by waiting for the next frame
    Qt.callLater(() => {
                   Qt.callLater(() => {
                                  visible = true;
                                  canAutoClose = false;
                                  gracePeriodTimer.restart();
                                });
                 });
  }

  function hide() {
    visible = false;
    root.items.length = 0;
    menuContentWidth = 120; // Reset to minimum
  }

  // Helper function to determine which menu item is under the mouse
  function getHoveredItem(mouseY) {
    const itemHeight = 32;
    const startY = Style.marginM;
    const relativeY = mouseY - startY;

    if (relativeY < 0)
      return -1;

    const itemIndex = Math.floor(relativeY / itemHeight);
    return itemIndex >= 0 && itemIndex < root.items.length ? itemIndex : -1;
  }

  function handleFocus() {
    if (root.toplevel?.activate) {
      root.toplevel.activate();
    }
    root.requestClose();
  }

  function handlePin() {
    if (root.toplevel?.appId) {
      root.toggleAppPin(root.toplevel.appId);
    }
    root.requestClose();
  }

  function handleClose() {
    // Check if toplevel is still valid before trying to close it
    const isValidToplevel = root.toplevel && ToplevelManager && ToplevelManager.toplevels.values.includes(root.toplevel);

    if (isValidToplevel && root.toplevel.close) {
      root.toplevel.close();
      // Trigger immediate dock update callback if provided
      if (root.onAppClosed && typeof root.onAppClosed === "function") {
        Qt.callLater(root.onAppClosed);
      }
    }
    root.hide();
    root.requestClose();
  }

  // Short delay to ignore spurious events
  Timer {
    id: gracePeriodTimer
    interval: 1500
    repeat: false
    onTriggered: {
      root.canAutoClose = true;
      if (!menuMouseArea.containsMouse) {
        closeTimer.start();
      }
    }
  }

  Timer {
    id: closeTimer
    interval: 500
    repeat: false
    running: false
    onTriggered: {
      root.hide();
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Color.mSurfaceVariant
    radius: Style.radiusS
    border.color: Color.mOutline
    border.width: Style.borderS

    // Single MouseArea to handle both auto-close and menu interactions
    MouseArea {
      id: menuMouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: root.hoveredItem >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor

      onEntered: {
        closeTimer.stop();
      }

      onExited: {
        root.hoveredItem = -1;
        if (root.canAutoClose) {
          // Only close if grace period has passed
          closeTimer.start();
        }
      }

      onPositionChanged: mouse => {
                           root.hoveredItem = root.getHoveredItem(mouse.y);
                         }

      onClicked: mouse => {
                   const clickedItem = root.getHoveredItem(mouse.y);
                   if (clickedItem >= 0) {
                     root.items[clickedItem].action.call();
                   }
                 }
    }

    ColumnLayout {
      id: contextMenuColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.marginM
      spacing: 0

      Repeater {
        model: root.items

        Rectangle {
          Layout.fillWidth: true
          height: 32
          color: root.hoveredItem === index ? Color.mHover : "transparent"
          radius: Style.radiusXS

          Row {
            id: rowLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.marginS
            anchors.rightMargin: Style.marginS
            spacing: Style.marginS

            NIcon {
              icon: modelData.icon
              pointSize: Style.fontSizeL
              color: root.hoveredItem === index ? Color.mOnHover : Color.mOnSurfaceVariant
              visible: icon !== ""
              anchors.verticalCenter: parent.verticalCenter
            }

            NText {
              text: modelData.text
              pointSize: Style.fontSizeS
              color: root.hoveredItem === index ? Color.mOnHover : Color.mOnSurfaceVariant
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }
    }
  }
}
