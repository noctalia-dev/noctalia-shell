import QtQuick
import QtQuick.Layouts

import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  required property string message

  width: 450
  height: 60
  radius: 30
  color: Color.mError
  border.color: Color.mError
  border.width: 1
  opacity: visible ? 1.0 : 0.0

  RowLayout {
    anchors.centerIn: parent
    spacing: 10

    NIcon {
      icon: "alert-circle"
      pointSize: Style.fontSizeL
      color: Color.mOnError
    }

    NText {
      text: root.message || "Authentication failed"
      color: Color.mOnError
      pointSize: Style.fontSizeL
      font.weight: Font.Medium
      horizontalAlignment: Text.AlignHCenter
    }
  }

  Behavior on opacity {
    NumberAnimation {
      duration: 300
      easing.type: Easing.OutCubic
    }
  }
}
