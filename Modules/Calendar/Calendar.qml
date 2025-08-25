import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  panelWidth: 340 * scaling
  panelHeight: 320 * scaling
  panelAnchorRight: true

  // Main Column
  panelContent: ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginM * scaling
    spacing: Style.marginXS * scaling

    // Header: Month/Year with navigation
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginM * scaling
      Layout.rightMargin: Style.marginM * scaling
      spacing: Style.marginS * scaling

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
        font.pointSize: Style.fontSizeM * scaling
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
      Layout.topMargin: Style.marginS * scaling
      Layout.bottomMargin: Style.marginM * scaling
    }

    // Columns label (respects locale's first day of week)
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginS * scaling // Align with grid
      Layout.rightMargin: Style.marginS * scaling
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
          font.pointSize: Style.fontSizeM * scaling
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
      Layout.leftMargin: Style.marginS * scaling
      Layout.rightMargin: Style.marginS * scaling
      spacing: 0
      month: Time.date.getMonth()
      year: Time.date.getFullYear()
      locale: Qt.locale() // Use system locale

      delegate: Rectangle {
        width: (Style.baseWidgetSize * scaling)
        height: (Style.baseWidgetSize * scaling)
        radius: Style.radiusS * scaling
        color: model.today ? Color.mPrimary : Color.transparent

        NText {
          anchors.centerIn: parent
          text: model.day
          color: model.today ? Color.mOnPrimary : Color.mOnSurface
          opacity: model.month === grid.month ? Style.opacityHeavy : Style.opacityLight
          font.pointSize: (Style.fontSizeM * scaling)
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
