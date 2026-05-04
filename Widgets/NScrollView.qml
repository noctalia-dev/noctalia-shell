import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T
import qs.Commons

ScrollView {
  id: root

  property color handleColor: Qt.alpha(Color.mHover, 0.8)
  property color handleHoverColor: handleColor
  property color handlePressedColor: handleColor
  property color trackColor: "transparent"
  property real handleWidth: Math.round(6 * Style.uiScaleRatio)
  property real handleRadius: Style.iRadiusM
  property int verticalPolicy: ScrollBar.AsNeeded
  property int horizontalPolicy: ScrollBar.AsNeeded
  property bool preventHorizontalScroll: horizontalPolicy === ScrollBar.AlwaysOff
  property int boundsBehavior: Flickable.StopAtBounds
  readonly property bool verticalScrollable: (contentItem.contentHeight > contentItem.height) || (verticalPolicy == ScrollBar.AlwaysOn)
  readonly property bool horizontalScrollable: (contentItem.contentWidth > contentItem.width) || (horizontalPolicy == ScrollBar.AlwaysOn)
  property bool showGradientMasks: true
  property color gradientColor: Color.mSurfaceVariant
  property int gradientHeight: 16
  property bool reserveScrollbarSpace: true
  property real userRightPadding: 0
  // Keep scrollbars visible whenever overflow exists (without forcing visibility when not scrollable)
  property bool showScrollbarWhenScrollable: Settings.data.ui.scrollbarAlwaysVisible

  // Scroll speed multiplier for mouse wheel (1.0 = default, higher = faster)
  property real wheelScrollMultiplier: 2.0
  property int smoothWheelAnimationDuration: Style.animationNormal
  property real _wheelTargetY: 0

  function clampScrollY(value) {
    if (!root._internalFlickable)
      return 0;
    const flickable = root._internalFlickable;
    return Math.max(0, Math.min(value, flickable.contentHeight - flickable.height));
  }

  function applyWheelScroll(delta) {
    if (!root._internalFlickable)
      return;

    const flickable = root._internalFlickable;
    const step = delta * root.wheelScrollMultiplier;

    if (!Settings.data.general.smoothScrollEnabled || Settings.data.general.animationDisabled) {
      flickable.contentY = root.clampScrollY(flickable.contentY - step);
      root._wheelTargetY = flickable.contentY;
      return;
    }

    if (!wheelScrollAnimation.running)
      root._wheelTargetY = flickable.contentY;

    root._wheelTargetY = root.clampScrollY(root._wheelTargetY - step);
    wheelScrollAnimation.to = root._wheelTargetY;
    wheelScrollAnimation.restart();
  }

  rightPadding: userRightPadding + (reserveScrollbarSpace && verticalScrollable ? handleWidth + Style.marginXS : 0)

  implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset, contentWidth + leftPadding + rightPadding)
  implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset, contentHeight + topPadding + bottomPadding)

  // Configure the internal flickable when it becomes available
  Component.onCompleted: {
    configureFlickable();
    createGradients();
  }

  // Dynamically create gradient overlays to avoid interfering with ScrollView content management
  function createGradients() {
    if (!showGradientMasks)
      return;

    Qt.createQmlObject(`
      import QtQuick
      import qs.Commons
      Rectangle {
        x: root.leftPadding
        y: root.topPadding
        width: root.availableWidth
        height: root.gradientHeight
        z: 1
        visible: root.showGradientMasks && root.verticalScrollable
        opacity: root.contentItem.contentY <= 1 ? 0 : 1
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
        x: root.leftPadding
        y: root.height - root.bottomPadding - height + 1
        width: root.availableWidth
        height: root.gradientHeight + 1
        z: 1
        visible: root.showGradientMasks && root.verticalScrollable
        opacity: (root.contentItem.contentY + root.contentItem.height >= root.contentItem.contentHeight - 1) ? 0 : 1
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

  // Reference to the internal Flickable for wheel handling
  property Flickable _internalFlickable: null

  NumberAnimation {
    id: wheelScrollAnimation
    target: root._internalFlickable
    property: "contentY"
    duration: root.smoothWheelAnimationDuration
    easing.type: Easing.OutCubic
  }

  Connections {
    target: root._internalFlickable

    function onDraggingChanged() {
      if (!root._internalFlickable || !root._internalFlickable.dragging)
        return;
      wheelScrollAnimation.stop();
      root._wheelTargetY = root._internalFlickable.contentY;
    }

    function onFlickingChanged() {
      if (!root._internalFlickable || !root._internalFlickable.flicking)
        return;
      wheelScrollAnimation.stop();
      root._wheelTargetY = root._internalFlickable.contentY;
    }

    function onContentHeightChanged() {
      root._wheelTargetY = root.clampScrollY(root._wheelTargetY);
    }

    function onHeightChanged() {
      root._wheelTargetY = root.clampScrollY(root._wheelTargetY);
    }
  }

  // Function to configure the underlying Flickable
  function configureFlickable() {
    // Find the internal Flickable (it's usually the first child)
    for (var i = 0; i < children.length; i++) {
      var child = children[i];
      if (child.toString().indexOf("Flickable") !== -1) {
        // Configure the flickable to prevent horizontal scrolling
        child.boundsBehavior = root.boundsBehavior;
        root._internalFlickable = child;

        if (root.preventHorizontalScroll) {
          child.flickableDirection = Flickable.VerticalFlick;
          child.contentWidth = Qt.binding(() => child.width);
        }

        root._wheelTargetY = child.contentY;
        break;
      }
    }
  }

  WheelHandler {
    enabled: root.wheelScrollMultiplier !== 1.0 && root._internalFlickable !== null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
               const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
               root.applyWheelScroll(delta);
               event.accepted = true;
             }
  }

  // Watch for changes in horizontalPolicy
  onHorizontalPolicyChanged: {
    preventHorizontalScroll = (horizontalPolicy === ScrollBar.AlwaysOff);
    configureFlickable();
  }

  ScrollBar.vertical: ScrollBar {
    parent: root
    x: root.mirrored ? 0 : root.width - width
    y: root.topPadding
    height: root.availableHeight
    policy: root.verticalPolicy
    interactive: root.verticalScrollable

    contentItem: Rectangle {
      implicitWidth: root.handleWidth
      implicitHeight: 100
      radius: root.handleRadius
      color: parent.pressed ? root.handlePressedColor : parent.hovered ? root.handleHoverColor : root.handleColor
      opacity: parent.policy === ScrollBar.AlwaysOn ? 1.0 : root.verticalScrollable ? ((root.showScrollbarWhenScrollable || parent.active) ? 1.0 : 0.0) : 0.0

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
      opacity: parent.policy === ScrollBar.AlwaysOn ? 0.3 : root.verticalScrollable ? ((root.showScrollbarWhenScrollable || parent.active) ? 0.3 : 0.0) : 0.0
      radius: root.handleRadius / 2

      Behavior on opacity {
        NumberAnimation {
          duration: Style.animationFast
        }
      }
    }
  }

  ScrollBar.horizontal: ScrollBar {
    parent: root
    x: root.leftPadding
    y: root.height - height
    width: root.availableWidth
    policy: root.horizontalPolicy
    interactive: root.horizontalScrollable

    contentItem: Rectangle {
      implicitWidth: 100
      implicitHeight: root.handleWidth
      radius: root.handleRadius
      color: parent.pressed ? root.handlePressedColor : parent.hovered ? root.handleHoverColor : root.handleColor
      opacity: parent.policy === ScrollBar.AlwaysOn ? 1.0 : root.horizontalScrollable ? ((root.showScrollbarWhenScrollable || parent.active) ? 1.0 : 0.0) : 0.0

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
      implicitWidth: 100
      implicitHeight: root.handleWidth
      color: root.trackColor
      opacity: parent.policy === ScrollBar.AlwaysOn ? 0.3 : root.horizontalScrollable ? ((root.showScrollbarWhenScrollable || parent.active) ? 0.3 : 0.0) : 0.0
      radius: root.handleRadius / 2

      Behavior on opacity {
        NumberAnimation {
          duration: Style.animationFast
        }
      }
    }
  }
}
