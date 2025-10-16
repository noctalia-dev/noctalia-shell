import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

RowLayout {
  id: root

  // Public API
  property string label: ""
  property string description: ""
  property bool checked: false
  property bool hovering: false
  property color activeColor: Color.mPrimary
  property color activeOnColor: Color.mOnPrimary
  property int baseSize: Style.baseWidgetSize * 0.7

  signal toggled(bool checked)
  signal entered
  signal exited

  Layout.fillWidth: true

  NLabel {
    label: root.label
    description: root.description
    visible: root.label !== "" || root.description !== ""
  }

  // Spacer to push the checkbox to the far right
  Item {
    Layout.fillWidth: true
  }

  Rectangle {
    id: box

    implicitWidth: Math.round(root.baseSize)
    implicitHeight: Math.round(root.baseSize)
    radius: Style.radiusXS
    color: root.checked ? root.activeColor : Color.mSurface
    border.color: Color.mOutline
    border.width: Math.max(1, Style.borderS)

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
      visible: root.checked
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: -1
      icon: "check"
      color: root.activeOnColor
      pointSize: Math.max(Style.fontSizeXS, root.baseSize * 0.5)
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true
      onEntered: {
        hovering = true
        root.entered()
      }
      onExited: {
        hovering = false
        root.exited()
      }
      onClicked: root.toggled(!root.checked)
    }
  }
}
