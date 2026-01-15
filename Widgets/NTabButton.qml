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
  property bool isFirst: false
  property bool isLast: false

  // Internal state
  property bool isHovered: false

  signal clicked

  // Sizing
  Layout.fillHeight: true
  implicitWidth: tabText.implicitWidth + Style.marginM * 2

  topLeftRadius: isFirst ? Style.iRadiusM : Style.iRadiusXXS
  bottomLeftRadius: isFirst ? Style.iRadiusM : Style.iRadiusXXS
  topRightRadius: isLast ? Style.iRadiusM : Style.iRadiusXXS
  bottomRightRadius: isLast ? Style.iRadiusM : Style.iRadiusXXS

  color: root.isHovered ? Color.mHover : (root.checked ? Color.mPrimary : Color.mSurface)
  border.color: Color.mOutline
  border.width: Style.borderS

  Behavior on color {
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  NText {
    id: tabText
    y: Style.pixelAlignCenter(parent.height, height)
    anchors {
      left: parent.left
      right: parent.right
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
