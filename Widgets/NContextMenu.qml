import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

/*
* NContextMenu - Popup-based context menu for use inside panels and dialogs
*
* Use this component when you need a context menu inside:
* - Settings panels
* - Dialogs
* - Repeater delegates
* - Any nested component context
*
* For bar widgets and top-level window contexts, use NPopupContextMenu instead,
* which provides better screen boundary handling and compositor integration.
*
* Usage:
*   NContextMenu {
*     id: contextMenu
*     parent: Overlay.overlay
*     model: [
*       { "label": "Action 1", "action": "action1", "icon": "icon-name" },
*       { "label": "Action 2", "action": "action2" }
*     ]
*     onTriggered: action => { Logger.i("MyModule", "Selected:", action) }
*   }
*
*   MouseArea {
*     onClicked: contextMenu.openAtItem(parent, mouse.x, mouse.y)
*   }
*/
NPopup {
  id: root

  property var model: []
  property real itemHeight: 36
  property real itemPadding: Style.marginM
  property int verticalPolicy: ScrollBar.AsNeeded
  property int horizontalPolicy: ScrollBar.AsNeeded

  signal triggered(string action)

  // Filter out hidden items to avoid spacing artifacts from zero-height items
  readonly property var filteredModel: {
    if (!model || model.length === 0)
      return [];
    var filtered = [];
    for (var i = 0; i < model.length; i++) {
      if (model[i].visible !== false) {
        filtered.push(model[i]);
      }
    }
    return filtered;
  }

  width: 180
  padding: Style.marginS

  background: Rectangle {
    color: Color.mSurfaceVariant
    border.color: Color.mOutline
    border.width: Style.borderS
    radius: Style.iRadiusM
  }

  contentItem: NListView {
    id: listView
    implicitHeight: Math.max(contentHeight, root.itemHeight)
    spacing: Style.marginXXS
    interactive: contentHeight > root.height
    verticalPolicy: root.verticalPolicy
    horizontalPolicy: root.horizontalPolicy
    reserveScrollbarSpace: false
    model: root.filteredModel

    delegate: ItemDelegate {
      id: menuItem
      width: listView.availableWidth
      height: root.itemHeight
      opacity: modelData.enabled !== false ? 1.0 : 0.5
      enabled: modelData.enabled !== false

      // Store reference to the popup
      property var popup: root

      background: Rectangle {
        color: menuItem.hovered && menuItem.enabled ? Color.mHover : "transparent"
        radius: Style.iRadiusS

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }
      }

      contentItem: RowLayout {
        spacing: Style.marginS

        // Optional icon
        NIcon {
          visible: modelData.icon !== undefined
          icon: modelData.icon || ""
          pointSize: Style.fontSizeM
          color: menuItem.hovered && menuItem.enabled ? Color.mOnHover : Color.mOnSurface
          Layout.leftMargin: root.itemPadding

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }

        NText {
          text: modelData.label || modelData.text || ""
          pointSize: Style.fontSizeM
          color: menuItem.hovered && menuItem.enabled ? Color.mOnHover : Color.mOnSurface
          verticalAlignment: Text.AlignVCenter
          Layout.fillWidth: true
          Layout.leftMargin: modelData.icon === undefined ? root.itemPadding : 0

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }
      }

      onClicked: {
        if (enabled) {
          popup.triggered(modelData.action || modelData.key || index.toString());
          popup.close();
        }
      }
    }
  }

  // Helper function to open at mouse position
  function openAt(x, y) {
    root.x = x;
    root.y = y;
    root.open();
  }

  // Helper function to open at item
  function openAtItem(item, mouseX, mouseY) {
    var pos = item.mapToItem(root.parent, mouseX || 0, mouseY || 0);
    openAt(pos.x, pos.y);
  }
}
