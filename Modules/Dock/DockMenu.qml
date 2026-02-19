import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.UI
import qs.Widgets

PopupWindow {
  id: root

  property var toplevel: null
  property var appData: null
  property Item anchorItem: null
  property ShellScreen targetScreen: null

  property string menuMode: "app" // "app" or "launcher"
  property string launcherWidgetSection: ""
  property int launcherWidgetIndex: -1
  property var launcherWidgetSettings: ({})

  property bool hovered: menuHoverHandler.hovered
  property var onAppClosed: null // Callback function for when an app is closed
  property bool canAutoClose: false

  // Track which menu item is hovered
  property int hoveredItem: -1 // -1: none, otherwise the index of the item in `items`

  property var items: []

  signal requestClose

  property real menuContentWidth: 160
  property real menuMinWidth: 120
  property real menuMaxWidth: 360
  property real menuMaxHeight: Math.max(180, Math.min(420, Math.round((targetScreen ? targetScreen.height : 600) * 0.3)))
  property int separatorCompactHeight: 8
  property string forcedGroupMenuMode: ""
  readonly property int separatorIndex: {
    for (let i = 0; i < root.items.length; i++) {
      if (root.items[i] && root.items[i].separator === true)
        return i;
    }
    return -1;
  }
  readonly property bool splitExtendedLayout: separatorIndex >= 0
  readonly property var scrollItems: splitExtendedLayout ? root.items.slice(0, separatorIndex) : root.items
  readonly property var fixedItems: splitExtendedLayout ? root.items.slice(separatorIndex + 1) : []
  readonly property real menuInnerHeight: Math.max(0, implicitHeight - Style.marginXL)
  readonly property real fixedActionsHeight: listHeight(fixedItems)
  readonly property real separatorBlockHeight: splitExtendedLayout ? separatorCompactHeight : 0
  readonly property real scrollAreaHeight: splitExtendedLayout
    ? Math.max(0, menuInnerHeight - fixedActionsHeight - separatorBlockHeight)
    : menuInnerHeight
  readonly property bool listOverflowing: menuFlick && menuFlick.contentHeight > menuFlick.height
  readonly property real menuBodyHeight: {
    if (splitExtendedLayout) {
      return listHeight(scrollItems) + separatorBlockHeight + fixedActionsHeight;
    }
    return listHeight(root.items);
  }

  implicitWidth: menuContentWidth + (Style.marginXL)
  implicitHeight: Math.min(menuBodyHeight + (Style.marginXL), menuMaxHeight)
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
    // Keep menu readable without allowing extremely wide labels.
    menuContentWidth = Math.max(menuMinWidth, Math.min(menuMaxWidth, Math.ceil(maxWidth)));
  }

  function getCurrentAppId() {
    return appData?.appId || toplevel?.appId || "";
  }

  function getValidToplevels() {
    if (!ToplevelManager || !ToplevelManager.toplevels)
      return [];
    const source = appData?.toplevels && appData.toplevels.length > 0 ? appData.toplevels : (toplevel ? [toplevel] : []);
    const allToplevels = ToplevelManager.toplevels.values || [];
    return source.filter(window => window && allToplevels.includes(window));
  }

  function getPrimaryToplevel() {
    const windows = getValidToplevels();
    if (windows.length === 0)
      return null;
    if (ToplevelManager && ToplevelManager.activeToplevel && windows.includes(ToplevelManager.activeToplevel))
      return ToplevelManager.activeToplevel;
    return windows[0];
  }

  function isItemActionable(index) {
    if (index < 0 || index >= root.items.length)
      return false;
    const item = root.items[index];
    return item && typeof item.action === "function";
  }

  function rowHeightForItem(item) {
    return item && item.separator === true ? 16 : 32;
  }

  function listHeight(items) {
    let total = 0;
    if (!items)
      return total;
    for (let i = 0; i < items.length; i++) {
      total += rowHeightForItem(items[i]);
    }
    return total;
  }

  function initItems() {
    if (menuMode === "launcher") {
      root.items = [
            {
              "icon": "adjustments",
              "text": I18n.tr("actions.dock-settings"),
              "action": function () {
                handleDockSettings();
              }
            },
            {
              "icon": "adjustments",
              "text": I18n.tr("actions.launcher-settings"),
              "action": function () {
                handleLauncherSettings();
              }
            },
            {
              "icon": "settings",
              "text": I18n.tr("actions.widget-settings"),
              "action": function () {
                handleLauncherWidgetSettings();
              }
            }
          ];
      calculateMenuWidth();
      return;
    }

    const windows = getValidToplevels();
    const primaryToplevel = getPrimaryToplevel();
    const appId = getCurrentAppId();
    const isRunning = windows.length > 0;
    const isPinned = isAppPinned(appId);
    const grouped = Settings.data.dock.groupApps && windows.length > 1;
    const rawGroupMenuMode = forcedGroupMenuMode || Settings.data.dock.groupContextMenuMode || "extended";
    const menuModeForGroup = grouped ? ((rawGroupMenuMode === "list" || rawGroupMenuMode === "extended") ? rawGroupMenuMode : "extended") : "single";

    var next = [];

    if (!grouped || menuModeForGroup === "single") {
      if (isRunning) {
        next.push({
                    "icon": "eye",
                    "text": I18n.tr("common.focus"),
                    "action": function () {
                      handleFocus(primaryToplevel);
                    }
                  });
      }

      next.push({
                  "icon": !isPinned ? "pin" : "unpin",
                  "text": !isPinned ? I18n.tr("common.pin") : I18n.tr("common.unpin"),
                  "action": function () {
                    handlePin(appId);
                  }
                });

      if (isRunning) {
        next.push({
                    "icon": "close",
                    "text": I18n.tr("common.close"),
                    "action": function () {
                      handleClose(primaryToplevel);
                    }
                  });
      }
    } else {
      windows.forEach((window, index) => {
        const windowTitle = (window.title && window.title.trim() !== "") ? window.title : (appId || ("Window " + (index + 1)));
        next.push({
                    "icon": window === ToplevelManager?.activeToplevel ? "circle-filled" : "square-rounded",
                    "text": windowTitle,
                    "action": function () {
                      handleFocus(window);
                    }
                  });
      });

      if (menuModeForGroup === "extended") {
        next.push({
                    "separator": true
                  });
        next.push({
                    "icon": "eye",
                    "text": I18n.tr("common.focus"),
                    "action": function () {
                      handleFocus(primaryToplevel);
                    }
                  });
        next.push({
                    "icon": !isPinned ? "pin" : "unpin",
                    "text": !isPinned ? I18n.tr("common.pin") : I18n.tr("common.unpin"),
                    "action": function () {
                      handlePin(appId);
                    }
                  });
        next.push({
                    "icon": "close",
                    "text": I18n.tr("common.close") + " All",
                    "action": function () {
                      handleCloseAll(windows);
                    }
                  });
      }
    }

    // Keep grouped list mode as a clean window switcher.
    const canAddDesktopActions = !grouped || menuModeForGroup === "extended";

    // Create a menu entry for each app-specific action defined in its .desktop file
    if (canAddDesktopActions && typeof DesktopEntries !== 'undefined' && DesktopEntries.byId && appId) {
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
                        if (Settings.data.dock.dockType === "static") {
                          const panel = PanelService.getPanel("staticDockPanel", root.screen, false);
                          if (panel)
                            panel.close();
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

  // Dock position for context menu placement
  property string dockPosition: "bottom"

  anchor.item: anchorItem
  // Position menu on opposite side of dock with comfortable spacing
  anchor.rect.x: {
    if (!anchorItem)
      return 0;
    switch (dockPosition) {
    case "left":
      return anchorItem.width + Style.marginL; // Open to right of dock
    case "right":
      return -implicitWidth - Style.marginL; // Open to left of dock
    default:
      return (anchorItem.width - implicitWidth) / 2; // Center horizontally
    }
  }
  anchor.rect.y: {
    if (!anchorItem)
      return 0;
    switch (dockPosition) {
    case "top":
      return anchorItem.height + Style.marginL; // Open below dock
    case "bottom":
      return -implicitHeight - Style.marginL; // Open above dock (default)
    case "left":
    case "right":
      return (anchorItem.height - implicitHeight) / 2; // Center vertically
    default:
      return -implicitHeight - Style.marginL;
    }
  }

  function show(item, toplevelData, screen, groupModeOverride) {
    if (!item) {
      return;
    }

    // First hide completely
    visible = false;

    // Then set up new data
    anchorItem = item;
    if (toplevelData && typeof toplevelData === "object" && (toplevelData.appId !== undefined || toplevelData.toplevels !== undefined)) {
      appData = toplevelData;
      toplevel = toplevelData.toplevel || null;
    } else {
      appData = toplevelData ? {
        "appId": toplevelData.appId,
        "toplevel": toplevelData,
        "toplevels": toplevelData ? [toplevelData] : []
      } : null;
      toplevel = toplevelData;
    }
    targetScreen = screen || null;
    forcedGroupMenuMode = groupModeOverride || "";
    initItems();

    visible = true;
    canAutoClose = false;
    gracePeriodTimer.restart();
  }

  // Helper function to determine which menu item is under the mouse
  function getHoveredItem(mouseY) {
    const startY = Style.marginM;
    const localY = mouseY - startY;

    if (localY < 0)
      return -1;

    function findIndexInList(items, relativeY, baseIndex) {
      let offset = 0;
      for (let i = 0; i < items.length; i++) {
        const h = rowHeightForItem(items[i]);
        if (relativeY >= offset && relativeY < offset + h)
          return baseIndex + i;
        offset += h;
      }
      return -1;
    }

    if (splitExtendedLayout) {
      if (localY < scrollAreaHeight) {
        return findIndexInList(scrollItems, localY + (menuFlick ? menuFlick.contentY : 0), 0);
      }
      if (localY < scrollAreaHeight + separatorBlockHeight) {
        return -1;
      }
      return findIndexInList(fixedItems, localY - scrollAreaHeight - separatorBlockHeight, separatorIndex + 1);
    } else {
      return findIndexInList(scrollItems, localY + (menuFlick ? menuFlick.contentY : 0), 0);
    }
  }

  function fixedItemGlobalIndex(localIndex) {
    if (!splitExtendedLayout)
      return localIndex;
    return separatorIndex + 1 + localIndex;
  }

  function isScrollableHovered(mouseY) {
    const localY = mouseY - Style.marginM;
    return localY >= 0 && localY < scrollAreaHeight;
  }

  function onWheelScroll(deltaY) {
    if (!menuFlick || menuFlick.contentHeight <= menuFlick.height)
      return;
    const nextY = menuFlick.contentY - deltaY;
    menuFlick.contentY = Math.max(0, Math.min(nextY, menuFlick.contentHeight - menuFlick.height));
  }

  function resetMenuState() {
    root.items.length = 0;
    root.appData = null;
    root.toplevel = null;
    root.forcedGroupMenuMode = "";
    menuContentWidth = menuMinWidth;
    hoveredItem = -1;
    if (menuFlick)
      menuFlick.contentY = 0;
  }

  function hide() {
    visible = false;
    resetMenuState();
  }

  function hideWithoutReset() {
    visible = false;
  }

  function closeAndReset() {
    hide();
    root.requestClose();
  }

  function handleFocus(targetToplevel) {
    if (targetToplevel?.activate) {
      targetToplevel.activate();
    }
    closeAndReset();
  }

  function handlePin(appId) {
    if (appId) {
      root.toggleAppPin(appId);
    }
    closeAndReset();
  }

  function handleClose(targetToplevel) {
    const isValidToplevel = targetToplevel && ToplevelManager && ToplevelManager.toplevels.values.includes(targetToplevel);

    if (isValidToplevel && targetToplevel.close) {
      targetToplevel.close();
      if (root.onAppClosed && typeof root.onAppClosed === "function") {
        Qt.callLater(root.onAppClosed);
      }
    }
    closeAndReset();
  }

  function handleCloseAll(windows) {
    windows.forEach(window => {
                    if (window && ToplevelManager && ToplevelManager.toplevels.values.includes(window) && window.close) {
                      window.close();
                    }
                  });
    if (root.onAppClosed && typeof root.onAppClosed === "function") {
      Qt.callLater(root.onAppClosed);
    }
    closeAndReset();
  }

  function handleLauncherSettings() {
    if (targetScreen) {
      var panel = PanelService.getPanel("settingsPanel", targetScreen);
      panel.requestedTab = SettingsPanel.Tab.Launcher;
      panel.toggle();
    }
    closeAndReset();
  }

  function handleDockSettings() {
    if (targetScreen) {
      var panel = PanelService.getPanel("settingsPanel", targetScreen);
      panel.requestedTab = SettingsPanel.Tab.Dock;
      panel.toggle();
    }
    closeAndReset();
  }

  function handleLauncherWidgetSettings() {
    if (targetScreen && launcherWidgetSection && launcherWidgetIndex >= 0) {
      BarService.openWidgetSettings(targetScreen, launcherWidgetSection, launcherWidgetIndex, "Launcher", launcherWidgetSettings || {});
    }
    closeAndReset();
  }

  // Short delay to ignore spurious events
  Timer {
    id: gracePeriodTimer
    interval: 1500
    repeat: false
    onTriggered: {
      root.canAutoClose = true;
      if (!menuHoverHandler.hovered) {
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
      root.hideWithoutReset();
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Color.mSurfaceVariant
    radius: Style.radiusS
    border.color: Color.mOutline
    border.width: Style.borderS

    HoverHandler {
      id: menuHoverHandler
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onHoveredChanged: {
        if (hovered) {
          closeTimer.stop();
        } else {
          root.hoveredItem = -1;
          if (root.canAutoClose) {
            closeTimer.start();
          }
        }
      }
    }

    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: event => {
                 if (!root.isScrollableHovered(event.y))
                   return;
                 const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
                 root.onWheelScroll(delta);
                 event.accepted = true;
               }
    }

    Flickable {
      id: menuFlick
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.marginM
      anchors.rightMargin: Style.marginM
      anchors.topMargin: Style.marginM
      height: root.scrollAreaHeight
      clip: true
      contentWidth: width
      contentHeight: scrollColumn.height
      flickableDirection: Flickable.VerticalFlick
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      ScrollBar.vertical: ScrollBar {
        id: menuScrollBar
        policy: ScrollBar.AsNeeded
        visible: root.listOverflowing
        interactive: true
        hoverEnabled: true
      }

      Column {
        id: scrollColumn
        width: menuFlick.width 
        spacing: 0

        Repeater {
          model: root.scrollItems

          Rectangle {
            readonly property bool isSeparator: modelData && modelData.separator === true
            width: scrollColumn.width
            height: root.rowHeightForItem(modelData)
            color: (!isSeparator && root.hoveredItem === index) ? Color.mHover : "transparent"
            radius: Style.radiusXS

            Row {
              id: rowLayout
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.marginS
              anchors.rightMargin: Style.marginS
              spacing: Style.marginS
              visible: !isSeparator

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
                width: rowLayout.width - ((modelData.icon && modelData.icon !== "") ? (Style.fontSizeL + Style.marginS) : 0)
                elide: Text.ElideRight
              }
            }

            MouseArea {
              anchors.fill: parent
              enabled: !parent.isSeparator && root.isItemActionable(index)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton

              onEntered: {
                root.hoveredItem = index;
              }

              onExited: {
                if (root.hoveredItem === index) {
                  root.hoveredItem = -1;
                }
              }

              onClicked: {
                if (root.isItemActionable(index)) {
                  root.items[index].action.call();
                }
              }
            }
          }
        }
      }
    }

    Rectangle {
      visible: root.splitExtendedLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: menuFlick.bottom
      anchors.leftMargin: Style.marginS
      anchors.rightMargin: Style.marginS
      height: Style.borderS
      color: Qt.alpha(Color.mOutline, 0.7)
      radius: Style.radiusXS
    }

    Column {
      id: fixedColumn
      visible: root.splitExtendedLayout && root.fixedItems.length > 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.marginM
      anchors.rightMargin: Style.marginM
      anchors.bottomMargin: Style.marginM
      anchors.top: menuFlick.bottom
      anchors.topMargin: root.separatorBlockHeight
      spacing: 0

      Repeater {
        model: root.fixedItems

        Rectangle {
          readonly property int globalIndex: root.fixedItemGlobalIndex(index)
          width: fixedColumn.width
          height: root.rowHeightForItem(modelData)
          color: root.hoveredItem === globalIndex ? Color.mHover : "transparent"
          radius: Style.radiusXS

          Row {
            id: fixedRowLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.marginS
            anchors.rightMargin: Style.marginS
            spacing: Style.marginS

            NIcon {
              icon: modelData.icon
              pointSize: Style.fontSizeL
              color: root.hoveredItem === parent.globalIndex ? Color.mOnHover : Color.mOnSurfaceVariant
              visible: icon !== ""
              anchors.verticalCenter: parent.verticalCenter
            }

            NText {
              text: modelData.text
              pointSize: Style.fontSizeS
              color: root.hoveredItem === parent.globalIndex ? Color.mOnHover : Color.mOnSurfaceVariant
              anchors.verticalCenter: parent.verticalCenter
              width: fixedRowLayout.width - ((modelData.icon && modelData.icon !== "") ? (Style.fontSizeL + Style.marginS) : 0)
              elide: Text.ElideRight
            }
          }

          MouseArea {
            anchors.fill: parent
            enabled: root.isItemActionable(parent.globalIndex)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton

            onEntered: {
              root.hoveredItem = parent.globalIndex;
            }

            onExited: {
              if (root.hoveredItem === parent.globalIndex) {
                root.hoveredItem = -1;
              }
            }

            onClicked: {
              if (root.isItemActionable(parent.globalIndex)) {
                root.items[parent.globalIndex].action.call();
              }
            }
          }
        }
      }
    }
  }
}
