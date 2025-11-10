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

  signal entered
  signal exited

  Layout.fillWidth: true

  NLabel {
    label: root.label
    description: root.description
  }

  // Main spinbox container
  Rectangle {
    id: spinBoxContainer
    implicitWidth: 120
    implicitHeight: (root.baseSize - 4)
    radius: height * 0.5
    color: Color.mSurfaceVariant
    border.color: (root.hovering || decreaseArea.containsMouse || increaseArea.containsMouse) ? Color.mHover : Color.mOutline
    border.width: 1

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
        root.hovering = true
        root.entered()
      }
      onExited: {
        root.hovering = false
        root.exited()
      }
      onWheel: wheel => {
                 if (wheel.angleDelta.y > 0 && root.value < root.to) {
                   let newValue = Math.min(root.to, root.value + root.stepSize)
                   root.value = newValue
                 } else if (wheel.angleDelta.y < 0 && root.value > root.from) {
                   let newValue = Math.max(root.from, root.value - root.stepSize)
                   root.value = newValue
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
      opacity: root.enabled && root.value > root.from ? 1.0 : 0.3

      Item {
        id: leftSemicircle
        width: Math.round(parent.height / 2)
        height: parent.height
        clip: true
        anchors.left: parent.left
        Rectangle {
          width: Math.round(parent.height)
          height: parent.height
          radius: width / 2
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
        onClicked: {
          let newValue = Math.max(root.from, root.value - root.stepSize)
          root.value = newValue
        }
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
      opacity: root.enabled && root.value < root.to ? 1.0 : 0.3

      Item {
        id: rightSemicircle
        width: Math.round(parent.height / 2)
        height: parent.height
        clip: true
        anchors.right: parent.right
        Rectangle {
          width: Math.round(parent.height)
          height: parent.height
          radius: width / 2
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
        onClicked: {
          let newValue = Math.min(root.to, root.value + root.stepSize)
          root.value = newValue
        }
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
            applyValue()
            focus = false
          }

          Keys.onEscapePressed: {
            text = root.value.toString()
            focus = false
          }

          onFocusChanged: {
            if (focus) {
              selectAll()
            } else {
              applyValue()
            }
          }

          function applyValue() {
            let newValue = parseInt(text)
            if (!isNaN(newValue)) {
              // Don't manually set text here - let the binding handle it
              newValue = Math.max(root.from, Math.min(root.to, newValue))
              root.value = newValue
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
