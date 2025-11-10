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

  implicitWidth: Math.max(160, contextMenuColumn.implicitWidth)
  implicitHeight: contextMenuColumn.implicitHeight + (Style.marginM * 2)
  color: Color.transparent
  visible: false

  function initItems() {
    // Is this a running app?
    const isRunning = root.toplevel && ToplevelManager && ToplevelManager.toplevels.values.includes(root.toplevel)

    // Is this a pinned app?
    const isPinned = root.toplevel && root.isAppPinned(root.toplevel.appId)

    var next = []
    if (isRunning) {
      // Focus item
      next.push({
                  "icon": "eye",
                  "text": I18n.tr("dock.menu.focus"),
                  "action": function () {
                    handleFocus()
                  }
                })
    }

    // Pin/Unpin item
    next.push({
                "icon": !isPinned ? "pin" : "unpin",
                "text": !isPinned ? I18n.tr("dock.menu.pin") : I18n.tr("dock.menu.unpin"),
                "action": function () {
                  handlePin()
                }
              })

    if (isRunning) {
      // Close item
      next.push({
                  "icon": "close",
                  "text": I18n.tr("dock.menu.close"),
                  "action": function () {
                    handleClose()
                  }
                })
    }

    // Create a menu entry for each app-specific action definied in its .desktop file
    if (typeof DesktopEntries !== 'undefined' && DesktopEntries.byId) {
      const entry = (DesktopEntries.heuristicLookup) ? DesktopEntries.heuristicLookup(appId) : DesktopEntries.byId(appId)
      if (entry != null) {
        entry.actions.forEach(function (action) {
          next.push({
                      "icon": "",
                      "text": action.name,
                      "action": function () {
                        action.execute()
                      }
                    })
        })
      }
    }

    root.items = next
  }

  // Helper functions for pin/unpin functionality
  function isAppPinned(appId) {
    if (!appId)
      return false
    const pinnedApps = Settings.data.dock.pinnedApps || []
    return pinnedApps.includes(appId)
  }

  function toggleAppPin(appId) {
    if (!appId)
      return

    let pinnedApps = (Settings.data.dock.pinnedApps || []).slice() // Create a copy
    const isPinned = pinnedApps.includes(appId)

    if (isPinned) {
      // Unpin: remove from array
      pinnedApps = pinnedApps.filter(id => id !== appId)
    } else {
      // Pin: add to array
      pinnedApps.push(appId)
    }

    // Update the settings
    Settings.data.dock.pinnedApps = pinnedApps
  }

  anchor.item: anchorItem
  anchor.rect.x: anchorItem ? (anchorItem.width - implicitWidth) / 2 : 0
  anchor.rect.y: anchorItem ? -implicitHeight - (Style.marginM) : 0

  function show(item, toplevelData) {
    if (!item) {
      return
    }

    anchorItem = item
    toplevel = toplevelData
    initItems()
    visible = true
    canAutoClose = false
    gracePeriodTimer.restart()
  }

  function hide() {
    visible = false
    root.items.length = 0
  }

  // Helper function to determine which menu item is under the mouse
  function getHoveredItem(mouseY) {
    const itemHeight = 32
    const startY = Style.marginM
    const relativeY = mouseY - startY

    if (relativeY < 0)
      return -1

    const itemIndex = Math.floor(relativeY / itemHeight)
    return itemIndex >= 0 && itemIndex < root.items.length ? itemIndex : -1
  }

  function handleFocus() {
    if (root.toplevel?.activate) {
      root.toplevel.activate()
    }
    root.requestClose()
  }

  function handlePin() {
    if (root.toplevel?.appId) {
      root.toggleAppPin(root.toplevel.appId)
    }
    root.requestClose()
  }

  function handleClose() {
    // Check if toplevel is still valid before trying to close it
    const isValidToplevel = root.toplevel && ToplevelManager && ToplevelManager.toplevels.values.includes(root.toplevel)

    if (isValidToplevel && root.toplevel.close) {
      root.toplevel.close()
      // Trigger immediate dock update callback if provided
      if (root.onAppClosed && typeof root.onAppClosed === "function") {
        Qt.callLater(root.onAppClosed)
      }
    }
    root.hide()
    root.requestClose()
  }

  // Short delay to ignore spurious events
  Timer {
    id: gracePeriodTimer
    interval: 1500
    repeat: false
    onTriggered: {
      root.canAutoClose = true
      if (!menuMouseArea.containsMouse) {
        closeTimer.start()
      }
    }
  }

  Timer {
    id: closeTimer
    interval: 500
    repeat: false
    running: false
    onTriggered: {
      root.hide()
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
        closeTimer.stop()
      }

      onExited: {
        root.hoveredItem = -1
        if (root.canAutoClose) {
          // Only close if grace period has passed
          closeTimer.start()
        }
      }

      onPositionChanged: mouse => {
                           root.hoveredItem = root.getHoveredItem(mouse.y)
                         }

      onClicked: mouse => {
                   const clickedItem = root.getHoveredItem(mouse.y)
                   if (clickedItem >= 0) {
                     root.items[clickedItem].action.call()
                   }
                 }
    }

    ColumnLayout {
      id: contextMenuColumn
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: 0

      Repeater {
        model: root.items

        Rectangle {
          Layout.fillWidth: true
          height: 32
          color: root.hoveredItem === index ? Color.mHover : Color.transparent
          radius: Style.radiusXS

          RowLayout {
            anchors.left: parent.left
            anchors.leftMargin: Style.marginS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.marginS

            NIcon {
              icon: modelData.icon
              pointSize: Style.fontSizeL
              color: root.hoveredItem === index ? Color.mOnHover : Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignVCenter
            }

            NText {
              text: modelData.text
              pointSize: Style.fontSizeS
              color: root.hoveredItem === index ? Color.mOnHover : Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignVCenter
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
