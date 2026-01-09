import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI

Rectangle {
  id: root

  // Public properties
  property string text: ""
  property string icon: ""
  property string tooltipText
  property color backgroundColor: Color.mPrimary
  property color textColor: Color.mOnPrimary
  property color hoverColor: Color.mHover
  property color textHoverColor: Color.mOnHover
  property bool enabled: true
  property real fontSize: Style.fontSizeM
  property int fontWeight: Style.fontWeightSemiBold
  property real iconSize: Style.fontSizeL
  property bool outlined: false
  property int horizontalAlignment: Qt.AlignHCenter
  property real buttonRadius: Style.iRadiusS

  // Signals
  signal clicked
  signal rightClicked
  signal middleClicked
  signal entered
  signal exited

  // Internal properties
  property bool hovered: false
  readonly property color contentColor: {
    if (!root.enabled) {
      return Color.mOnSurfaceVariant;
    }
    if (root.hovered) {
      return root.textHoverColor;
    }
    if (root.outlined) {
      return root.backgroundColor;
    }
    return root.textColor;
  }

  // Dimensions
  implicitWidth: contentRow.implicitWidth + (fontSize * 2)
  implicitHeight: contentRow.implicitHeight + (fontSize)

  // Appearance
  radius: root.buttonRadius
  color: {
    if (!enabled)
      return outlined ? "transparent" : Qt.lighter(Color.mSurfaceVariant, 1.2);
    if (hovered)
      return hoverColor;
    return outlined ? "transparent" : backgroundColor;
  }

  border.width: outlined ? Style.borderS : 0
  border.color: {
    if (!enabled)
      return Color.mOutline;
    if (hovered)
      return backgroundColor;
    return outlined ? backgroundColor : "transparent";
  }

  opacity: enabled ? 1.0 : 0.6

  Behavior on color {
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  Behavior on border.color {
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  // Content
  RowLayout {
    id: contentRow
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: root.horizontalAlignment === Qt.AlignLeft ? parent.left : undefined
    anchors.horizontalCenter: root.horizontalAlignment === Qt.AlignHCenter ? parent.horizontalCenter : undefined
    anchors.leftMargin: root.horizontalAlignment === Qt.AlignLeft ? Style.marginL : 0
    spacing: Style.marginXS

    // Icon (optional)
    NIcon {
      Layout.alignment: Qt.AlignVCenter
      visible: root.icon !== ""
      icon: root.icon
      pointSize: root.iconSize
      color: contentColor

      Behavior on color {
        ColorAnimation {
          duration: Style.animationFast
          easing.type: Easing.OutCubic
        }
      }
    }

    // Text
    NText {
      Layout.alignment: Qt.AlignVCenter
      visible: root.text !== ""
      text: root.text
      pointSize: root.fontSize
      font.weight: root.fontWeight
      color: contentColor

      Behavior on color {
        ColorAnimation {
          duration: Style.animationFast
          easing.type: Easing.OutCubic
        }
      }
    }
  }

  // Mouse interaction
  MouseArea {
    id: mouseArea
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

    onEntered: {
      root.hovered = true;
      root.entered();
      if (tooltipText) {
        TooltipService.show(root, root.tooltipText);
      }
    }
    onExited: {
      root.hovered = false;
      root.exited();
      if (tooltipText) {
        TooltipService.hide();
      }
    }
    onPressed: mouse => {
                 if (tooltipText) {
                   TooltipService.hide();
                 }
                 if (mouse.button === Qt.LeftButton) {
                   root.clicked();
                 } else if (mouse.button == Qt.RightButton) {
                   root.rightClicked();
                 } else if (mouse.button == Qt.MiddleButton) {
                   root.middleClicked();
                 }
               }

    onCanceled: {
      root.hovered = false;
      if (tooltipText) {
        TooltipService.hide();
      }
    }
  }
}
