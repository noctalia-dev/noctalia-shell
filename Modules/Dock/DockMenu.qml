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

  // --- New Properties for Move Logic ---
  property int pinnedIndex: -1
  property int totalPinnedCount: 0
  property string menuView: "main" 
  signal requestMove(int offset)
  // -------------------------------------

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
    
    // ============================================
    // VIEW: MAIN (Root Menu)
    // ============================================
    if (root.menuView === "main") {
        if (menuType === "pinned") {
            next.push({
                "icon": "plus",
                "text": "New Instance",
                "action": function () {
                    Quickshell.execDetached(["gtk-launch", menuData]); 
                    root.requestClose();
                }
            });
            
            // --- Move Button ---
            // Only show if there are at least 2 apps
            if (root.totalPinnedCount > 1) {
                next.push({
                    "icon": "arrow-right", 
                    "text": "Move App", // Renamed here
                    "action": function() {
                        root.menuView = "move_options";
                        root.initItems();
                    }
                });
            }

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

        // Desktop actions (Main view only)
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
    }
    // ============================================
    // VIEW: MOVE OPTIONS (Left / Right)
    // ============================================
    else if (root.menuView === "move_options") {
        next.push({
            "icon": "arrow-left",
            "text": "Back",
            "action": function() {
                root.menuView = "main";
                root.initItems();
            }
        });

        // Move Left (Only if not first)
        if (root.pinnedIndex > 0) {
            next.push({
                "icon": "arrow-left",
                "text": "Move Left",
                "action": function() {
                    root.menuView = "move_left";
                    root.initItems();
                }
            });
        }

        // Move Right (Only if not last)
        if (root.pinnedIndex < root.totalPinnedCount - 1) {
            next.push({
                "icon": "arrow-right",
                "text": "Move Right",
                "action": function() {
                    root.menuView = "move_right";
                    root.initItems();
                }
            });
        }
    }
    // ============================================
    // VIEW: MOVE LEFT STEPS
    // ============================================
    else if (root.menuView === "move_left") {
        next.push({
            "icon": "arrow-left",
            "text": "Back",
            "action": function() {
                root.menuView = "move_options";
                root.initItems();
            }
        });

        // 1 Step
        if (root.pinnedIndex >= 1) {
            next.push({ "icon": "", "text": "1 Position", "action": function() { root.requestMove(-1); } });
        }
        // 2 Steps
        if (root.pinnedIndex >= 2) {
            next.push({ "icon": "", "text": "2 Positions", "action": function() { root.requestMove(-2); } });
        }
        // 3 Steps
        if (root.pinnedIndex >= 3) {
            next.push({ "icon": "", "text": "3 Positions", "action": function() { root.requestMove(-3); } });
        }
    }
    // ============================================
    // VIEW: MOVE RIGHT STEPS
    // ============================================
    else if (root.menuView === "move_right") {
        next.push({
            "icon": "arrow-left",
            "text": "Back",
            "action": function() {
                root.menuView = "move_options";
                root.initItems();
            }
        });

        // 1 Step
        if (root.pinnedIndex + 1 < root.totalPinnedCount) {
            next.push({ "icon": "", "text": "1 Position", "action": function() { root.requestMove(1); } });
        }
        // 2 Steps
        if (root.pinnedIndex + 2 < root.totalPinnedCount) {
            next.push({ "icon": "", "text": "2 Positions", "action": function() { root.requestMove(2); } });
        }
        // 3 Steps
        if (root.pinnedIndex + 3 < root.totalPinnedCount) {
            next.push({ "icon": "", "text": "3 Positions", "action": function() { root.requestMove(3); } });
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

  // Modified show function to accept index info
  function showPinned(item, data, index, total) {
    if (!item) return;
    anchorItem = item;
    menuData = data;
    menuType = "pinned";
    pinnedIndex = index;
    totalPinnedCount = total;
    menuView = "main"; // Reset to main view
    
    initItems();
    visible = true;
    canAutoClose = false;
    gracePeriodTimer.restart();
  }

  function show(item, data, type) {
    if (!item) return;
    anchorItem = item;
    menuData = data;
    menuType = type || "workspace";
    menuView = "main"; // Reset to main view
    
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
