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

  property ShellScreen screen
  readonly property var now: Time.date

  preferredWidth: (Settings.data.location.showWeekNumberInCalendar ? 400 : 380) * Style.uiScaleRatio
  preferredHeight: 520 * Style.uiScaleRatio
  panelKeyboardFocus: true

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

  panelContent: ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM

    readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek
    property bool isCurrentMonth: checkIsCurrentMonth()
    readonly property bool weatherReady: Settings.data.location.weatherEnabled && (LocationService.data.weather !== null)

    function checkIsCurrentMonth() {
      return (Time.date.getMonth() === grid.month) && (Time.date.getFullYear() === grid.year)
    }

    Shortcut {
      sequence: "Escape"
      onActivated: {
        if (timerActive) {
          cancelTimer()
        } else {
          cancelTimer()
          root.close()
        }
      }
      context: Qt.WidgetShortcut
      enabled: root.opened
    }

    Connections {
      target: Time
      function onDateChanged() {
        isCurrentMonth = checkIsCurrentMonth()
      }
    }

    // Combined blue banner with date/time and weather summary
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: blueColumn.implicitHeight + Style.marginM * 2
      radius: Style.radiusL
      color: Color.mPrimary

      ColumnLayout {
        id: blueColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.topMargin: Style.marginM
        anchors.leftMargin: Style.marginM
        anchors.bottomMargin: Style.marginM
        anchors.rightMargin: clockItem.width + (Style.marginM * 2)
        spacing: 0

        // Combined layout for weather icon, date, and weather text
        RowLayout {
          Layout.fillWidth: true
          height: 60 * Style.uiScaleRatio
          clip: true
          spacing: Style.marginS

          // Weather icon and temperature
          ColumnLayout {
            visible: Settings.data.location.weatherEnabled && weatherReady
            Layout.alignment: Qt.AlignVCenter
            spacing: Style.marginXXS

            NIcon {
              Layout.alignment: Qt.AlignHCenter
              icon: Settings.data.location.weatherEnabled && weatherReady ? LocationService.weatherSymbolFromCode(LocationService.data.weather.current_weather.weathercode) : ""
              pointSize: Style.fontSizeXXL
              color: Color.mOnPrimary
            }

            NText {
              Layout.alignment: Qt.AlignHCenter
              text: {
                if (!Settings.data.location.weatherEnabled)
                  return ""
                if (!weatherReady)
                  return ""
                var temp = LocationService.data.weather.current_weather.temperature
                var suffix = "C"
                if (Settings.data.location.useFahrenheit) {
                  temp = LocationService.celsiusToFahrenheit(temp)
                  suffix = "F"
                }
                temp = Math.round(temp)
                return `${temp}°${suffix}`
              }
              pointSize: Style.fontSizeM
              font.weight: Style.fontWeightBold
              color: Color.mOnPrimary
            }
          }

          // Today day number - with simple, stable animation
          NText {
            opacity: content.isCurrentMonth ? 1.0 : 0.0
            Layout.preferredWidth: content.isCurrentMonth ? implicitWidth : 0
            elide: Text.ElideNone
            clip: true

            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
            text: Time.date.getDate()
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
            Layout.preferredWidth: 170 * Style.uiScaleRatio
            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
            Layout.bottomMargin: Style.marginXXS
            Layout.topMargin: -Style.marginXXS
            spacing: -Style.marginXS

            RowLayout {
              spacing: 0

              NText {
                text: Qt.locale().monthName(grid.month, Locale.LongFormat).toUpperCase()
                pointSize: Style.fontSizeXL * 1.1
                font.weight: Style.fontWeightBold
                color: Color.mOnPrimary
                Layout.alignment: Qt.AlignBaseline
                elide: Text.ElideRight
              }

              NText {
                text: ` ${grid.year}`
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
                  if (!weatherReady)
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
                text: weatherReady ? ` (${LocationService.data.weather.timezone_abbreviation})` : ""
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
      Item {
        id: clockItem
        anchors.right: parent.right
        anchors.rightMargin: Style.marginM
        anchors.verticalCenter: parent.verticalCenter
        Layout.alignment: Qt.AlignVCenter
        height: Math.round((Style.fontSizeXXXL * 1.9) / 2 * Style.uiScaleRatio) * 2
        width: clockItem.height

        Canvas {
          id: clockCanvas
          visible: Settings.data.location.analogClockInCalendar
          anchors.fill: parent

          property int hours: now.getHours()
          property int minutes: now.getMinutes()
          property int seconds: now.getSeconds()
          property real markAlpha: 0.7
          property color secondHandColor: {
            var defaultColor = Color.mError
            var backgroundL = Color.mPrimary.hslLightness
            var hourMarkL = (Color.mOnPrimary.hslLightness * markAlpha) + (backgroundL * (1.0 - markAlpha))

            var bestWorstContrast = -1
            var bestColor = defaultColor

            var candidates = [Color.mSecondary, Color.mTertiary, Color.mError]

            for (var i = 0; i < candidates.length; i++) {
              var candidateColor = candidates[i]
              var candidateL = candidateColor.hslLightness

              var diffBackground = Math.abs(backgroundL - candidateL)
              var diffHourMark = Math.abs(hourMarkL - candidateL)

              var currentWorstContrast = Math.min(diffBackground, diffHourMark)

              if (currentWorstContrast > bestWorstContrast) {
                bestWorstContrast = currentWorstContrast
                bestColor = candidateColor
              }
            }

            return bestColor
          }

          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.translate(width / 2, height / 2)
            var radius = Math.min(width, height) / 2

            // Hour marks
            ctx.strokeStyle = Qt.alpha(Color.mOnPrimary, markAlpha)
            ctx.lineWidth = 2 * Style.uiScaleRatio
            var scaleFactor = 0.7

            for (var i = 0; i < 12; i++) {
              var scaleFactor = 0.8
              if (i % 3 === 0) {
                scaleFactor = 0.65
              }
              ctx.save()
              ctx.rotate(i * Math.PI / 6)
              ctx.beginPath()
              ctx.moveTo(0, -radius * scaleFactor)
              ctx.lineTo(0, -radius)
              ctx.stroke()
              ctx.restore()
            }

            // Hour hand
            ctx.save()
            var hourAngle = (hours % 12 + minutes / 60) * Math.PI / 6
            ctx.rotate(hourAngle)
            ctx.strokeStyle = Color.mOnPrimary
            ctx.lineWidth = 3 * Style.uiScaleRatio
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.moveTo(0, 0)
            ctx.lineTo(0, -radius * 0.6)
            ctx.stroke()
            ctx.restore()

            // Minute hand
            ctx.save()
            var minuteAngle = (minutes + seconds / 60) * Math.PI / 30
            ctx.rotate(minuteAngle)
            ctx.strokeStyle = Color.mOnPrimary
            ctx.lineWidth = 2 * Style.uiScaleRatio
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.moveTo(0, 0)
            ctx.lineTo(0, -radius * 0.9)
            ctx.stroke()
            ctx.restore()

            // Second hand
            ctx.save()
            var secondAngle = seconds * Math.PI / 30
            ctx.rotate(secondAngle)
            ctx.strokeStyle = secondHandColor
            ctx.lineWidth = 1.6 * Style.uiScaleRatio
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.moveTo(0, 0)
            ctx.lineTo(0, -radius)
            ctx.stroke()
            ctx.restore()

            // Center dot
            ctx.beginPath()
            ctx.arc(0, 0, 3 * Style.uiScaleRatio, 0, 2 * Math.PI)
            ctx.fillStyle = Color.mOnPrimary
            ctx.fill()
          }

          Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: {
              clockCanvas.hours = now.getHours()
              clockCanvas.minutes = now.getMinutes()
              clockCanvas.seconds = now.getSeconds()
              clockCanvas.requestPaint()
            }
          }

          Component.onCompleted: requestPaint()
        }

        // Digital clock's seconds circular progress
        Canvas {
          id: secondsProgress
          visible: !Settings.data.location.analogClockInCalendar
          anchors.fill: parent
          property real progress: now.getSeconds() / 60
          onProgressChanged: requestPaint()
          Connections {
            target: Time
            function onDateChanged() {
              const total = now.getSeconds() * 1000 + now.getMilliseconds()
              secondsProgress.progress = total / 60000
            }
          }
          onPaint: {
            var ctx = getContext("2d")
            var centerX = width / 2
            var centerY = height / 2
            var radius = Math.min(width, height) / 2 - 3
            ctx.reset()

            // Background circle
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI)
            ctx.lineWidth = 2.5
            ctx.strokeStyle = Qt.alpha(Color.mOnPrimary, 0.15)
            ctx.stroke()

            // Progress arc
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + progress * 2 * Math.PI)
            ctx.lineWidth = 2.5
            ctx.strokeStyle = Color.mOnPrimary
            ctx.lineCap = "round"
            ctx.stroke()
          }
        }

        // Digital clock
        ColumnLayout {
          visible: !Settings.data.location.analogClockInCalendar
          anchors.centerIn: parent
          spacing: -Style.marginXXS

          NText {
            text: {
              var t = Settings.data.location.use12hourFormat ? Qt.locale().toString(now, "hh AP") : Qt.locale().toString(now, "HH")
              return t.split(" ")[0]
            }

            pointSize: Style.fontSizeXS
            font.weight: Style.fontWeightBold
            color: Color.mOnPrimary
            family: Settings.data.ui.fontFixed
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: Qt.formatTime(now, "mm")
            pointSize: Style.fontSizeXXS
            font.weight: Style.fontWeightBold
            color: Color.mOnPrimary
            family: Settings.data.ui.fontFixed
            Layout.alignment: Qt.AlignHCenter
          }
        }
      }
    }

    RowLayout {
      visible: weatherReady
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      spacing: Style.marginL
      Repeater {
        model: weatherReady ? Math.min(6, LocationService.data.weather.daily.time.length) : 0
        delegate: ColumnLayout {
          Layout.preferredWidth: 0
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.marginS
          NText {
            text: {
              var weatherDate = new Date(LocationService.data.weather.daily.time[index].replace(/-/g, "/"))
              return Qt.locale().toString(weatherDate, "ddd")
            }
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeM
            font.weight: Style.fontWeightMedium
            Layout.alignment: Qt.AlignHCenter
          }
          NIcon {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.daily.weathercode[index])
            pointSize: Style.fontSizeXXL * 1.5
            color: Color.mPrimary
          }
          NText {
            Layout.alignment: Qt.AlignHCenter
            text: {
              var max = LocationService.data.weather.daily.temperature_2m_max[index]
              var min = LocationService.data.weather.daily.temperature_2m_min[index]
              if (Settings.data.location.useFahrenheit) {
                max = LocationService.celsiusToFahrenheit(max)
                min = LocationService.celsiusToFahrenheit(min)
              }
              max = Math.round(max)
              min = Math.round(min)
              return `${max}°/${min}°`
            }
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
            font.weight: Style.fontWeightMedium
          }
        }
      }
    }
    RowLayout {
      visible: Settings.data.location.weatherEnabled && !weatherReady
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      NBusyIndicator {}
    }
    Item {}
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
          grid.month = Time.date.getMonth()
          grid.year = Time.date.getFullYear()
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
            Layout.preferredHeight: Style.baseWidgetSize * 0.6
            NText {
              anchors.centerIn: parent
              text: {
                let dayIndex = (content.firstDayOfWeek + index) % 7
                const dayNames = ["S", "M", "T", "W", "T", "F", "S"]
                return dayNames[dayIndex]
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
      Layout.fillHeight: true
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
        Layout.fillHeight: true
        spacing: 0
        Repeater {
          model: 6
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            NText {
              anchors.centerIn: parent
              color: Color.mOutline
              pointSize: Style.fontSizeXXS
              font.weight: Style.fontWeightMedium
              text: {
                let firstOfMonth = new Date(grid.year, grid.month, 1)
                let firstDayOfWeek = content.firstDayOfWeek
                let firstOfMonthDayOfWeek = firstOfMonth.getDay()
                let daysBeforeFirst = (firstOfMonthDayOfWeek - firstDayOfWeek + 7) % 7
                if (daysBeforeFirst === 0) {
                  daysBeforeFirst = 7
                }
                let gridStartDate = new Date(grid.year, grid.month, 1 - daysBeforeFirst)
                let rowStartDate = new Date(gridStartDate)
                rowStartDate.setDate(gridStartDate.getDate() + (index * 7))
                let thursday = new Date(rowStartDate)
                if (firstDayOfWeek === 0) {
                  thursday.setDate(rowStartDate.getDate() + 4)
                } else if (firstDayOfWeek === 1) {
                  thursday.setDate(rowStartDate.getDate() + 3)
                } else {
                  let daysToThursday = (4 - firstDayOfWeek + 7) % 7
                  thursday.setDate(rowStartDate.getDate() + daysToThursday)
                }
                return `${root.getISOWeekNumber(thursday)}`
              }
            }
          }
        }
      }
      MonthGrid {
        id: grid
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.marginXXS
        month: Time.date.getMonth()
        year: Time.date.getFullYear()
        locale: Qt.locale()
        delegate: Item {
          Rectangle {
            width: Style.baseWidgetSize * 0.9
            height: Style.baseWidgetSize * 0.9
            anchors.centerIn: parent
            radius: Style.radiusM
            color: model.today ? Color.mSecondary : Color.transparent
            NText {
              anchors.centerIn: parent
              text: model.day
              color: {
                if (model.today)
                  return Color.mOnSecondary
                if (model.month === grid.month)
                  return Color.mOnSurface
                return Color.mOnSurfaceVariant
              }
              opacity: model.month === grid.month ? 1.0 : 0.4
              pointSize: Style.fontSizeM
              font.weight: model.today ? Style.fontWeightBold : Style.fontWeightMedium
            }

            // Event indicator dots
            Row {
              visible: Settings.data.location.showCalendarEvents && parent.parent.parent.parent.parent.hasEventsOnDate(model.year, model.month, model.day)
              spacing: 2
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.marginXS

              readonly property int currentYear: model.year
              readonly property int currentMonth: model.month
              readonly property int currentDay: model.day
              readonly property bool isToday: model.today

              Repeater {
                model: parent.parent.parent.parent.parent.parent.getEventsForDate(parent.currentYear, parent.currentMonth, parent.currentDay)

                Rectangle {
                  width: 4
                  height: width
                  radius: width / 2
                  color: parent.parent.parent.parent.parent.parent.getEventColor(modelData, model.today)
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              enabled: Settings.data.location.showCalendarEvents

              onEntered: {
                const events = parent.parent.parent.parent.parent.getEventsForDate(model.year, model.month, model.day)
                if (events.length > 0) {
                  const summaries = events.map(e => e.summary).join('\n')
                  TooltipService.show(Screen, parent, summaries)
                  TooltipService.updateText(summaries)
                }
              }

              onClicked: {
                const dateWithSlashes = `${model.month.toString().padStart(2, '0')}/${model.day.toString().padStart(2, '0')}/${model.year.toString().substring(2)}`
                Quickshell.execDetached(["gnome-calendar", "--date", dateWithSlashes])
                PanelService.getPanel("calendarPanel").toggle(null)
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
