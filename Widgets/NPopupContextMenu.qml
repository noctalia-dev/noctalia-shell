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
  property real minWidth: 120
  property real calculatedWidth: 180

  // Explicit offset for centering on target item (computed from targetItem in openAtItem)
  property real targetOffsetX: 0
  property real targetOffsetY: 0
  property real targetWidth: 0
  property real targetHeight: 0

  readonly property string barPosition: Settings.getBarPositionForScreen(screen?.name)
  readonly property real barHeight: Style.getBarHeightForScreen(screen?.name)

  signal triggered(string action, var item)

  implicitWidth: calculatedWidth
  implicitHeight: Math.min(600, flickable.contentHeight + (Style.marginS * 2))
  visible: false
  color: "transparent"

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

          itemWidth += Style.margin2M;

          if (itemWidth > maxWidth) {
            maxWidth = itemWidth;
          }
        }
      }
    }
    calculatedWidth = Math.max(maxWidth + (Style.marginS * 2), minWidth);
  }

  anchor.item: anchorItem

  anchor.rect.x: {
    if (anchorItem && screen) {
      const anchorGlobalPos = anchorItem.mapToItem(null, 0, 0);

      // Use stored targetOffsetX and targetWidth for positioning
      const effectiveWidth = targetWidth > 0 ? targetWidth : anchorItem.width;
      const targetGlobalX = anchorGlobalPos.x + targetOffsetX;

      // For right bar: position menu to the left of target
      if (root.barPosition === "right") {
        let baseX = targetOffsetX - implicitWidth - Style.marginM;
        return baseX;
      }

      // For left bar: position menu to the right of target
      if (root.barPosition === "left") {
        let baseX = targetOffsetX + effectiveWidth + Style.marginM;
        return baseX;
      }

      // For top/bottom bar: center horizontally on target
      const targetCenterScreenX = targetGlobalX + (effectiveWidth / 2);
      const menuScreenX = targetCenterScreenX - (implicitWidth / 2);
      let baseX = menuScreenX - anchorGlobalPos.x;

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
      // Check if using absolute positioning (small anchor point item)
      const isAbsolutePosition = anchorItem.width <= 1 && anchorItem.height <= 1;

      if (isAbsolutePosition) {
        // For absolute positioning, show menu directly at anchor Y
        // Only adjust if menu would clip at bottom
        const anchorGlobalPos = anchorItem.mapToItem(null, 0, 0);
        const menuBottom = anchorGlobalPos.y + implicitHeight;

        if (menuBottom > screen.height - Style.marginM) {
          // Position above the click point instead
          return -implicitHeight;
        }
        return 0;
      }

      const anchorGlobalPos = anchorItem.mapToItem(null, 0, 0);

      // Use target offset/height for vertical bars, anchor dimensions otherwise
      const effectiveHeight = targetHeight > 0 ? targetHeight : anchorItem.height;
      const effectiveOffsetY = targetOffsetY;

      // Calculate base Y position based on bar orientation
      let baseY;
      if (root.barPosition === "bottom") {
        // For bottom bar: position menu above the bar
        baseY = -(implicitHeight + Style.marginS);
      } else if (root.barPosition === "top") {
        // For top bar: position menu below bar at consistent height
        // Compensate for anchor's Y position to ensure menu top is always at (barHeight + margin)
        baseY = barHeight + Style.marginS - anchorGlobalPos.y;
      } else {
        // For left/right bar: vertically center on target item
        const targetCenterY = effectiveOffsetY + (effectiveHeight / 2);
        baseY = targetCenterY - (implicitHeight / 2);
      }

      const menuScreenY = anchorGlobalPos.y + baseY;
      const menuBottom = menuScreenY + implicitHeight;

      // Define clipping boundaries based on bar position
      const topLimit = Style.marginM;
      const bottomLimit = root.barPosition === "bottom" ? screen.height - barHeight - Style.marginS : screen.height - Style.marginM;

      // Adjust if menu would clip at top (skip for bottom bar - don't push menu down over bar)
      if (menuScreenY < topLimit && root.barPosition !== "bottom") {
        const adjustment = topLimit - menuScreenY;
        return baseY + adjustment;
      }

      // Adjust if menu would clip at bottom (or overlap bar for bottom bar)
      if (menuBottom > bottomLimit) {
        const overflow = menuBottom - bottomLimit;
        return baseY - overflow;
      }

      return baseY;
    }

    // Fallback if no screen
    if (root.barPosition === "bottom") {
      return -implicitHeight - Style.marginS;
    }
    return barHeight;
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
    radius: Style.radiusM
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
          color: "transparent"

          Rectangle {
            id: innerRect
            anchors.fill: parent
            color: mouseArea.containsMouse ? Color.mHover : "transparent"
            radius: Style.radiusS
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
  // Optional centerOnItem: if provided, menu will be horizontally centered on this item instead of anchorItem
  function openAtItem(item, itemScreen, centerOnItem) {
    if (!item) {
      Logger.w("NPopupContextMenu", "anchorItem is undefined, won't show menu.");
      return;
    }

    // Set anchor and screen first
    anchorItem = item;
    screen = itemScreen || null;

    // Compute target offset and dimensions from centerOnItem
    if (centerOnItem && centerOnItem !== item) {
      const relPos = centerOnItem.mapToItem(item, 0, 0);
      targetOffsetX = relPos.x;
      targetOffsetY = relPos.y;
      targetWidth = centerOnItem.width;
      targetHeight = centerOnItem.height;
    } else {
      targetOffsetX = 0;
      targetOffsetY = 0;
      targetWidth = 0;
      targetHeight = 0;
    }

    // Calculate menu width after anchor is set
    calculateWidth();

    visible = true;

    // Force anchor recalculation after showing
    Qt.callLater(() => {
                   anchor.updateAnchor();
                 });
  }

  function close() {
    visible = false;
  }

  function closeMenu() {
    close();
  }
}
