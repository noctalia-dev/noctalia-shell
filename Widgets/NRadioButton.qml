import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Widgets

RadioButton {
  id: root

  property real pointSize: Style.fontSizeM

  indicator: Rectangle {
    id: outerCircle

    implicitWidth: Style.baseWidgetSize * 0.625 * pointSize / Style.fontSizeM
    implicitHeight: Style.baseWidgetSize * 0.625 * pointSize / Style.fontSizeM
    radius: width * 0.5
    color: Color.transparent
    border.color: root.checked ? Color.mPrimary : Color.mOnSurface
    border.width: Style.borderM
    anchors.verticalCenter: parent.verticalCenter

    Rectangle {
      anchors.fill: parent
      anchors.margins: parent.width * 0.3

      radius: width * 0.5
      color: Qt.alpha(Color.mPrimary, root.checked ? 1 : 0)

      Behavior on color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }
    }

    Behavior on border.color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }
  }

  contentItem: NText {
    text: root.text
    pointSize: root.pointSize
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: outerCircle.right
    anchors.right: parent.right
    anchors.leftMargin: Style.marginS
  }
}
