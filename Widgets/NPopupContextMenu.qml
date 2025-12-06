import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons

// Simple context menu PopupWindow (similar to TrayMenu)
// Designed to be rendered inside a PopupMenuWindow for click-outside-to-close
PopupWindow {
  id: root

  property alias model: repeater.model
  property real itemHeight: 28  // Match TrayMenu
  property real itemPadding: Style.marginM
  property int verticalPolicy: ScrollBar.AsNeeded
  property int horizontalPolicy: ScrollBar.AsNeeded

  property var anchorItem: null
  property real anchorX: 0
  property real anchorY: 0
  property real calculatedWidth: 180

  signal triggered(string action)

  implicitWidth: calculatedWidth
  implicitHeight: Math.min(600, flickable.contentHeight + (Style.marginS * 2))
  visible: false
  color: Color.transparent

  NText {
    id: textMeasure
    visible: false
    pointSize: Style.fontSizeS
    wrapMode: Text.NoWrap
    elide: Text.ElideNone
    width: undefined
  }

  NIcon {
    id: iconMeasure
    visible: false
    icon: "bell"
    pointSize: Style.fontSizeS
    applyUiScale: false
  }

  onModelChanged: {
    Qt.callLater(calculateWidth);
  }

  function calculateWidth() {
    let maxWidth = 0;
    if (model && model.length) {
      for (let i = 0; i < model.length; i++) {
        const item = model[i];
        if (item && item.visible !== false) {
          const label = item.label || item.text || "";
          textMeasure.text = label;
          textMeasure.forceLayout();

          let itemWidth = textMeasure.contentWidth + 8;

          if (item.icon !== undefined) {
            itemWidth += iconMeasure.width + Style.marginS;
          }

          itemWidth += Style.marginM * 2;

          if (itemWidth > maxWidth) {
            maxWidth = itemWidth;
          }
        }
      }
    }
    calculatedWidth = Math.max(maxWidth + (Style.marginS * 2), 120);
  }

  anchor.item: anchorItem
  anchor.rect.x: anchorX
  anchor.rect.y: anchorY

  Component.onCompleted: {
    Qt.callLater(calculateWidth);
  }

  Item {
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: root.close()
  }

  Rectangle {
    id: menuBackground
    anchors.fill: parent
    color: Color.mSurface
    border.color: Color.mOutline
    border.width: Style.borderS
    radius: Style.iRadiusM
    opacity: root.visible ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutQuad
      }
    }
  }

  Flickable {
    id: flickable
    anchors.fill: parent
    anchors.margins: Style.marginS
    contentHeight: columnLayout.implicitHeight
    interactive: true
    opacity: root.visible ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutQuad
      }
    }

    ColumnLayout {
      id: columnLayout
      width: flickable.width
      spacing: 0

      Repeater {
        id: repeater

        delegate: Rectangle {
          id: menuItem
          required property var modelData
          required property int index

          Layout.preferredWidth: parent.width
          Layout.preferredHeight: modelData.visible !== false ? root.itemHeight : 0
          visible: modelData.visible !== false
          color: Color.transparent

          Rectangle {
            id: innerRect
            anchors.fill: parent
            color: mouseArea.containsMouse ? Color.mHover : Color.transparent
            radius: Style.iRadiusS
            opacity: modelData.enabled !== false ? 1.0 : 0.5

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.marginM
              anchors.rightMargin: Style.marginM
              spacing: Style.marginS

              NIcon {
                visible: modelData.icon !== undefined
                icon: modelData.icon || ""
                pointSize: Style.fontSizeS
                applyUiScale: false
                color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
                verticalAlignment: Text.AlignVCenter

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }
              }

              NText {
                text: modelData.label || modelData.text || ""
                pointSize: Style.fontSizeS
                color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
                verticalAlignment: Text.AlignVCenter
                Layout.fillWidth: true

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              enabled: (modelData.enabled !== false) && root.visible
              cursorShape: Qt.PointingHandCursor

              onClicked: {
                if (menuItem.modelData.enabled !== false) {
                  root.triggered(menuItem.modelData.action || menuItem.modelData.key || menuItem.index.toString());
                  // Don't call root.close() here - let the parent PopupMenuWindow handle closing
                }
              }
            }
          }
        }
      }
    }
  }

  // Helper function to open at specific position relative to anchor item
  function openAt(x, y, item) {
    if (!item) {
      Logger.w("NPopupContextMenu", "anchorItem is undefined, won't show menu.");
      return;
    }

    calculateWidth();

    anchorItem = item;
    anchorX = x;
    anchorY = y;
    visible = true;

    Qt.callLater(() => {
                   if (root.anchor) {
                     root.anchor.updateAnchor();
                   }
                 });
  }

  function openAtItem(item, mouseX, mouseY) {
    openAt(mouseX || 0, mouseY || 0, item);
  }

  function close() {
    visible = false;
  }

  function closeMenu() {
    close();
  }
}
