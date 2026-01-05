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
  property real pointSize: Style.fontSizeM

  // Internal state
  property bool isHovered: false

  signal clicked

  // Sizing
  Layout.fillHeight: true
  implicitWidth: tabText.implicitWidth + Style.marginM * 2

  // Styling
  radius: Style.iRadiusM
  color: root.isHovered ? Color.mHover : (root.checked ? Color.mPrimary : Color.mSurface)

  Behavior on color {
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  NText {
    id: tabText
    anchors {
      left: parent.left
      right: parent.right
      verticalCenter: parent.verticalCenter
      leftMargin: Style.marginS
      rightMargin: Style.marginS
    }
    text: root.text
    pointSize: root.pointSize
    font.weight: Style.fontWeightSemiBold
    color: root.isHovered ? Color.mOnHover : (root.checked ? Color.mOnPrimary : Color.mOnSurface)
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
      root.clicked();
      // Update parent NTabBar's currentIndex
      if (root.parent && root.parent.parent && root.parent.parent.currentIndex !== undefined) {
        root.parent.parent.currentIndex = root.tabIndex;
      }
    }
  }
}
