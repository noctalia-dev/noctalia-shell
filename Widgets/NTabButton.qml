import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  // Public properties
  property string text: ""
  property bool checked: false
  property int tabIndex: 0

  // Internal state
  property bool isHovered: false

  signal clicked

  // Sizing
  Layout.fillWidth: true
  Layout.fillHeight: true

  // Styling
  radius: Style.radiusXS
  color: root.checked ? Color.mPrimary : (root.isHovered ? Color.mHover : Color.mSurface)

  Behavior on color {
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  NText {
    id: tabText
    anchors.centerIn: parent
    text: root.text
    pointSize: Style.fontSizeM
    font.weight: root.checked ? Style.fontWeightSemiBold : Style.fontWeightRegular
    color: root.checked ? Color.mOnPrimary : root.isHovered ? Color.mOnHover : Color.mOnSurface
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCubic
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.isHovered = true
    onExited: root.isHovered = false
    onClicked: {
      root.clicked()
      // Update parent NTabBar's currentIndex
      if (root.parent && root.parent.parent && root.parent.parent.currentIndex !== undefined) {
        root.parent.parent.currentIndex = root.tabIndex
      }
    }
  }
}
