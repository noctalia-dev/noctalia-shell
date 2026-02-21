import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

Rectangle {
  id: root

  // Public properties
  // Public properties
  property string text: ""
  property string icon: ""
  property string tooltipText: ""
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
  implicitWidth: contentLayout.implicitWidth + Style.margin2M

  topLeftRadius: isFirst ? Style.iRadiusM : Style.iRadiusXXXS
  bottomLeftRadius: isFirst ? Style.iRadiusM : Style.iRadiusXXXS
  topRightRadius: isLast ? Style.iRadiusM : Style.iRadiusXXXS
  bottomRightRadius: isLast ? Style.iRadiusM : Style.iRadiusXXXS

  color: root.isHovered ? Color.mHover : (root.checked ? Color.mPrimary : Color.mSurface)
  border.color: Color.mOutline
  border.width: Style.borderS

  Behavior on color {
    enabled: !Color.isTransitioning
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  // Content
  RowLayout {
    id: contentLayout
    anchors.centerIn: parent
    width: Math.min(implicitWidth, parent.width - Style.margin2S)
    spacing: (root.icon !== "" && root.text !== "") ? Style.marginXS : 0

    NIcon {
      visible: root.icon !== ""
      Layout.alignment: Qt.AlignVCenter
      icon: root.icon
      pointSize: root.pointSize * 1.2
      color: root.isHovered ? Color.mOnHover : (root.checked ? Color.mOnPrimary : Color.mOnSurface)

      Behavior on color {
        enabled: !Color.isTransitioning
        ColorAnimation {
          duration: Style.animationFast
          easing.type: Easing.OutCubic
        }
      }
    }

    NText {
      id: tabText
      visible: root.text !== ""
      Layout.alignment: Qt.AlignVCenter
      text: root.text
      pointSize: root.pointSize
      font.weight: Style.fontWeightSemiBold
      color: root.isHovered ? Color.mOnHover : (root.checked ? Color.mOnPrimary : Color.mOnSurface)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter

      Behavior on color {
        enabled: !Color.isTransitioning
        ColorAnimation {
          duration: Style.animationFast
          easing.type: Easing.OutCubic
        }
      }
    }
  }

  // Tooltip
  Timer {
    id: tooltipTimer
    interval: 500
    onTriggered: {
      if (root.isHovered && root.tooltipText !== "") {
        TooltipService.show(root, root.tooltipText);
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: {
      root.isHovered = true;
      if (root.tooltipText !== "") {
        tooltipTimer.start();
      }
    }
    onExited: {
      root.isHovered = false;
      tooltipTimer.stop();
      if (root.tooltipText !== "") {
        TooltipService.hide();
      }
    }
    onClicked: {
      root.clicked();
      // Update parent NTabBar's currentIndex
      if (root.parent && root.parent.parent && root.parent.parent.currentIndex !== undefined) {
        root.parent.parent.currentIndex = root.tabIndex;
      }
    }
  }
}
