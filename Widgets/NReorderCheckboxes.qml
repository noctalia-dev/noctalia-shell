import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

Item {
  id: root

  // Public API
  property var model: []
  property var disabledIds: []
  property color activeColor: Color.mPrimary
  property color activeOnColor: Color.mOnPrimary
  property color dragHandleColor: Color.mOutline
  property int baseSize: Style.baseWidgetSize * 0.7
  property int spacing: Style.marginM

  signal itemToggled(int index, bool enabled)
  signal itemsReordered(int fromIndex, int toIndex)
  signal dragPotentialStarted
  signal dragPotentialEnded

  readonly property real itemHeight: root.baseSize
  readonly property real contentHeight: root.model.length > 0 ? root.model.length * itemHeight + (root.model.length - 1) * root.spacing : 0
  implicitHeight: contentHeight

  function toggleItem(index) {
    if (index < 0 || index >= root.model.length)
      return;
    var item = root.model[index];
    if (item.required)
      return;

    // Create a new array to trigger binding update
    var newModel = root.model.slice();
    newModel[index] = Object.assign({}, item, {
                                      "enabled": !item.enabled
                                    });
    root.model = newModel;

    root.itemToggled(index, newModel[index].enabled);
  }

  function moveItem(fromIndex, toIndex) {
    if (fromIndex === toIndex)
      return;
    if (fromIndex < 0 || fromIndex >= root.model.length)
      return;
    if (toIndex < 0 || toIndex >= root.model.length)
      return;

    // Create a new array with item moved
    var newModel = root.model.slice();
    var item = newModel.splice(fromIndex, 1)[0];
    newModel.splice(toIndex, 0, item);
    root.model = newModel;

    root.itemsReordered(fromIndex, toIndex);
  }

  Item {
    id: itemsContainer
    anchors.fill: parent
    clip: true

    Repeater {
      id: repeater
      model: root.model

      delegate: Item {
        id: delegateItem

        width: itemsContainer.width
        height: checkboxRow.height

        required property int index
        required property var modelData

        property string text: modelData.text || ""
        property bool enabled: modelData.enabled || false
        property bool required: modelData.required || false
        readonly property bool isDisabled: (root.disabledIds || []).indexOf(modelData.id) !== -1
        readonly property bool canDrag: !delegateItem.isDisabled
        property bool dragging: false
        property int dragStartY: 0
        property int dragStartIndex: -1
        property int dragTargetIndex: -1
        property int itemSpacing: root.spacing

        RowLayout {
          id: checkboxRow

          width: parent.width
          spacing: Style.marginS
          opacity: isDisabled ? 0.5 : 1.0

          // Drag handle
          Rectangle {
            id: dragHandle

            Layout.preferredWidth: root.baseSize
            Layout.preferredHeight: root.baseSize
            radius: Style.iRadiusXS
            color: dragHandleMouseArea.containsMouse ? Color.mSurfaceVariant : "transparent"

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.marginS

              Repeater {
                model: 3
                Rectangle {
                  Layout.preferredWidth: root.baseSize * 0.4
                  Layout.preferredHeight: 2
                  radius: 1
                  color: root.dragHandleColor
                }
              }
            }

            MouseArea {
              id: dragHandleMouseArea

              anchors.fill: parent
              cursorShape: delegateItem.canDrag ? Qt.SizeVerCursor : Qt.ArrowCursor
              hoverEnabled: true
              preventStealing: false
              enabled: delegateItem.canDrag
              z: 1000

              onPressed: mouse => {
                           if (!delegateItem.canDrag) {
                             return;
                           }
                           delegateItem.dragStartIndex = delegateItem.index;
                           delegateItem.dragTargetIndex = delegateItem.index;
                           delegateItem.dragStartY = delegateItem.y;
                           delegateItem.dragging = true;
                           delegateItem.z = 999;

                           // Signal that interaction started (prevents panel close)
                           preventStealing = true;
                           root.dragPotentialStarted();
                         }

              onPositionChanged: mouse => {
                                   if (delegateItem.dragging) {
                                     var dy = mouse.y - dragHandle.height / 2;
                                     var newY = delegateItem.y + dy;

                                     // Constrain within bounds
                                     newY = Math.max(0, Math.min(newY, root.contentHeight - delegateItem.height));
                                     delegateItem.y = newY;

                                     // Calculate target index (but don't apply yet)
                                     var targetIndex = Math.floor((newY + delegateItem.height / 2) / (delegateItem.height + delegateItem.itemSpacing));
                                     targetIndex = Math.max(0, Math.min(targetIndex, repeater.count - 1));

                                     delegateItem.dragTargetIndex = targetIndex;
                                   }
                                 }

              onReleased: {
                // Always signal end of interaction
                preventStealing = false;
                root.dragPotentialEnded();

                // Apply the model change now that drag is complete
                if (delegateItem.dragStartIndex !== -1 && delegateItem.dragTargetIndex !== -1 && delegateItem.dragStartIndex !== delegateItem.dragTargetIndex) {
                  root.moveItem(delegateItem.dragStartIndex, delegateItem.dragTargetIndex);
                }

                delegateItem.dragging = false;
                delegateItem.dragStartIndex = -1;
                delegateItem.dragTargetIndex = -1;
                delegateItem.z = 0;
              }

              onCanceled: {
                // Handle cancel (e.g., ESC key pressed during drag)
                preventStealing = false;
                root.dragPotentialEnded();

                delegateItem.dragging = false;
                delegateItem.dragStartIndex = -1;
                delegateItem.dragTargetIndex = -1;
                delegateItem.z = 0;
              }
            }
          }

          // Checkbox
          Rectangle {
            id: box

            Layout.preferredWidth: root.baseSize
            Layout.preferredHeight: root.baseSize
            radius: Style.iRadiusXS
            color: delegateItem.enabled ? root.activeColor : Color.mSurface
            border.color: delegateItem.required ? root.activeColor : Color.mOutline
            border.width: Style.borderS
            opacity: delegateItem.required ? 0.7 : 1.0

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }

            Behavior on border.color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }

            NIcon {
              visible: delegateItem.enabled
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: -1
              icon: "check"
              color: root.activeOnColor
              pointSize: Math.max(Style.fontSizeXS, root.baseSize * 0.5)
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: (!delegateItem.required && !delegateItem.isDisabled) ? Qt.PointingHandCursor : Qt.ArrowCursor
              enabled: !delegateItem.required && !delegateItem.isDisabled

              onClicked: {
                if (!delegateItem.required && !delegateItem.isDisabled) {
                  root.toggleItem(delegateItem.index);
                }
              }
            }
          }

          // Label
          NText {
            Layout.fillWidth: true
            text: delegateItem.text
            color: Color.mOnSurface
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          // Required indicator
          NText {
            visible: delegateItem.required
            text: I18n.tr("common.required")
            color: Color.mOnSurfaceVariant
            verticalAlignment: Text.AlignVCenter
          }
        }

        // Position binding for non-dragging state
        y: {
          if (delegateItem.dragging) {
            return delegateItem.y;
          }

          // Check if any item is being dragged
          var draggedIndex = -1;
          var targetIndex = -1;
          for (var i = 0; i < repeater.count; i++) {
            var item = repeater.itemAt(i);
            if (item && item.dragging) {
              draggedIndex = item.dragStartIndex;
              targetIndex = item.dragTargetIndex;
              break;
            }
          }

          // If an item is being dragged, adjust positions
          if (draggedIndex !== -1 && targetIndex !== -1 && draggedIndex !== targetIndex) {
            var currentIndex = delegateItem.index;

            if (draggedIndex < targetIndex) {
              // Dragging down: shift items up between draggedIndex and targetIndex
              if (currentIndex > draggedIndex && currentIndex <= targetIndex) {
                return (currentIndex - 1) * (delegateItem.height + delegateItem.itemSpacing);
              }
            } else {
              // Dragging up: shift items down between targetIndex and draggedIndex
              if (currentIndex >= targetIndex && currentIndex < draggedIndex) {
                return (currentIndex + 1) * (delegateItem.height + delegateItem.itemSpacing);
              }
            }
          }

          return delegateItem.index * (delegateItem.height + delegateItem.itemSpacing);
        }

        Behavior on y {
          enabled: !delegateItem.dragging
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Style.easingTypeFast
            easing.bezierCurve: Style.easingCurveFast
          }
        }
      }
    }
  }
}
