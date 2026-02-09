import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: root
  objectName: "NTabView"

  property int currentIndex: 0

  // Private
  property int previousIndex: 0
  property bool initialized: false
  property bool animating: false
  property real animatingHeight: 0
  property real transitionGap: Style.marginXL
  property real transitionTime: Style.animationNormal
  property list<Item> contentItems: []

  default property alias content: container.data

  clip: true
  Layout.fillWidth: true

  // During animation, use max height to prevent clipping. Otherwise use current item height.
  implicitHeight: animating ? animatingHeight : (contentItems[currentIndex] ? contentItems[currentIndex].implicitHeight : 0)

  Item {
    id: container
    anchors.fill: parent
  }

  // Set the visible tab to idx without triggering a slide animation.
  // Call this BEFORE the bound currentIndex changes so that
  // onCurrentIndexChanged sees previousIndex === currentIndex and skips.
  function setIndexWithoutAnimation(idx) {
    fromXAnim.stop();
    fromOpacityAnim.stop();
    toXAnim.stop();
    toOpacityAnim.stop();
    animating = false;
    previousIndex = idx;
    for (let i = 0; i < contentItems.length; i++) {
      if (i === idx) {
        contentItems[i].x = 0;
        contentItems[i].visible = true;
        contentItems[i].opacity = 1.0;
      } else {
        contentItems[i].x = root.width;
        contentItems[i].visible = false;
        contentItems[i].opacity = 1.0;
      }
    }
  }

  Component.onCompleted: {
    _initializeItems();
  }

  function _initializeItems() {
    contentItems = [];
    for (let i = 0; i < container.children.length; i++) {
      const child = container.children[i];
      contentItems.push(child);
      child.width = Qt.binding(() => root.width);

      if (i === currentIndex) {
        child.x = 0;
        child.visible = true;
      } else {
        child.x = root.width;
        child.visible = false;
      }
    }
    initialized = true;
  }

  onCurrentIndexChanged: {
    if (!initialized || contentItems.length === 0)
      return;
    if (previousIndex === currentIndex)
      return;

    _animateTransition(previousIndex, currentIndex);
    previousIndex = currentIndex;
  }

  function _animateTransition(fromIdx, toIdx) {
    // Stop any running animations
    fromXAnim.stop();
    fromOpacityAnim.stop();
    toXAnim.stop();
    toOpacityAnim.stop();

    // Reset all items to clean state (except target)
    for (let i = 0; i < contentItems.length; i++) {
      if (i !== toIdx) {
        contentItems[i].visible = false;
        contentItems[i].opacity = 1.0;
      }
    }

    const fromItem = contentItems[fromIdx];
    const toItem = contentItems[toIdx];
    const slideLeft = toIdx > fromIdx;

    // Set height to max of both items during animation
    const fromHeight = fromItem ? fromItem.implicitHeight : 0;
    const toHeight = toItem ? toItem.implicitHeight : 0;
    animatingHeight = Math.max(fromHeight, toHeight);
    animating = true;

    // Position outgoing item and make visible for animation
    if (fromItem) {
      fromItem.visible = true;
      fromItem.x = 0;
      fromItem.opacity = 1.0;
    }

    // Position incoming item off-screen (with gap) and set initial opacity
    if (toItem) {
      toItem.visible = true;
      toItem.x = slideLeft ? root.width + transitionGap : -root.width - transitionGap;
      toItem.opacity = 0.0;
    }

    // Animate both items together (with gap)
    if (fromItem) {
      fromXAnim.target = fromItem;
      fromXAnim.to = slideLeft ? -root.width - transitionGap : root.width + transitionGap;
      fromOpacityAnim.target = fromItem;
      fromXAnim.start();
      fromOpacityAnim.start();
    }

    if (toItem) {
      toXAnim.target = toItem;
      toOpacityAnim.target = toItem;
      toXAnim.start();
      toOpacityAnim.start();
    }
  }

  NumberAnimation {
    id: fromXAnim
    property: "x"
    duration: root.transitionTime
    easing.type: Style.easingTypeDefault
    onFinished: {
      if (target && target !== contentItems[currentIndex]) {
        target.visible = false;
        target.opacity = 1.0;
      }
      animating = false;
    }
  }

  NumberAnimation {
    id: fromOpacityAnim
    property: "opacity"
    to: 0.25
    duration: root.transitionTime
    easing.type: Style.easingTypeDefault
  }

  NumberAnimation {
    id: toXAnim
    property: "x"
    to: 0
    duration: root.transitionTime
    easing.type: Style.easingTypeDefault
  }

  NumberAnimation {
    id: toOpacityAnim
    property: "opacity"
    to: 1.0
    duration: root.transitionTime
    easing.type: Style.easingTypeDefault
  }
}
