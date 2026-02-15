import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var entriesModel: []
  property var updateEntry
  property var reorderEntries
  property var openEntrySettingsDialog

  // List of items
  Item {
    Layout.fillWidth: true
    implicitHeight: listView.contentHeight

    NListView {
      id: listView
      anchors.fill: parent
      spacing: Style.marginS
      interactive: false
      reserveScrollbarSpace: false
      model: root.entriesModel

      delegate: Item {
        id: delegateItem
        width: listView.availableWidth
        height: contentRow.height

        required property int index
        required property var modelData

        property bool dragging: false
        property int dragStartY: 0
        property int dragStartIndex: -1
        property int dragTargetIndex: -1

        Rectangle {
          anchors.fill: parent
          radius: Style.radiusM
          color: delegateItem.dragging ? Color.mSurfaceVariant : "transparent"
          border.color: delegateItem.dragging ? Color.mOutline : "transparent"
          border.width: Style.borderS

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }

        RowLayout {
          id: contentRow
          width: parent.width
          spacing: Style.marginS

          // Drag handle
          Rectangle {
            Layout.preferredWidth: Style.baseWidgetSize * 0.7
            Layout.preferredHeight: Style.baseWidgetSize * 0.7
            Layout.alignment: Qt.AlignVCenter
            radius: Style.radiusXS
            color: dragHandleMouseArea.containsMouse ? Color.mSurfaceVariant : "transparent"

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }

            ColumnLayout {
              anchors.centerIn: parent
              spacing: 2

              Repeater {
                model: 3
                Rectangle {
                  Layout.preferredWidth: Style.baseWidgetSize * 0.28
                  Layout.preferredHeight: 2
                  radius: 1
                  color: Color.mOutline
                }
              }
            }

            MouseArea {
              id: dragHandleMouseArea
              anchors.fill: parent
              cursorShape: Qt.SizeVerCursor
              hoverEnabled: true
              preventStealing: false
              z: 1000

              onPressed: mouse => {
                           delegateItem.dragStartIndex = delegateItem.index;
                           delegateItem.dragTargetIndex = delegateItem.index;
                           delegateItem.dragStartY = delegateItem.y;
                           delegateItem.dragging = true;
                           delegateItem.z = 999;
                           preventStealing = true;
                         }

              onPositionChanged: mouse => {
                                   if (delegateItem.dragging) {
                                     var dy = mouse.y - height / 2;
                                     var newY = delegateItem.y + dy;
                                     newY = Math.max(0, Math.min(newY, listView.contentHeight - delegateItem.height));
                                     delegateItem.y = newY;
                                     var targetIndex = Math.floor((newY + delegateItem.height / 2) / (delegateItem.height + Style.marginS));
                                     targetIndex = Math.max(0, Math.min(targetIndex, listView.count - 1));
                                     delegateItem.dragTargetIndex = targetIndex;
                                   }
                                 }

              onReleased: {
                preventStealing = false;
                if (delegateItem.dragStartIndex !== -1 && delegateItem.dragTargetIndex !== -1 && delegateItem.dragStartIndex !== delegateItem.dragTargetIndex) {
                  root.reorderEntries(delegateItem.dragStartIndex, delegateItem.dragTargetIndex);
                }
                delegateItem.dragging = false;
                delegateItem.dragStartIndex = -1;
                delegateItem.dragTargetIndex = -1;
                delegateItem.z = 0;
              }

              onCanceled: {
                preventStealing = false;
                delegateItem.dragging = false;
                delegateItem.dragStartIndex = -1;
                delegateItem.dragTargetIndex = -1;
                delegateItem.z = 0;
              }
            }
          }

          // Enable checkbox
          Rectangle {
            Layout.preferredWidth: Style.baseWidgetSize * 0.7
            Layout.preferredHeight: Style.baseWidgetSize * 0.7
            Layout.alignment: Qt.AlignVCenter
            radius: Style.radiusXS
            color: modelData.enabled ? Color.mPrimary : Color.mSurface
            border.color: Color.mOutline
            border.width: Style.borderS

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }

            NIcon {
              visible: modelData.enabled
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: -1
              icon: "check"
              color: Color.mOnPrimary
              pointSize: Math.max(Style.fontSizeXS, Style.baseWidgetSize * 0.35)
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.updateEntry(index, {
                                   "enabled": !modelData.enabled
                                 });
              }
            }
          }

          // Label
          NText {
            Layout.fillWidth: true
            text: modelData.text
            color: Color.mOnSurface
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          // Countdown toggle (only shown when global countdown is enabled)
          NIconButtonHot {
            visible: Settings.data.sessionMenu.enableCountdown
            icon: "clock"
            hot: modelData.countdownEnabled !== undefined ? modelData.countdownEnabled : true
            baseSize: Style.baseWidgetSize * 0.8
            Layout.alignment: Qt.AlignVCenter
            tooltipText: I18n.tr("common.countdown")
            onClicked: root.updateEntry(delegateItem.index, {
                                          "countdownEnabled": !(modelData.countdownEnabled !== undefined ? modelData.countdownEnabled : true)
                                        })
          }

          // Settings button (cogwheel)
          NIconButton {
            icon: "settings"
            tooltipText: I18n.tr("panels.session-menu.entry-settings-tooltip")
            baseSize: Style.baseWidgetSize * 0.8
            Layout.alignment: Qt.AlignVCenter
            onClicked: root.openEntrySettingsDialog(delegateItem.index)
          }
        }

        // Position binding for non-dragging state
        y: {
          if (delegateItem.dragging) {
            return delegateItem.y;
          }

          var draggedIndex = -1;
          var targetIndex = -1;
          for (var i = 0; i < listView.count; i++) {
            var item = listView.itemAtIndex(i);
            if (item && item.dragging) {
              draggedIndex = item.dragStartIndex;
              targetIndex = item.dragTargetIndex;
              break;
            }
          }

          if (draggedIndex !== -1 && targetIndex !== -1 && draggedIndex !== targetIndex) {
            var currentIndex = delegateItem.index;
            if (draggedIndex < targetIndex) {
              if (currentIndex > draggedIndex && currentIndex <= targetIndex) {
                return (currentIndex - 1) * (delegateItem.height + Style.marginS);
              }
            } else {
              if (currentIndex >= targetIndex && currentIndex < draggedIndex) {
                return (currentIndex + 1) * (delegateItem.height + Style.marginS);
              }
            }
          }

          return delegateItem.index * (delegateItem.height + Style.marginS);
        }

        Behavior on y {
          enabled: !delegateItem.dragging
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutQuad
          }
        }
      }
    }
  }
}
