import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T
import qs.Commons

Item {
  id: root

  // Intercept all key events at the root level to prevent GridView from handling them
  Keys.onPressed: event => {
                    // Don't let this event reach the GridView
                    event.accepted = false;
                  }

  Keys.onReleased: event => {
                     event.accepted = false;
                   }

  property color handleColor: Qt.alpha(Color.mHover, 0.8)
  property color handleHoverColor: handleColor
  property color handlePressedColor: handleColor
  property color trackColor: Color.transparent
  property real handleWidth: 6
  property real handleRadius: Style.iRadiusM
  property int verticalPolicy: ScrollBar.AsNeeded
  property int horizontalPolicy: ScrollBar.AlwaysOff
  readonly property bool verticalScrollBarActive: {
    if (gridView.ScrollBar.vertical.policy === ScrollBar.AlwaysOff)
      return false;
    return gridView.contentHeight > gridView.height;
  }
  readonly property real scrollBarWidth: verticalScrollBarActive ? handleWidth : 0

  // Forward GridView properties
  property alias model: gridView.model
  property alias delegate: gridView.delegate
  property alias cellWidth: gridView.cellWidth
  property alias cellHeight: gridView.cellHeight
  property alias leftMargin: gridView.leftMargin
  property alias rightMargin: gridView.rightMargin
  property alias topMargin: gridView.topMargin
  property alias bottomMargin: gridView.bottomMargin
  property alias currentIndex: gridView.currentIndex
  property alias count: gridView.count
  property alias contentHeight: gridView.contentHeight
  property alias contentWidth: gridView.contentWidth
  property alias contentY: gridView.contentY
  property alias contentX: gridView.contentX
  property alias currentItem: gridView.currentItem
  property alias highlightItem: gridView.highlightItem
  property alias highlightFollowsCurrentItem: gridView.highlightFollowsCurrentItem
  property alias preferredHighlightBegin: gridView.preferredHighlightBegin
  property alias preferredHighlightEnd: gridView.preferredHighlightEnd
  property alias highlightRangeMode: gridView.highlightRangeMode
  property alias snapMode: gridView.snapMode
  property alias keyNavigationEnabled: gridView.keyNavigationEnabled
  property alias keyNavigationWraps: gridView.keyNavigationWraps
  property alias cacheBuffer: gridView.cacheBuffer
  property alias displayMarginBeginning: gridView.displayMarginBeginning
  property alias displayMarginEnd: gridView.displayMarginEnd
  property alias layoutDirection: gridView.layoutDirection
  property alias effectiveLayoutDirection: gridView.effectiveLayoutDirection
  property alias flow: gridView.flow
  property alias boundsBehavior: gridView.boundsBehavior
  property alias flickableDirection: gridView.flickableDirection
  property alias interactive: gridView.interactive
  property alias moving: gridView.moving
  property alias flicking: gridView.flicking
  property alias dragging: gridView.dragging
  property alias horizontalVelocity: gridView.horizontalVelocity
  property alias verticalVelocity: gridView.verticalVelocity

  // Forward GridView methods
  function positionViewAtIndex(index, mode) {
    gridView.positionViewAtIndex(index, mode);
  }

  function positionViewAtBeginning() {
    gridView.positionViewAtBeginning();
  }

  function positionViewAtEnd() {
    gridView.positionViewAtEnd();
  }

  function forceLayout() {
    gridView.forceLayout();
  }

  function cancelFlick() {
    gridView.cancelFlick();
  }

  function flick(xVelocity, yVelocity) {
    gridView.flick(xVelocity, yVelocity);
  }

  function incrementCurrentIndex() {
    gridView.incrementCurrentIndex();
  }

  function decrementCurrentIndex() {
    gridView.decrementCurrentIndex();
  }

  function indexAt(x, y) {
    return gridView.indexAt(x, y);
  }

  function itemAt(x, y) {
    return gridView.itemAt(x, y);
  }

  function itemAtIndex(index) {
    return gridView.itemAtIndex(index);
  }

  // Set reasonable implicit sizes for Layout usage
  implicitWidth: 200
  implicitHeight: 200

  GridView {
    id: gridView
    anchors.fill: parent

    // Enable clipping to keep content within bounds
    clip: true

    // Enable flickable for smooth scrolling
    boundsBehavior: Flickable.StopAtBounds

    // Completely disable focus to prevent any keyboard interaction
    focus: false
    activeFocusOnTab: false
    enabled: true  // Still enabled for mouse interaction

    // Override key navigation - do nothing
    Keys.onPressed: event => {
                      // Consume the event here so GridView doesn't process it
                      // but don't actually do anything
                      event.accepted = true;
                    }

    Keys.onReleased: event => {
                       event.accepted = true;
                     }

    ScrollBar.vertical: ScrollBar {
      parent: gridView
      x: gridView.mirrored ? 0 : gridView.width - width
      y: 0
      height: gridView.height
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
