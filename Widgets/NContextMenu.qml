import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

Popup {
  id: root

  property alias model: listView.model
  property real itemHeight: 36
  property real itemPadding: Style.marginM
  property int verticalPolicy: ScrollBar.AsNeeded
  property int horizontalPolicy: ScrollBar.AsNeeded

  signal triggered(string action)

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
    implicitHeight: contentHeight
    spacing: Style.marginXXS
    interactive: contentHeight > root.height
    verticalPolicy: root.verticalPolicy
    horizontalPolicy: root.horizontalPolicy

    delegate: ItemDelegate {
      id: menuItem
      width: listView.width
      height: modelData.visible !== false ? root.itemHeight : 0
      visible: modelData.visible !== false
      opacity: modelData.enabled !== false ? 1.0 : 0.5
      enabled: modelData.enabled !== false

      // Store reference to the popup
      property var popup: root

      background: Rectangle {
        color: menuItem.hovered && menuItem.enabled ? Color.mHover : Color.transparent
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
