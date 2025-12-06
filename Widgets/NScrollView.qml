import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T
import qs.Commons

T.ScrollView {
  id: root

  property color handleColor: Qt.alpha(Color.mHover, 0.8)
  property color handleHoverColor: handleColor
  property color handlePressedColor: handleColor
  property color trackColor: Color.transparent
  property real handleWidth: 6
  property real handleRadius: Style.iRadiusM
  property int verticalPolicy: ScrollBar.AsNeeded
  property int horizontalPolicy: ScrollBar.AsNeeded
  property bool preventHorizontalScroll: horizontalPolicy === ScrollBar.AlwaysOff
  property int boundsBehavior: Flickable.StopAtBounds
  property int flickableDirection: Flickable.VerticalFlick
  readonly property bool verticalScrollable: contentItem.contentHeight > contentItem.height
  readonly property bool horizontalScrollable: contentItem.contentWidth > contentItem.width

  implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset, contentWidth + leftPadding + rightPadding)
  implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset, contentHeight + topPadding + bottomPadding)

  // Configure the internal flickable when it becomes available
  Component.onCompleted: {
    configureFlickable();
  }

  // Function to configure the underlying Flickable
  function configureFlickable() {
    // Find the internal Flickable (it's usually the first child)
    for (var i = 0; i < children.length; i++) {
      var child = children[i];
      if (child.toString().indexOf("Flickable") !== -1) {
        // Configure the flickable to prevent horizontal scrolling
        child.boundsBehavior = root.boundsBehavior;

        if (root.preventHorizontalScroll) {
          child.flickableDirection = Flickable.VerticalFlick;
          child.contentWidth = Qt.binding(() => child.width);
        } else {
          child.flickableDirection = root.flickableDirection;
        }
        break;
      }
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
    active: root.ScrollBar.horizontal.active
    policy: root.verticalPolicy

    contentItem: Rectangle {
      implicitWidth: root.handleWidth
      implicitHeight: 100
      radius: root.handleRadius
      color: parent.pressed ? root.handlePressedColor : parent.hovered ? root.handleHoverColor : root.handleColor
      opacity: parent.policy === ScrollBar.AlwaysOn ? 1.0 : root.verticalScrollable ? (parent.active ? 1.0 : 0.0) : 0.0

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
      opacity: parent.policy === ScrollBar.AlwaysOn ? 0.3 : root.verticalScrollable ? (parent.active ? 0.3 : 0.0) : 0.0
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
    active: root.ScrollBar.vertical.active
    policy: root.horizontalPolicy

    contentItem: Rectangle {
      implicitWidth: 100
      implicitHeight: root.handleWidth
      radius: root.handleRadius
      color: parent.pressed ? root.handlePressedColor : parent.hovered ? root.handleHoverColor : root.handleColor
      opacity: parent.policy === ScrollBar.AlwaysOn ? 1.0 : root.horizontalScrollable ? (parent.active ? 1.0 : 0.0) : 0.0

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
      opacity: parent.policy === ScrollBar.AlwaysOn ? 0.3 : root.horizontalScrollable ? (parent.active ? 0.3 : 0.0) : 0.0
      radius: root.handleRadius / 2

      Behavior on opacity {
        NumberAnimation {
          duration: Style.animationFast
        }
      }
    }
  }
}
