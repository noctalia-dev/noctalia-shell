import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T
import qs.Commons

Item {
  id: root

  property color handleColor: Qt.alpha(Color.mHover, 0.8)
  property color handleHoverColor: handleColor
  property color handlePressedColor: handleColor
  property color trackColor: "transparent"
  property real handleWidth: 6
  property real handleRadius: Style.iRadiusM
  property int verticalPolicy: ScrollBar.AsNeeded
  property int horizontalPolicy: ScrollBar.AlwaysOff
  readonly property bool verticalScrollBarActive: {
    if (listView.ScrollBar.vertical.policy === ScrollBar.AlwaysOff)
      return false;
    return listView.contentHeight > listView.height;
  }

  // Forward ListView properties
  property alias model: listView.model
  property alias delegate: listView.delegate
  property alias spacing: listView.spacing
  property alias orientation: listView.orientation
  property alias currentIndex: listView.currentIndex
  property alias count: listView.count
  property alias contentHeight: listView.contentHeight
  property alias contentWidth: listView.contentWidth
  property alias contentY: listView.contentY
  property alias contentX: listView.contentX
  property alias currentItem: listView.currentItem
  property alias highlightItem: listView.highlightItem
  property alias headerItem: listView.headerItem
  property alias footerItem: listView.footerItem
  property alias section: listView.section
  property alias highlightFollowsCurrentItem: listView.highlightFollowsCurrentItem
  property alias highlightMoveDuration: listView.highlightMoveDuration
  property alias highlightMoveVelocity: listView.highlightMoveVelocity
  property alias preferredHighlightBegin: listView.preferredHighlightBegin
  property alias preferredHighlightEnd: listView.preferredHighlightEnd
  property alias highlightRangeMode: listView.highlightRangeMode
  property alias snapMode: listView.snapMode
  property alias keyNavigationWraps: listView.keyNavigationWraps
  property alias cacheBuffer: listView.cacheBuffer
  property alias displayMarginBeginning: listView.displayMarginBeginning
  property alias displayMarginEnd: listView.displayMarginEnd
  property alias layoutDirection: listView.layoutDirection
  property alias effectiveLayoutDirection: listView.effectiveLayoutDirection
  property alias verticalLayoutDirection: listView.verticalLayoutDirection
  property alias boundsBehavior: listView.boundsBehavior
  property alias flickableDirection: listView.flickableDirection
  property alias interactive: listView.interactive
  property alias moving: listView.moving
  property alias flicking: listView.flicking
  property alias dragging: listView.dragging
  property alias horizontalVelocity: listView.horizontalVelocity
  property alias verticalVelocity: listView.verticalVelocity

  // Forward ListView methods
  function positionViewAtIndex(index, mode) {
    listView.positionViewAtIndex(index, mode);
  }

  function positionViewAtBeginning() {
    listView.positionViewAtBeginning();
  }

  function positionViewAtEnd() {
    listView.positionViewAtEnd();
  }

  function forceLayout() {
    listView.forceLayout();
  }

  function cancelFlick() {
    listView.cancelFlick();
  }

  function flick(xVelocity, yVelocity) {
    listView.flick(xVelocity, yVelocity);
  }

  function incrementCurrentIndex() {
    listView.incrementCurrentIndex();
  }

  function decrementCurrentIndex() {
    listView.decrementCurrentIndex();
  }

  function indexAt(x, y) {
    return listView.indexAt(x, y);
  }

  function itemAt(x, y) {
    return listView.itemAt(x, y);
  }

  function itemAtIndex(index) {
    return listView.itemAtIndex(index);
  }

  // Set reasonable implicit sizes for Layout usage
  implicitWidth: 200
  implicitHeight: 200

  ListView {
    id: listView
    anchors.fill: parent

    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ScrollBar.vertical: ScrollBar {
      parent: listView
      x: listView.mirrored ? 0 : listView.width - width
      y: 0
      height: listView.height
      policy: root.verticalPolicy

      contentItem: Rectangle {
        implicitWidth: root.handleWidth
        implicitHeight: 100
        radius: root.handleRadius
        color: parent.pressed ? root.handlePressedColor : parent.hovered ? root.handleHoverColor : root.handleColor
        opacity: parent.policy === ScrollBar.AlwaysOn ? 1.0 : root.verticalScrollBarActive ? (parent.active ? 1.0 : 0.0) : 0.0

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationFast
          }
        }

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }
      }

      background: Rectangle {
        implicitWidth: root.handleWidth
        implicitHeight: 100
        color: root.trackColor
        opacity: parent.policy === ScrollBar.AlwaysOn ? 0.3 : root.verticalScrollBarActive ? (parent.active ? 0.3 : 0.0) : 0.0
        radius: root.handleRadius / 2

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationFast
          }
        }
      }
    }
  }
}
