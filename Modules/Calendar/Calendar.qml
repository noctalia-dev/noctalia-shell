import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NLoader {
  id: root

  content: Component {
    NPanel {
      id: calendarPanel

      // Override hide function to animate first
      function hide() {
        // Start hide animation
        calendarRect.scaleValue = 0.8
        calendarRect.opacityValue = 0.0

        // Hide after animation completes
        hideTimer.start()
      }

      // Connect to NPanel's dismissed signal to handle external close events
      Connections {
        target: calendarPanel
        function onDismissed() {
          // Start hide animation
          calendarRect.scaleValue = 0.8
          calendarRect.opacityValue = 0.0

          // Hide after animation completes
          hideTimer.start()
        }
      }

      // Also handle visibility changes from external sources
      onVisibleChanged: {
        if (!visible && calendarRect.opacityValue > 0) {
          // Start hide animation
          calendarRect.scaleValue = 0.8
          calendarRect.opacityValue = 0.0

          // Hide after animation completes
          hideTimer.start()
        }
      }

      // Timer to hide panel after animation
      Timer {
        id: hideTimer
        interval: Style.animationSlow
        repeat: false
        onTriggered: {
          calendarPanel.visible = false
          calendarPanel.dismissed()
        }
      }

      Rectangle {
        id: calendarRect
        color: Color.mSurface
        radius: Style.radiusMedium * scaling
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderMedium * scaling)
        width: 340 * scaling
        height: 320 * scaling // Reduced height to eliminate bottom space
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.marginTiny * scaling
        anchors.rightMargin: Style.marginTiny * scaling

        // Animation properties
        property real scaleValue: 0.8
        property real opacityValue: 0.0

        scale: scaleValue
        opacity: opacityValue

        // Animate in when component is completed
        Component.onCompleted: {
          scaleValue = 1.0
          opacityValue = 1.0
        }

        // Prevent closing when clicking in the panel bg
        MouseArea {
          anchors.fill: parent
        }

        // Animation behaviors
        Behavior on scale {
          NumberAnimation {
            duration: Style.animationSlow
            easing.type: Easing.OutExpo
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutQuad
          }
        }

        // Main Column
        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginMedium * scaling
          spacing: Style.marginTiny * scaling

          // Header: Month/Year with navigation
          RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Style.marginMedium * scaling
            Layout.rightMargin: Style.marginMedium * scaling
            spacing: Style.marginSmall * scaling

            NIconButton {
              icon: "chevron_left"
              tooltipText: "Previous Month"
              onClicked: {
                let newDate = new Date(grid.year, grid.month - 1, 1)
                grid.year = newDate.getFullYear()
                grid.month = newDate.getMonth()
              }
            }

            NText {
              text: grid.title
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              font.pointSize: Style.fontSizeMedium * scaling
              font.weight: Style.fontWeightBold
              color: Color.mPrimary
            }

            NIconButton {
              icon: "chevron_right"
              tooltipText: "Next Month"
              onClicked: {
                let newDate = new Date(grid.year, grid.month + 1, 1)
                grid.year = newDate.getFullYear()
                grid.month = newDate.getMonth()
              }
            }
          }

          // Divider between header and weekdays
          NDivider {
            Layout.fillWidth: true
            Layout.topMargin: Style.marginSmall * scaling
            Layout.bottomMargin: Style.marginMedium * scaling
          }

          // Columns label (respects locale's first day of week)
          RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Style.marginSmall * scaling // Align with grid
            Layout.rightMargin: Style.marginSmall * scaling
            spacing: 0

            Repeater {
              model: 7

              NText {
                text: {
                  // Use the locale's first day of week setting
                  let firstDay = Qt.locale().firstDayOfWeek
                  let dayIndex = (firstDay + index) % 7
                  return Qt.locale().dayName(dayIndex, Locale.ShortFormat)
                }
                color: Color.mSecondary
                font.pointSize: Style.fontSizeMedium * scaling
                font.weight: Style.fontWeightBold
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                Layout.preferredWidth: Style.baseWidgetSize * scaling
              }
            }
          }

          // Grids: days
          MonthGrid {
            id: grid

            Layout.fillWidth: true
            Layout.fillHeight: true // Take remaining space
            Layout.leftMargin: Style.marginSmall * scaling
            Layout.rightMargin: Style.marginSmall * scaling
            spacing: 0
            month: Time.date.getMonth()
            year: Time.date.getFullYear()
            locale: Qt.locale() // Use system locale

            // Optionally, update when the panel becomes visible
            Connections {
              target: calendarPanel
              function onVisibleChanged() {
                if (calendarPanel.visible) {
                  grid.month = Time.date.getMonth()
                  grid.year = Time.date.getFullYear()
                }
              }
            }

            delegate: Rectangle {
              width: (Style.baseWidgetSize * scaling)
              height: (Style.baseWidgetSize * scaling)
              radius: Style.radiusSmall * scaling
              color: model.today ? Color.mPrimary : Color.transparent

              NText {
                anchors.centerIn: parent
                text: model.day
                color: model.today ? Color.mOnPrimary : Color.mOnSurface
                opacity: model.month === grid.month ? Style.opacityHeavy : Style.opacityLight
                font.pointSize: (Style.fontSizeMedium * scaling)
                font.weight: model.today ? Style.fontWeightBold : Style.fontWeightRegular
              }

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
            }
          }
        }
      }
    }
  }
}
