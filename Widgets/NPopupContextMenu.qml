import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons

// Simple context menu PopupWindow (similar to TrayMenu)
// Designed to be rendered inside a PopupMenuWindow for click-outside-to-close
// Automatically positions itself to respect screen boundaries
PopupWindow {
  id: root

  property alias model: repeater.model
  property real itemHeight: 28 // Match TrayMenu
  property real itemPadding: Style.marginM
  property int verticalPolicy: ScrollBar.AsNeeded
  property int horizontalPolicy: ScrollBar.AsNeeded

  property var anchorItem: null
  property ShellScreen screen: null
  property real calculatedWidth: 180

  readonly property string barPosition: Settings.data.bar.position

  signal triggered(string action, var item)

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

  anchor.rect.x: {
    if (anchorItem && screen) {
      const anchorGlobalPos = anchorItem.mapToItem(null, 0, 0);

      // For right bar: position menu to the left of anchor
      if (root.barPosition === "right") {
        let baseX = -implicitWidth - Style.marginM;
        return baseX;
      }

      // For left bar: position menu to the right of anchor
      if (root.barPosition === "left") {
        let baseX = anchorItem.width + Style.marginM;
        return baseX;
      }

      // For top/bottom bar: center horizontally on anchor
      const anchorCenterX = anchorItem.width / 2;
      let baseX = anchorCenterX - (implicitWidth / 2);

      // Calculate menu position on screen
      const menuScreenX = anchorGlobalPos.x + baseX;
      const menuRight = menuScreenX + implicitWidth;

      // Adjust if menu would clip on the right
      if (menuRight > screen.width - Style.marginM) {
        const overflow = menuRight - (screen.width - Style.marginM);
        return baseX - overflow;
      }
      // Adjust if menu would clip on the left
      if (menuScreenX < Style.marginM) {
        return baseX + (Style.marginM - menuScreenX);
      }
      return baseX;
    }
    return 0;
  }
  anchor.rect.y: {
    if (anchorItem && screen) {
      const anchorCenterY = anchorItem.height / 2;

      // Calculate base Y position based on bar orientation
      let baseY;
      if (root.barPosition === "bottom") {
        // For bottom bar: position menu above the bar
        baseY = -(implicitHeight + Style.marginM);
      } else if (root.barPosition === "top") {
        // For top bar: position menu below bar
        baseY = Style.barHeight + Style.marginM;
      } else {
        // For left/right bar: vertically center on anchor
        baseY = anchorCenterY - (implicitHeight / 2);
      }

      // Calculate menu position on screen
      const anchorGlobalPos = anchorItem.mapToItem(null, 0, 0);
      const menuScreenY = anchorGlobalPos.y + baseY;

      const menuBottom = menuScreenY + implicitHeight;

      // Adjust if menu would clip at bottom
      if (menuBottom > screen.height - Style.marginM) {
        const overflow = menuBottom - (screen.height - Style.marginM);
        return baseY - overflow;
      }

      return baseY;
    }

    // Fallback if no screen
    if (root.barPosition === "bottom") {
      return -implicitHeight - Style.marginM;
    }
    return Style.barHeight;
  }

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
                  root.triggered(menuItem.modelData.action || menuItem.modelData.key || menuItem.index.toString(), menuItem.modelData);
                  // Don't call root.close() here - let the parent PopupMenuWindow handle closing
                }
              }
            }
          }
        }
      }
    }
  }

  // Helper function to open context menu anchored to an item
  // Position is calculated automatically based on bar position and screen boundaries
  function openAtItem(item, itemScreen) {
    if (!item) {
      Logger.w("NPopupContextMenu", "anchorItem is undefined, won't show menu.");
      return;
    }

    calculateWidth();

    anchorItem = item;
    screen = itemScreen || null;
    visible = true;
  }

  function close() {
    visible = false;
  }

  function closeMenu() {
    close();
  }
}
