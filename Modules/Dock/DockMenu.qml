import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Widgets
import qs.Services.Compositor

PopupWindow {
  id: root

  property var menuData: null 
  property string menuType: "workspace" 
  property Item anchorItem: null

  property bool hovered: menuMouseArea.containsMouse
  property var onAppClosed: null
  property bool canAutoClose: false

  property int hoveredItem: -1
  property var items: []

  signal requestClose

  implicitWidth: Math.max(160, contextMenuColumn.implicitWidth)
  implicitHeight: contextMenuColumn.implicitHeight + (Style.marginM * 2)
  color: Color.transparent
  visible: false

  function initItems() {
    var next = [];
    
    if (menuType === "pinned") {
        next.push({
            "icon": "plus",
            "text": "New Instance",
            "action": function () {
                Quickshell.execDetached(["gtk-launch", menuData]); 
                root.requestClose();
            }
        });
        
        next.push({
            "icon": "unpin",
            "text": I18n.tr("dock.menu.unpin"),
            "action": function () {
                handlePin(menuData);
            }
        });
    } 
    else if (menuType === "workspace") {
        const appId = menuData.appId;
        const isPinned = root.isAppPinned(appId);
        
        next.push({
            "icon": "eye",
            "text": I18n.tr("dock.menu.focus"),
            "action": function () {
                handleFocus();
            }
        });

        next.push({
            "icon": !isPinned ? "pin" : "unpin",
            "text": !isPinned ? I18n.tr("dock.menu.pin") : I18n.tr("dock.menu.unpin"),
            "action": function () {
                handlePin(appId);
            }
        });

        next.push({
            "icon": "close",
            "text": I18n.tr("dock.menu.close"),
            "action": function () {
                handleClose();
            }
        });
    }

    const targetAppId = (menuType === "pinned") ? menuData : menuData?.appId;
    
    if (targetAppId && typeof DesktopEntries !== 'undefined' && DesktopEntries.byId) {
      const entry = (DesktopEntries.heuristicLookup) ? DesktopEntries.heuristicLookup(targetAppId) : DesktopEntries.byId(targetAppId);
      if (entry != null) {
        entry.actions.forEach(function (action) {
          next.push({
            "icon": "",
            "text": action.name,
            "action": function () {
              action.execute();
              root.requestClose();
            }
          });
        });
      }
    }

    root.items = next;
  }

  function isAppPinned(appId) {
    if (!appId) return false;
    const pinnedApps = Settings.data.dock.pinnedApps || [];
    return pinnedApps.includes(appId);
  }

  function toggleAppPin(appId) {
    if (!appId) return;
    let pinnedApps = (Settings.data.dock.pinnedApps || []).slice();
    const isPinned = pinnedApps.includes(appId);

    if (isPinned) {
      pinnedApps = pinnedApps.filter(id => id !== appId);
    } else {
      pinnedApps.push(appId);
    }
    Settings.data.dock.pinnedApps = pinnedApps;
  }

  anchor.item: anchorItem
  anchor.rect.x: anchorItem ? (anchorItem.width - implicitWidth) / 2 : 0
  anchor.rect.y: anchorItem ? -implicitHeight - (Style.marginM) : 0

  function show(item, data, type) {
    if (!item) return;

    anchorItem = item;
    menuData = data;
    menuType = type || "workspace";
    initItems();
    visible = true;
    canAutoClose = false;
    gracePeriodTimer.restart();
  }

  function hide() {
    visible = false;
    root.items.length = 0;
  }

  function getHoveredItem(mouseY) {
    const itemHeight = 32;
    const startY = Style.marginM;
    const relativeY = mouseY - startY;
    if (relativeY < 0) return -1;
    const itemIndex = Math.floor(relativeY / itemHeight);
    return itemIndex >= 0 && itemIndex < root.items.length ? itemIndex : -1;
  }

  function handleFocus() {
    if (root.menuData) {
      CompositorService.focusWindow(root.menuData);
    }
    root.requestClose();
  }

  function handlePin(targetId) {
    if (targetId) {
      root.toggleAppPin(targetId);
    }
    root.requestClose();
  }

  function handleClose() {
    if (root.menuData) {
      CompositorService.closeWindow(root.menuData);
      
      if (root.onAppClosed && typeof root.onAppClosed === "function") {
        Qt.callLater(root.onAppClosed);
      }
    }
    root.hide();
    root.requestClose();
  }

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
