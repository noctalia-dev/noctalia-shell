import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.ControlCenter.Cards
import qs.Services
import qs.Widgets

NPanel {
  id: root

  property ShellScreen screen
  readonly property var now: Time.now

  preferredWidth: 500 * Style.uiScaleRatio
  preferredHeight: 700 * Style.uiScaleRatio

  // Helper function to calculate ISO week number
  function getISOWeekNumber(date) {
    const target = new Date(date.valueOf())
    const dayNr = (date.getDay() + 6) % 7
    target.setDate(target.getDate() - dayNr + 3)
    const firstThursday = new Date(target.getFullYear(), 0, 4)
    const diff = target - firstThursday
    const oneWeek = 1000 * 60 * 60 * 24 * 7
    const weekNumber = 1 + Math.round(diff / oneWeek)
    return weekNumber
  }

  panelContent: Item {
    anchors.fill: parent

    // Dynamic sizing properties that NPanel will bind to
    property real contentPreferredWidth: (Settings.data.location.showWeekNumberInCalendar ? 400 : 380) * Style.uiScaleRatio

    property real calendarGridHeight: {
      // Calculate number of weeks in the calendar grid
      const numWeeks = grid.daysModel ? Math.ceil(grid.daysModel.length / 7) : 5

      // Calendar grid height (dynamic based on number of weeks)
      const rowHeight = Style.baseWidgetSize * 0.9 + Style.marginXXS

      return numWeeks * rowHeight
    }

    // Use implicitHeight from content + margins to avoid binding loops
    property real contentPreferredHeight: content.implicitHeight + Style.marginL * 2

    ColumnLayout {
      id: content
      anchors.fill: parent
      anchors.margins: Style.marginL
      width: parent.contentPreferredWidth - Style.marginL * 2
      spacing: Style.marginM

      readonly property int firstDayOfWeek: Settings.data.location.firstDayOfWeek === -1 ? I18n.locale.firstDayOfWeek : Settings.data.location.firstDayOfWeek
      property bool isCurrentMonth: true
      readonly property bool weatherReady: Settings.data.location.weatherEnabled && (LocationService.data.weather !== null)

      function checkIsCurrentMonth() {
        return (now.getMonth() === grid.month) && (now.getFullYear() === grid.year)
      }

      Component.onCompleted: {
        isCurrentMonth = checkIsCurrentMonth()
      }

      Connections {
        target: Time
        function onNowChanged() {
          content.isCurrentMonth = content.checkIsCurrentMonth()
        }
      }

      Connections {
        target: I18n
        function onLanguageChanged() {
          // Force update of day names when language changes
          grid.month = grid.month
        }
      }

      // Banner with date/time/clock
      Rectangle {
        id: banner
        Layout.fillWidth: true
        Layout.preferredHeight: capsuleColumn.implicitHeight + Style.marginM * 2
        radius: Style.radiusL
        color: Color.mPrimary

        ColumnLayout {
          id: capsuleColumn
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.bottom: parent.bottom

          anchors.topMargin: Style.marginM
          anchors.bottomMargin: Style.marginM
          anchors.rightMargin: clockLoader.width + (Style.marginXL * 2)
          anchors.leftMargin: Style.marginXL

          spacing: 0

          // Combined layout for date, month year, locatio and time-zone
          RowLayout {
            Layout.fillWidth: true
            height: 60 * Style.uiScaleRatio
            clip: true
            spacing: Style.marginS

            // Today day number - with simple, stable animation
            NText {
              opacity: content.isCurrentMonth ? 1.0 : 0.0
              Layout.preferredWidth: content.isCurrentMonth ? implicitWidth : 0
              elide: Text.ElideNone
              clip: true

              Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
              text: now.getDate()
              pointSize: Style.fontSizeXXXL * 1.5
              font.weight: Style.fontWeightBold
              color: Color.mOnPrimary

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
              Behavior on Layout.preferredWidth {
                NumberAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.InOutQuad
                }
              }
            }

            // Month, year, location
            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
              Layout.bottomMargin: Style.marginXXS
              Layout.topMargin: -Style.marginXXS
              spacing: -Style.marginXS

              RowLayout {
                spacing: Style.marginS

                NText {
                  text: I18n.locale.monthName(grid.month, Locale.LongFormat).toUpperCase()
                  pointSize: Style.fontSizeXL * 1.1
                  font.weight: Style.fontWeightBold
                  color: Color.mOnPrimary
                  Layout.alignment: Qt.AlignBaseline
                  elide: Text.ElideRight
                }

                NText {
                  text: `${grid.year}`
                  pointSize: Style.fontSizeM
                  font.weight: Style.fontWeightBold
                  color: Qt.alpha(Color.mOnPrimary, 0.7)
                  Layout.alignment: Qt.AlignBaseline
                }
              }

              RowLayout {
                spacing: 0

                NText {
                  text: {
                    if (!Settings.data.location.weatherEnabled)
                      return ""
                    if (!content.weatherReady)
                      return I18n.tr("calendar.weather.loading")
                    const chunks = Settings.data.location.name.split(",")
                    return chunks[0]
                  }
                  pointSize: Style.fontSizeM
                  font.weight: Style.fontWeightMedium
                  color: Color.mOnPrimary
                  Layout.maximumWidth: 150
                  elide: Text.ElideRight
                }

                NText {
                  text: content.weatherReady ? ` (${LocationService.data.weather.timezone_abbreviation})` : ""
                  pointSize: Style.fontSizeXS
                  font.weight: Style.fontWeightMedium
                  color: Qt.alpha(Color.mOnPrimary, 0.7)
                }
              }
            }

            // Spacer to push content left
            Item {
              Layout.fillWidth: true
            }
          }
        }

        // Analog clock
        NClock {
          id: clockLoader
          anchors.right: parent.right
          anchors.rightMargin: Style.marginXL
          anchors.verticalCenter: parent.verticalCenter
          clockStyle: Settings.data.location.analogClockInCalendar ? "analog" : "digital"
          progressColor: Color.mOnPrimary
          Layout.alignment: Qt.AlignVCenter
          now: root.now
        }
      }

      // Calendar itself
      NBox {
        id: calendar
        Layout.fillWidth: true
        Layout.preferredHeight: {
          const navigationHeight = Style.baseWidgetSize // Navigation buttons row
          const dayNamesHeight = Style.baseWidgetSize * 0.6 // Day names header row
          const innerMargins = Style.marginM * 2 // Top and bottom margins inside NBox
          const innerSpacing = Style.marginS * 2 // Spacing between nav, dayNames, and grid (2 gaps)
          return navigationHeight + dayNamesHeight + calendarGridHeight + innerMargins + innerSpacing
        }

        Behavior on Layout.preferredWidth {
          NumberAnimation {
            duration: Style.animationFast
            easing.type: Easing.InOutQuad
          }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NDivider {
              Layout.fillWidth: true
            }

            NIconButton {
              icon: "chevron-left"
              onClicked: {
                let newDate = new Date(grid.year, grid.month - 1, 1)
                grid.year = newDate.getFullYear()
                grid.month = newDate.getMonth()
                content.isCurrentMonth = content.checkIsCurrentMonth()
                const now = new Date()
                const monthStart = new Date(grid.year, grid.month, 1)
                const monthEnd = new Date(grid.year, grid.month + 1, 0)

                const daysBehind = Math.max(0, Math.ceil((now - monthStart) / (24 * 60 * 60 * 1000)))
                const daysAhead = Math.max(0, Math.ceil((monthEnd - now) / (24 * 60 * 60 * 1000)))

                CalendarService.loadEvents(daysAhead + 30, daysBehind + 30)
              }
            }

            NIconButton {
              icon: "calendar"
              onClicked: {
                grid.month = now.getMonth()
                grid.year = now.getFullYear()
                content.isCurrentMonth = true
                CalendarService.loadEvents()
              }
            }

            NIconButton {
              icon: "chevron-right"
              onClicked: {
                let newDate = new Date(grid.year, grid.month + 1, 1)
                grid.year = newDate.getFullYear()
                grid.month = newDate.getMonth()
                content.isCurrentMonth = content.checkIsCurrentMonth()
                const now = new Date()
                const monthStart = new Date(grid.year, grid.month, 1)
                const monthEnd = new Date(grid.year, grid.month + 1, 0)

                const daysBehind = Math.max(0, Math.ceil((now - monthStart) / (24 * 60 * 60 * 1000)))
                const daysAhead = Math.max(0, Math.ceil((monthEnd - now) / (24 * 60 * 60 * 1000)))

                CalendarService.loadEvents(daysAhead + 30, daysBehind + 30)
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Item {
              visible: Settings.data.location.showWeekNumberInCalendar
              Layout.preferredWidth: visible ? Style.baseWidgetSize * 0.7 : 0
            }

            GridLayout {
              Layout.fillWidth: true
              columns: 7
              rows: 1
              columnSpacing: 0
              rowSpacing: 0
              Repeater {
                model: 7
                Item {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.fontSizeS * 2
                  NText {
                    anchors.centerIn: parent
                    text: {
                      let dayIndex = (content.firstDayOfWeek + index) % 7
                      const dayName = I18n.locale.dayName(dayIndex, Locale.ShortFormat)
                      return dayName.substring(0, 2).toUpperCase()
                    }
                    color: Color.mPrimary
                    pointSize: Style.fontSizeS
                    font.weight: Style.fontWeightBold
                    horizontalAlignment: Text.AlignHCenter
                  }
                }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 0

            // Helper function to check if a date has events
            function hasEventsOnDate(year, month, day) {
              if (!CalendarService.available || CalendarService.events.length === 0)
                return false

              const targetDate = new Date(year, month, day)
              const targetStart = new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate()).getTime() / 1000
              const targetEnd = targetStart + 86400 // +24 hours

              return CalendarService.events.some(event => {
                                                   // Check if event starts or overlaps with this day
                                                   return (event.start >= targetStart && event.start < targetEnd) || (event.end > targetStart && event.end <= targetEnd) || (event.start < targetStart && event.end > targetEnd)
                                                 })
            }

            // Helper function to get events for a specific date
            function getEventsForDate(year, month, day) {
              if (!CalendarService.available || CalendarService.events.length === 0)
                return []

              const targetDate = new Date(year, month, day)
              const targetStart = Math.floor(new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate()).getTime() / 1000)
              const targetEnd = targetStart + 86400 // +24 hours

              return CalendarService.events.filter(event => {
                                                     return (event.start >= targetStart && event.start < targetEnd) || (event.end > targetStart && event.end <= targetEnd) || (event.start < targetStart && event.end > targetEnd)
                                                   })
            }

            // Helper function to check if an event is all-day
            function isAllDayEvent(event) {
              const duration = event.end - event.start
              const startDate = new Date(event.start * 1000)
              const isAtMidnight = startDate.getHours() === 0 && startDate.getMinutes() === 0
              return duration === 86400 && isAtMidnight
            }

            // Helper function to check if an event is multi-day
            function isMultiDayEvent(event) {
              if (isAllDayEvent(event)) {
                return false
              }

              const startDate = new Date(event.start * 1000)
              const endDate = new Date(event.end * 1000)

              const startDateOnly = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate())
              const endDateOnly = new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate())

              return startDateOnly.getTime() !== endDateOnly.getTime()
            }

            // Helper function to get color for a specific event
            function getEventColor(event, isToday) {
              if (isMultiDayEvent(event)) {
                return isToday ? Color.mOnSecondary : Color.mTertiary
              } else if (isAllDayEvent(event)) {
                return isToday ? Color.mOnSecondary : Color.mSecondary
              } else {
                return isToday ? Color.mOnSecondary : Color.mPrimary
              }
            }

            // Column of week numbers
            ColumnLayout {
              visible: Settings.data.location.showWeekNumberInCalendar
              Layout.preferredWidth: visible ? Style.baseWidgetSize * 0.7 : 0
              Layout.preferredHeight: {
                const numWeeks = weekNumbers ? weekNumbers.length : 5
                const rowHeight = Style.baseWidgetSize * 0.9 + Style.marginXXS
                return numWeeks * rowHeight
              }
              spacing: Style.marginXXS

              Behavior on Layout.preferredHeight {
                NumberAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.InOutQuad
                }
              }

              property var weekNumbers: {
                if (!grid.daysModel || grid.daysModel.length === 0)
                  return []

                const weeks = []
                const numWeeks = Math.ceil(grid.daysModel.length / 7)

                for (var i = 0; i < numWeeks; i++) {
                  const dayIndex = i * 7
                  if (dayIndex < grid.daysModel.length) {
                    const weekDay = grid.daysModel[dayIndex]
                    const date = new Date(weekDay.year, weekDay.month, weekDay.day)

                    // Get Thursday of this week for ISO week calculation
                    const firstDayOfWeek = content.firstDayOfWeek
                    let thursday = new Date(date)
                    if (firstDayOfWeek === 0) {
                      thursday.setDate(date.getDate() + 4)
                    } else if (firstDayOfWeek === 1) {
                      thursday.setDate(date.getDate() + 3)
                    } else {
                      let daysToThursday = (4 - firstDayOfWeek + 7) % 7
                      thursday.setDate(date.getDate() + daysToThursday)
                    }

                    weeks.push(root.getISOWeekNumber(thursday))
                  }
                }
                return weeks
              }

              Repeater {
                model: parent.weekNumbers
                Item {
                  Layout.preferredWidth: Style.baseWidgetSize * 0.7
                  Layout.preferredHeight: Style.baseWidgetSize * 0.9
                  NText {
                    anchors.centerIn: parent
                    color: Qt.alpha(Color.mPrimary, 0.7)
                    pointSize: Style.fontSizeXXS
                    font.weight: Style.fontWeightMedium
                    text: modelData
                  }
                }
              }
            }

            GridLayout {
              id: grid
              Layout.fillWidth: true
              Layout.preferredHeight: {
                const numWeeks = daysModel ? Math.ceil(daysModel.length / 7) : 5
                const rowHeight = Style.baseWidgetSize * 0.9 + Style.marginXXS
                return numWeeks * rowHeight
              }
              columns: 7
              columnSpacing: Style.marginXXS
              rowSpacing: Style.marginXXS

              property int month: now.getMonth()
              property int year: now.getFullYear()

              Behavior on Layout.preferredHeight {
                NumberAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.InOutQuad
                }
              }

              // Calculate days to display
              property var daysModel: {
                const firstOfMonth = new Date(year, month, 1)
                const lastOfMonth = new Date(year, month + 1, 0)
                const daysInMonth = lastOfMonth.getDate()

                // Get first day of week (0 = Sunday, 1 = Monday, etc.)
                const firstDayOfWeek = content.firstDayOfWeek
                const firstOfMonthDayOfWeek = firstOfMonth.getDay()

                // Calculate days before first of month
                let daysBefore = (firstOfMonthDayOfWeek - firstDayOfWeek + 7) % 7

                // Calculate days after last of month to complete the week
                const lastOfMonthDayOfWeek = lastOfMonth.getDay()
                const daysAfter = (firstDayOfWeek - lastOfMonthDayOfWeek - 1 + 7) % 7

                // Build array of day objects
                const days = []
                const today = new Date()

                // Previous month days
                const prevMonth = new Date(year, month, 0)
                const prevMonthDays = prevMonth.getDate()
                for (var i = daysBefore - 1; i >= 0; i--) {
                  const day = prevMonthDays - i
                  const date = new Date(year, month - 1, day)
                  days.push({
                              "day": day,
                              "month": month - 1,
                              "year": month === 0 ? year - 1 : year,
                              "today": false,
                              "currentMonth": false
                            })
                }

                // Current month days
                for (var day = 1; day <= daysInMonth; day++) {
                  const date = new Date(year, month, day)
                  const isToday = date.getFullYear() === today.getFullYear() && date.getMonth() === today.getMonth() && date.getDate() === today.getDate()
                  days.push({
                              "day": day,
                              "month": month,
                              "year": year,
                              "today": isToday,
                              "currentMonth": true
                            })
                }

                // Next month days (only if needed to complete the week)
                for (var i = 1; i <= daysAfter; i++) {
                  days.push({
                              "day": i,
                              "month": month + 1,
                              "year": month === 11 ? year + 1 : year,
                              "today": false,
                              "currentMonth": false
                            })
                }

                return days
              }

              Repeater {
                model: grid.daysModel

                Item {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.baseWidgetSize * 0.9

                  Rectangle {
                    width: Style.baseWidgetSize * 0.9
                    height: Style.baseWidgetSize * 0.9
                    anchors.centerIn: parent
                    radius: Style.radiusM
                    color: modelData.today ? Color.mSecondary : Color.transparent

                    NText {
                      anchors.centerIn: parent
                      text: modelData.day
                      color: {
                        if (modelData.today)
                          return Color.mOnSecondary
                        if (modelData.currentMonth)
                          return Color.mOnSurface
                        return Color.mOnSurfaceVariant
                      }
                      opacity: modelData.currentMonth ? 1.0 : 0.4
                      pointSize: Style.fontSizeM
                      font.weight: modelData.today ? Style.fontWeightBold : Style.fontWeightMedium
                    }

                    // Event indicator dots
                    Row {
                      visible: Settings.data.location.showCalendarEvents && parent.parent.parent.parent.hasEventsOnDate(modelData.year, modelData.month, modelData.day)
                      spacing: 2
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: Style.marginXS

                      Repeater {
                        model: parent.parent.parent.parent.parent.getEventsForDate(modelData.year, modelData.month, modelData.day)

                        Rectangle {
                          width: 4
                          height: width
                          radius: width / 2
                          color: parent.parent.parent.parent.parent.getEventColor(modelData, modelData.today)
                        }
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      enabled: Settings.data.location.showCalendarEvents

                      onEntered: {
                        const events = parent.parent.parent.parent.getEventsForDate(modelData.year, modelData.month, modelData.day)
                        if (events.length > 0) {
                          const summaries = events.map(e => e.summary).join('\n')
                          TooltipService.show(Screen, parent, summaries)
                          TooltipService.updateText(summaries)
                        }
                      }

                      onClicked: {
                        const dateWithSlashes = `${(modelData.month + 1).toString().padStart(2, '0')}/${modelData.day.toString().padStart(2, '0')}/${modelData.year.toString().substring(2)}`
                        if (ProgramCheckerService.gnomeCalendarAvailable) {
                          Quickshell.execDetached(["gnome-calendar", "--date", dateWithSlashes])
                          root.close()
                        }
                      }

                      onExited: {
                        TooltipService.hide()
                      }
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

      Loader {
        id: weatherLoader
        active: Settings.data.location.weatherEnabled && Settings.data.location.showCalendarWeather
        Layout.fillWidth: true

        sourceComponent: WeatherCard {
          Layout.fillWidth: true
          forecastDays: 6
          showLocation: false
        }
      }
    }
  }
}
