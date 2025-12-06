import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

RowLayout {
  id: root

  // Public properties
  property int value: 0
  property int from: 0
  property int to: 100
  property int stepSize: 1
  property string suffix: ""
  property string prefix: ""
  property string label: ""
  property string description: ""
  property bool enabled: true
  property bool hovering: false
  property int baseSize: Style.baseWidgetSize

  // Convenience properties for common naming
  property alias minimum: root.from
  property alias maximum: root.to

  // Properties for repeating
  property int initialRepeatDelay: 400   // The "pause" after the first click (in ms)
  property int repeatInterval: 80        // How often to step up after fist pause (ms)
  property int rampFactor: 4             // How many ticks to wait before increasing the step multiplier
  property int maxStepMultiplier: 10     // The max step (e.g., 10 * stepSize)
  property int _holdTicks: 0             // Internal counter for hold duration
  property int _repeatDirection: 0       // -1 for decrease, 1 for increase

  signal entered
  signal exited

  Layout.fillWidth: true

  Timer {
    id: repeatTimer
    repeat: true
    interval: root.initialRepeatDelay

    onTriggered: {
      if (repeatTimer.interval === root.initialRepeatDelay) {
        repeatTimer.interval = root.repeatInterval;
        root._holdTicks = 0;
      }
      root._holdTicks++;
      var stepMultiplier = Math.min(root.maxStepMultiplier, 1 + Math.floor(root._holdTicks / root.rampFactor));
      changeValue(root._repeatDirection, root.stepSize * stepMultiplier);
    }
  }

  function changeValue(direction, step) {
    var currentStep = step || root.stepSize;

    if (direction === 1 && root.value < root.to) {
      root.value = Math.min(root.to, root.value + currentStep);
    } else if (direction === -1 && root.value > root.from) {
      root.value = Math.max(root.from, root.value - currentStep);
    } else {
      return;
    }

    if (root.value === root.to || root.value === root.from) {
      stopRepeat();
    }
  }

  function stopRepeat() {
    root._repeatDirection = 0;
    repeatTimer.stop();
    repeatTimer.interval = root.initialRepeatDelay;
  }

  NLabel {
    label: root.label
    description: root.description
  }

  // Main spinbox container
  Rectangle {
    id: spinBoxContainer
    implicitWidth: 120
    implicitHeight: Math.round((root.baseSize - 4) / 2) * 2
    radius: Style.iRadiusS
    color: Color.mSurfaceVariant
    border.color: (root.hovering || decreaseArea.containsMouse || increaseArea.containsMouse) ? Color.mHover : Color.mOutline
    border.width: Style.borderS

    Behavior on border.color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }

    // Mouse area for hover and scroll
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      hoverEnabled: true
      onEntered: {
        root.hovering = true;
        root.entered();
      }
      onExited: {
        root.hovering = false;
        root.exited();
      }
      onWheel: wheel => {
                 if (wheel.angleDelta.y > 0 && root.value < root.to) {
                   let newValue = Math.min(root.to, root.value + root.stepSize);
                   root.value = newValue;
                 } else if (wheel.angleDelta.y < 0 && root.value > root.from) {
                   let newValue = Math.max(root.from, root.value - root.stepSize);
                   root.value = newValue;
                 }
               }
    }

    // Decrease button (left)
    Item {
      id: decreaseButton
      height: parent.height
      width: leftSemicircle.width + (leftDiamondContainer.width / 2)
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      opacity: (root.enabled && root.value > root.from) || decreaseArea.containsMouse ? 1.0 : 0.3
      clip: true

      Item {
        id: leftSemicircle
        width: Math.round(parent.height / 2)
        height: parent.height
        clip: true
        anchors.left: parent.left
        Rectangle {
          width: Math.round(parent.height)
          height: parent.height
          radius: Math.min(Style.iRadiusL, width / 2)
          anchors.left: parent.left
          color: decreaseArea.containsMouse ? Color.mHover : Color.transparent
          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }
      }

      Item {
        id: leftDiamondContainer

        height: Math.round(parent.height / 2) * 2
        width: height * Math.sqrt(2)
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: leftSemicircle.right

        Rectangle {
          id: leftDiamondVisual
          width: 100
          height: 100
          radius: width / 4

          color: decreaseArea.containsMouse ? Color.mHover : Color.transparent
          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }

          anchors.centerIn: parent

          transform: [
            Rotation {
              angle: 45
              origin.x: 50
              origin.y: 50
            },
            Scale {
              id: leftScaler
              origin.x: 50
              origin.y: 50

              // This is the full formula for the height of the rotated, rounded square
              readonly property real trueHeight: (leftDiamondVisual.width - 2 * leftDiamondVisual.radius) * Math.sqrt(2) + (2 * leftDiamondVisual.radius)
              xScale: leftDiamondContainer.height / leftScaler.trueHeight
              yScale: leftDiamondContainer.height / leftScaler.trueHeight
            }
          ]
        }
      }

      NIcon {
        anchors.left: parent.left
        anchors.leftMargin: parent.width * 0.25
        anchors.verticalCenter: parent.verticalCenter
        icon: "chevron-left"
        pointSize: Style.fontSizeS
        color: decreaseArea.containsMouse ? Color.mOnHover : Color.mPrimary
      }

      MouseArea {
        id: decreaseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.enabled && root.value > root.from
        onPressed: {
          root._repeatDirection = -1;
          changeValue(root._repeatDirection, root.stepSize);
          repeatTimer.start();
        }
        onReleased: stopRepeat()
        onExited: stopRepeat()
      }
    }

    // Increase button (right)
    Item {
      id: increaseButton
      height: parent.height
      width: rightSemicircle.width + (rightDiamondContainer.width / 2)
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      opacity: (root.enabled && root.value < root.to) || increaseArea.containsMouse ? 1.0 : 0.3
      clip: true

      Item {
        id: rightSemicircle
        width: Math.round(parent.height / 2)
        height: parent.height
        clip: true
        anchors.right: parent.right
        Rectangle {
          width: Math.round(parent.height)
          height: parent.height
          radius: Math.min(Style.iRadiusL, width / 2)
          anchors.right: parent.right
          color: increaseArea.containsMouse ? Color.mHover : Color.transparent
          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }
      }

      Item {
        id: rightDiamondContainer

        height: Math.round(parent.height / 2) * 2
        width: height * Math.sqrt(2)
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: rightSemicircle.left

        Rectangle {
          id: rightDiamondVisual
          width: 100
          height: 100
          radius: width / 4

          color: increaseArea.containsMouse ? Color.mHover : Color.transparent
          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }

          anchors.centerIn: parent

          transform: [
            Rotation {
              angle: 45
              origin.x: 50
              origin.y: 50
            },
            Scale {
              id: rightScaler
              origin.x: 50
              origin.y: 50

              // This is the full formula for the height of the rotated, rounded square
              readonly property real trueHeight: (rightDiamondVisual.width - 2 * rightDiamondVisual.radius) * Math.sqrt(2) + (2 * rightDiamondVisual.radius)
              xScale: rightDiamondContainer.height / rightScaler.trueHeight
              yScale: rightDiamondContainer.height / rightScaler.trueHeight
            }
          ]
        }
      }

      NIcon {
        anchors.right: parent.right
        anchors.rightMargin: parent.width * 0.25
        anchors.verticalCenter: parent.verticalCenter
        icon: "chevron-right"
        pointSize: Style.fontSizeS
        color: increaseArea.containsMouse ? Color.mOnHover : Color.mPrimary
      }

      MouseArea {
        id: increaseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.enabled && root.value < root.to
        onPressed: {
          root._repeatDirection = 1;
          changeValue(root._repeatDirection, root.stepSize);
          repeatTimer.start();
        }
        onReleased: stopRepeat()
        onExited: stopRepeat()
      }
    }

    // Center value display with separate prefix, value, and suffix
    Rectangle {
      id: valueContainer
      anchors.left: decreaseButton.right
      anchors.right: increaseButton.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: 4
      height: parent.height
      color: Color.transparent

      RowLayout {
        anchors.centerIn: parent
        spacing: 0

        // Prefix text (non-editable)
        NText {
          text: root.prefix
          family: Settings.data.ui.fontFixed
          pointSize: Style.fontSizeM
          font.weight: Style.fontWeightMedium
          color: Color.mOnSurface
          verticalAlignment: Text.AlignVCenter
          Layout.alignment: Qt.AlignVCenter
          visible: root.prefix !== ""
        }

        // Editable number input
        TextInput {
          id: valueInput
          text: valueInput.focus ? valueInput.text : root.value.toString()
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeM
          font.weight: Style.fontWeightMedium
          color: Color.mOnSurface
          verticalAlignment: Text.AlignVCenter
          Layout.alignment: Qt.AlignVCenter
          selectByMouse: true
          enabled: root.enabled

          // Only allow numeric input within range
          validator: IntValidator {
            bottom: root.from
            top: root.to
          }

          Keys.onReturnPressed: {
            applyValue();
            focus = false;
          }

          Keys.onEscapePressed: {
            text = root.value.toString();
            focus = false;
          }

          onFocusChanged: {
            if (focus) {
              selectAll();
            } else {
              applyValue();
            }
          }

          function applyValue() {
            let newValue = parseInt(text);
            if (!isNaN(newValue)) {
              // Don't manually set text here - let the binding handle it
              newValue = Math.max(root.from, Math.min(root.to, newValue));
              root.value = newValue;
            }
          }
        }

        // Suffix text (non-editable)
        NText {
          text: root.suffix
          family: Settings.data.ui.fontFixed
          pointSize: Style.fontSizeM
          font.weight: Style.fontWeightMedium
          color: Color.mOnSurface
          verticalAlignment: Text.AlignVCenter
          Layout.alignment: Qt.AlignVCenter
          visible: root.suffix !== ""
        }
      }
    }
  }
}
