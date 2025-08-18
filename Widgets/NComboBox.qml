import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  readonly property real preferredHeight: Style.baseWidgetSize * 1.25 * scaling

  property string label: ""
  property string description: ""
  property ListModel model: {

  }
  property string currentKey: ''

  signal selected(string key)

  spacing: Style.marginSmall * scaling
  Layout.fillWidth: true

  ColumnLayout {
    spacing: Style.marginTiniest * scaling
    Layout.fillWidth: true
    NText {
      text: label
      font.pointSize: Style.fontSizeMedium * scaling
      font.weight: Style.fontWeightBold
      color: Color.mOnSurface
    }
    NText {
      text: description
      font.pointSize: Style.fontSizeSmall * scaling
      color: Color.mOnSurface
      wrapMode: Text.WordWrap
    }
  }

  function findIndexByKey(key) {
    for (var i = 0; i < root.model.count; i++) {
      if (root.model.get(i).key === key) {
        return i
      }
    }
    return -1
  }

  ComboBox {
    id: combo
    Layout.fillWidth: true
    Layout.preferredHeight: height
    model: model
    currentIndex: findIndexByKey(currentKey)
    onActivated: {
      root.selected(model.get(combo.currentIndex).key)
    }

    background: Rectangle {
      implicitWidth: Style.baseWidgetSize * 3.75 * scaling
      implicitHeight: preferredHeight
      color: Color.mSurface
      border.color: combo.activeFocus ? Color.mTertiary : Color.mOutline
      border.width: Math.max(1, Style.borderThin * scaling)
      radius: Style.radiusMedium * scaling
    }

    contentItem: NText {
      leftPadding: Style.marginLarge * scaling
      rightPadding: combo.indicator.width + Style.marginLarge * scaling
      font.pointSize: Style.fontSizeMedium * scaling
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
      text: (combo.currentIndex >= 0 && combo.currentIndex < root.model.count) ? root.model.get(
                                                                                   combo.currentIndex).name : ""
    }

    indicator: NIcon {
      x: combo.width - width - Style.marginMedium * scaling
      y: combo.topPadding + (combo.availableHeight - height) / 2
      text: "arrow_drop_down"
      font.pointSize: Style.fontSizeXL * scaling
    }

    popup: Popup {
      y: combo.height
      width: combo.width
      implicitHeight: Math.min(160 * scaling, contentItem.implicitHeight + Style.marginMedium * scaling * 2)
      padding: Style.marginMedium * scaling

      contentItem: ListView {
        property var comboBoxRoot: root
        clip: true
        implicitHeight: contentHeight
        model: combo.popup.visible ? root.model : null
        ScrollIndicator.vertical: ScrollIndicator {}

        delegate: ItemDelegate {
          width: combo.width
          hoverEnabled: true
          highlighted: ListView.view.currentIndex === index

          onHoveredChanged: {
            if (hovered) {
              ListView.view.currentIndex = index
            }
          }

          onClicked: {
            ListView.view.comboBoxRoot.selected(ListView.view.comboBoxRoot.model.get(index).key)
            combo.currentIndex = index
            combo.popup.close()
          }

          contentItem: NText {
            text: name
            font.pointSize: Style.fontSizeMedium * scaling
            color: highlighted ? Color.mSurface : Color.mOnSurface
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          background: Rectangle {
            width: combo.width - Style.marginMedium * scaling * 3
            color: highlighted ? Color.mTertiary : Color.transparent
            radius: Style.radiusSmall * scaling
          }
        }
      }

      background: Rectangle {
        color: Color.mSurfaceVariant
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderThin * scaling)
        radius: Style.radiusMedium * scaling
      }
    }
  }
}
