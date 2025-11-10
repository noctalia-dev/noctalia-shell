import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

RowLayout {
  id: root

  property real minimumWidth: 200 * Style.uiScaleRatio
  property real popupHeight: 180 * Style.uiScaleRatio

  property string label: ""
  property string description: ""
  property var model
  property string currentKey: ""
  property string placeholder: ""

  readonly property real preferredHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio

  signal selected(string key)

  spacing: Style.marginL
  Layout.fillWidth: true

  function itemCount() {
    if (!root.model)
      return 0
    if (typeof root.model.count === 'number')
      return root.model.count
    if (Array.isArray(root.model))
      return root.model.length
    return 0
  }

  function getItem(index) {
    if (!root.model)
      return null
    if (typeof root.model.get === 'function')
      return root.model.get(index)
    if (Array.isArray(root.model))
      return root.model[index]
    return null
  }

  function findIndexByKey(key) {
    for (var i = 0; i < itemCount(); i++) {
      var item = getItem(i)
      if (item && item.key === key)
        return i
    }
    return -1
  }

  NLabel {
    label: root.label
    description: root.description
  }

  ComboBox {
    id: combo

    Layout.minimumWidth: root.minimumWidth
    Layout.preferredHeight: root.preferredHeight
    model: model
    currentIndex: findIndexByKey(currentKey)
    onActivated: {
      var item = getItem(combo.currentIndex)
      if (item && item.key !== undefined)
        root.selected(item.key)
    }

    background: Rectangle {
      implicitWidth: Style.baseWidgetSize * 3.75
      implicitHeight: preferredHeight
      color: Color.mSurface
      border.color: combo.activeFocus ? Color.mSecondary : Color.mOutline
      border.width: Style.borderS
      radius: Style.radiusM

      Behavior on border.color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }
    }

    contentItem: NText {
      leftPadding: Style.marginL
      rightPadding: combo.indicator.width + Style.marginL
      pointSize: Style.fontSizeM
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
      color: (combo.currentIndex >= 0 && combo.currentIndex < itemCount()) ? Color.mOnSurface : Color.mOnSurfaceVariant
      text: (combo.currentIndex >= 0 && combo.currentIndex < itemCount()) ? (getItem(combo.currentIndex) ? getItem(combo.currentIndex).name : root.placeholder) : root.placeholder
    }

    indicator: NIcon {
      x: combo.width - width - Style.marginM
      y: combo.topPadding + (combo.availableHeight - height) / 2
      icon: "caret-down"
      pointSize: Style.fontSizeL
    }

    popup: Popup {
      y: combo.height
      implicitWidth: combo.width - Style.marginM
      implicitHeight: Math.min(root.popupHeight, contentItem.implicitHeight + Style.marginM * 2)
      padding: Style.marginM

      contentItem: NListView {
        model: combo.popup.visible ? root.model : null
        implicitHeight: contentHeight
        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded

        delegate: ItemDelegate {
          property var parentComboBox: combo // Reference to the ComboBox
          property int itemIndex: index // Explicitly capture index
          width: parentComboBox ? parentComboBox.width : 0
          hoverEnabled: true
          highlighted: ListView.view.currentIndex === itemIndex

          onHoveredChanged: {
            if (hovered) {
              ListView.view.currentIndex = itemIndex
            }
          }

          onClicked: {
            var item = root.getItem(itemIndex)
            if (item && item.key !== undefined && parentComboBox) {
              root.selected(item.key)
              parentComboBox.currentIndex = itemIndex
              parentComboBox.popup.close()
            }
          }

          background: Rectangle {
            width: parentComboBox ? parentComboBox.width - Style.marginM * 3 : 0
            color: highlighted ? Color.mHover : Color.transparent
            radius: Style.radiusS
            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }

          contentItem: NText {
            text: {
              var item = root.getItem(index)
              return item && item.name ? item.name : ""
            }
            pointSize: Style.fontSizeM
            color: highlighted ? Color.mOnHover : Color.mOnSurface
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }
        }
      }

      background: Rectangle {
        color: Color.mSurfaceVariant
        border.color: Color.mOutline
        border.width: Style.borderS
        radius: Style.radiusM
      }
    }

    // Update the currentIndex if the currentKey is changed externalyu
    Connections {
      target: root
      function onCurrentKeyChanged() {
        combo.currentIndex = root.findIndexByKey(currentKey)
      }
    }
  }
}
