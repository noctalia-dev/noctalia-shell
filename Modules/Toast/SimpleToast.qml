import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property string message: ""
  property string description: ""
  property string icon: ""
  property string type: "notice"
  property int duration: 3000
  readonly property real initialScale: 0.7

  signal hidden

  width: Math.round(420 * Style.uiScaleRatio + Style.marginM * 1.5 * 2)
  height: Math.round(contentLayout.implicitHeight + Style.marginM * 3 * 2)
  visible: true
  opacity: 0
  scale: initialScale

  // Background rectangle (apply shadows here)
  Rectangle {
    id: background
    anchors.fill: parent
    anchors.margins: Style.marginM * 1.5
    radius: Style.radiusL
    color: Color.mSurface

    // Colored border based on type
    border.width: Math.max(2, Style.borderM)
    border.color: {
      switch (root.type) {
      case "warning":
        return Color.mPrimary
      case "error":
        return Color.mError
      default:
        return Color.mOutline
      }
    }
  }

  NDropShadows {
    anchors.fill: background
    source: background
    autoPaddingEnabled: true
  }

  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
  }

  Behavior on scale {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
  }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.hide()
  }

  Timer {
    id: hideAnimation
    interval: Style.animationFast
    onTriggered: {
      root.visible = false
      root.hidden()
    }
  }

  // Cleanup on destruction
  Component.onDestruction: {
    hideTimer.stop()
    hideAnimation.stop()
  }

  RowLayout {
    id: contentLayout
    anchors.fill: parent
    anchors.topMargin: Style.marginL
    anchors.bottomMargin: Style.marginL
    anchors.leftMargin: Style.marginL * 2
    anchors.rightMargin: Style.marginL * 2
    spacing: Style.marginL

    // Icon
    NIcon {
      icon: if (root.icon !== "") {
              return root.icon
            } else if (type === "warning") {
              return "toast-warning"
            } else if (type === "error") {
              return "toast-error"
            } else {
              return "toast-notice"
            }
      color: {
        switch (type) {
        case "warning":
          return Color.mPrimary
        case "error":
          return Color.mError
        default:
          return Color.mOnSurface
        }
      }
      pointSize: Style.fontSizeXXL * 1.5
      Layout.alignment: Qt.AlignVCenter
    }

    // Label and description
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter

      NText {
        Layout.fillWidth: true
        text: root.message
        color: Color.mOnSurface
        pointSize: Style.fontSizeL
        font.weight: Style.fontWeightBold
        wrapMode: Text.WordWrap
        visible: text.length > 0
      }

      NText {
        Layout.fillWidth: true
        text: root.description
        color: Color.mOnSurface
        pointSize: Style.fontSizeM
        wrapMode: Text.WordWrap
        visible: text.length > 0
      }
    }
  }

  // Click anywhere dismiss the toast
  MouseArea {
    anchors.fill: background
    acceptedButtons: Qt.LeftButton
    onClicked: root.hide()
    cursorShape: Qt.PointingHandCursor
  }

  function show(msg, desc, msgIcon, msgType, msgDuration) {
    // Stop all timers first
    hideTimer.stop()
    hideAnimation.stop()

    message = msg
    description = desc || ""
    icon = msgIcon || ""
    type = msgType || "notice"
    duration = msgDuration || 3000

    visible = true
    opacity = 1
    scale = 1.0

    hideTimer.restart()
  }

  function hide() {
    hideTimer.stop()
    opacity = 0
    scale = initialScale
    hideAnimation.restart()
  }

  function hideImmediately() {
    hideTimer.stop()
    hideAnimation.stop()
    opacity = 0
    scale = initialScale
    root.visible = false
    root.hidden()
  }
}
