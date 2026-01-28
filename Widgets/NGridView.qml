import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T
import qs.Commons

Item {
  id: root

  // Signal for key press events when keyNavigationEnabled is true
  signal keyPressed(var event)

  property color handleColor: Qt.alpha(Color.mHover, 0.8)
  property color handleHoverColor: handleColor
  property color handlePressedColor: handleColor
  property color trackColor: "transparent"
  property real handleWidth: 6
  property real handleRadius: Style.iRadiusM
  property int verticalPolicy: ScrollBar.AsNeeded
  property int horizontalPolicy: ScrollBar.AlwaysOff
  readonly property bool verticalScrollBarActive: {
    if (gridView.ScrollBar.vertical.policy === ScrollBar.AlwaysOff)
      return false;
    return gridView.contentHeight > gridView.height;
  }
  readonly property bool contentOverflows: gridView.contentHeight > gridView.height

  // Gradient properties
  property bool showGradientMasks: true
  property color gradientColor: Color.mSurfaceVariant
  property int gradientHeight: 16
  property bool reserveScrollbarSpace: true

  // Available width for content (excludes scrollbar space when reserveScrollbarSpace is true)
  // Note: Always reserves space when enabled to avoid binding loops with cellWidth calculations
  readonly property real availableWidth: width - (reserveScrollbarSpace ? handleWidth + Style.marginXS : 0)

  // Expose activeFocus from internal gridView
  readonly property bool hasActiveFocus: gridView.activeFocus

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
  property alias reuseItems: gridView.reuseItems

  // Scroll speed multiplier for mouse wheel (1.0 = default, higher = faster)
  property real wheelScrollMultiplier: 2.0

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

  function forceActiveFocus() {
    gridView.forceActiveFocus();
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

  function moveCurrentIndexUp() {
    gridView.moveCurrentIndexUp();
  }

  function moveCurrentIndexDown() {
    gridView.moveCurrentIndexDown();
  }

  function moveCurrentIndexLeft() {
    gridView.moveCurrentIndexLeft();
  }

  function moveCurrentIndexRight() {
    gridView.moveCurrentIndexRight();
  }

  // Set reasonable implicit sizes for Layout usage
  implicitWidth: 200
  implicitHeight: 200

  Component.onCompleted: {
    createGradients();
  }

  // Dynamically create gradient overlays
  function createGradients() {
    if (!showGradientMasks)
      return;

    Qt.createQmlObject(`
      import QtQuick
      import qs.Commons
      Rectangle {
        x: 0
        y: 0
        width: root.availableWidth
        height: root.gradientHeight
        z: 1
        visible: root.showGradientMasks && root.contentOverflows
        opacity: gridView.contentY <= 1 ? 0 : 1
        Behavior on opacity {
          NumberAnimation { duration: Style.animationFast; easing.type: Easing.InOutQuad }
        }
        gradient: Gradient {
          GradientStop { position: 0.0; color: root.gradientColor }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }
    `, root, "topGradient");

    Qt.createQmlObject(`
      import QtQuick
      import qs.Commons
      Rectangle {
        x: 0
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -1
        width: root.availableWidth
        height: root.gradientHeight + 1
        z: 1
        visible: root.showGradientMasks && root.contentOverflows
        opacity: (gridView.contentY + gridView.height >= gridView.contentHeight - 1) ? 0 : 1
        Behavior on opacity {
          NumberAnimation { duration: Style.animationFast; easing.type: Easing.InOutQuad }
        }
        gradient: Gradient {
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 1.0; color: root.gradientColor }
        }
      }
    `, root, "bottomGradient");
  }

  GridView {
    id: gridView
    anchors.fill: parent
    anchors.rightMargin: root.reserveScrollbarSpace ? root.handleWidth + Style.marginXS : 0

    // Enable clipping to keep content within bounds
    clip: true

    // Enable flickable for smooth scrolling
    boundsBehavior: Flickable.StopAtBounds

    // Focus handling depends on keyNavigationEnabled
    focus: keyNavigationEnabled
    activeFocusOnTab: keyNavigationEnabled

    // Emit keyPressed signal for custom key handling
    Keys.onPressed: event => {
                      if (keyNavigationEnabled) {
                        root.keyPressed(event);
                      }
                    }

    WheelHandler {
      enabled: root.wheelScrollMultiplier !== 1.0
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: event => {
                 const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8;
                 const newY = gridView.contentY - (delta * root.wheelScrollMultiplier);
                 gridView.contentY = Math.max(0, Math.min(newY, gridView.contentHeight - gridView.height));
                 event.accepted = true;
               }
    }

    ScrollBar.vertical: ScrollBar {
      parent: root
      x: root.mirrored ? 0 : root.width - width
      y: 0
      height: root.height
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
