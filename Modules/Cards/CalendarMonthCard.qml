import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Location
import qs.Services.System
import qs.Services.UI
import qs.Widgets

// Calendar month grid with navigation
NBox {
  id: root
  Layout.fillWidth: true
  implicitHeight: calendarContent.implicitHeight + Style.marginM * 2

  // Internal state - independent from header
  readonly property var now: Time.now
  property int calendarMonth: now.getMonth()
  property int calendarYear: now.getFullYear()
  readonly property int firstDayOfWeek: Settings.data.location.firstDayOfWeek === -1 ? I18n.locale.firstDayOfWeek : Settings.data.location.firstDayOfWeek

  // Helper function to calculate ISO week number
  function getISOWeekNumber(date) {
    const target = new Date(date.valueOf());
    const dayNr = (date.getDay() + 6) % 7;
    target.setDate(target.getDate() - dayNr + 3);
    const firstThursday = new Date(target.getFullYear(), 0, 4);
    const diff = target - firstThursday;
    const oneWeek = 1000 * 60 * 60 * 24 * 7;
    const weekNumber = 1 + Math.round(diff / oneWeek);
    return weekNumber;
  }

  // Helper function to check if an event is all-day
  function isAllDayEvent(event) {
    const duration = event.end - event.start;
    const startDate = new Date(event.start * 1000);
    const isAtMidnight = startDate.getHours() === 0 && startDate.getMinutes() === 0;
    return duration === 86400 && isAtMidnight;
  }

  // Navigation functions
  function navigateToPreviousMonth() {
    let newDate = new Date(root.calendarYear, root.calendarMonth - 1, 1);
    root.calendarYear = newDate.getFullYear();
    root.calendarMonth = newDate.getMonth();
    const now = new Date();
    const monthStart = new Date(root.calendarYear, root.calendarMonth, 1);
    const monthEnd = new Date(root.calendarYear, root.calendarMonth + 1, 0);
    const daysBehind = Math.max(0, Math.ceil((now - monthStart) / (24 * 60 * 60 * 1000)));
    const daysAhead = Math.max(0, Math.ceil((monthEnd - now) / (24 * 60 * 60 * 1000)));
    CalendarService.loadEvents(daysAhead + 30, daysBehind + 30);
  }

  function navigateToNextMonth() {
    let newDate = new Date(root.calendarYear, root.calendarMonth + 1, 1);
    root.calendarYear = newDate.getFullYear();
    root.calendarMonth = newDate.getMonth();
    const now = new Date();
    const monthStart = new Date(root.calendarYear, root.calendarMonth, 1);
    const monthEnd = new Date(root.calendarYear, root.calendarMonth + 1, 0);
    const daysBehind = Math.max(0, Math.ceil((now - monthStart) / (24 * 60 * 60 * 1000)));
    const daysAhead = Math.max(0, Math.ceil((monthEnd - now) / (24 * 60 * 60 * 1000)));
    CalendarService.loadEvents(daysAhead + 30, daysBehind + 30);
  }

  // Wheel handler for month navigation
  WheelHandler {
    id: wheelHandler
    target: root
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function (event) {
      if (event.angleDelta.y > 0) {
        // Scroll up - go to previous month
        root.navigateToPreviousMonth();
        event.accepted = true;
      } else if (event.angleDelta.y < 0) {
        // Scroll down - go to next month
        root.navigateToNextMonth();
        event.accepted = true;
      }
    }
  }

  ColumnLayout {
    id: calendarContent
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginS

    // Navigation row
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      Item {
        Layout.preferredWidth: Style.marginS
      }

      NText {
        text: I18n.locale.monthName(root.calendarMonth, Locale.LongFormat).toUpperCase() + " " + root.calendarYear
        pointSize: Style.fontSizeM
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      NDivider {
        Layout.fillWidth: true
      }

      NIconButton {
        icon: "chevron-left"
        onClicked: root.navigateToPreviousMonth()
      }

      NIconButton {
        icon: "calendar"
        onClicked: {
          root.calendarMonth = root.now.getMonth();
          root.calendarYear = root.now.getFullYear();
          CalendarService.loadEvents();
        }
      }

      NIconButton {
        icon: "chevron-right"
        onClicked: root.navigateToNextMonth()
      }
    }

    // Day names header
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
                let dayIndex = (root.firstDayOfWeek + index) % 7;
                const dayName = I18n.locale.dayName(dayIndex, Locale.ShortFormat);
                return dayName.substring(0, 2).toUpperCase();
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

    // Calendar grid with week numbers
    RowLayout {
      Layout.fillWidth: true
      spacing: 0

      // Helper functions
      function hasEventsOnDate(year, month, day) {
        if (!CalendarService.available || CalendarService.events.length === 0)
          return false;
        const targetDate = new Date(year, month, day);
        const targetStart = new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate()).getTime() / 1000;
        const targetEnd = targetStart + 86400;
        return CalendarService.events.some(event => {
                                             return (event.start >= targetStart && event.start < targetEnd) || (event.end > targetStart && event.end <= targetEnd) || (event.start < targetStart && event.end > targetEnd);
                                           });
      }

      function getEventsForDate(year, month, day) {
        if (!CalendarService.available || CalendarService.events.length === 0)
          return [];
        const targetDate = new Date(year, month, day);
        const targetStart = Math.floor(new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate()).getTime() / 1000);
        const targetEnd = targetStart + 86400;
        return CalendarService.events.filter(event => {
                                               return (event.start >= targetStart && event.start < targetEnd) || (event.end > targetStart && event.end <= targetEnd) || (event.start < targetStart && event.end > targetEnd);
                                             });
      }

      function isMultiDayEvent(event) {
        if (root.isAllDayEvent(event)) {
          return false;
        }
        const startDate = new Date(event.start * 1000);
        const endDate = new Date(event.end * 1000);
        const startDateOnly = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate());
        const endDateOnly = new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate());
        return startDateOnly.getTime() !== endDateOnly.getTime();
      }

      function getEventColor(event, isToday) {
        if (isMultiDayEvent(event)) {
          return isToday ? Color.mOnSecondary : Color.mTertiary;
        } else if (root.isAllDayEvent(event)) {
          return isToday ? Color.mOnSecondary : Color.mSecondary;
        } else {
          return isToday ? Color.mOnSecondary : Color.mPrimary;
        }
      }

      // Week numbers column
      ColumnLayout {
        visible: Settings.data.location.showWeekNumberInCalendar
        Layout.preferredWidth: visible ? Style.baseWidgetSize * 0.7 : 0
        Layout.alignment: Qt.AlignTop
        spacing: Style.marginXXS

        property var weekNumbers: {
          if (!grid.daysModel || grid.daysModel.length === 0)
            return [];
          const weeks = [];
          const numWeeks = Math.ceil(grid.daysModel.length / 7);
          for (var i = 0; i < numWeeks; i++) {
            const dayIndex = i * 7;
            if (dayIndex < grid.daysModel.length) {
              const weekDay = grid.daysModel[dayIndex];
              const date = new Date(weekDay.year, weekDay.month, weekDay.day);
              let thursday = new Date(date);
              if (root.firstDayOfWeek === 0) {
                thursday.setDate(date.getDate() + 4);
              } else if (root.firstDayOfWeek === 1) {
                thursday.setDate(date.getDate() + 3);
              } else {
                let daysToThursday = (4 - root.firstDayOfWeek + 7) % 7;
                thursday.setDate(date.getDate() + daysToThursday);
              }
              weeks.push(root.getISOWeekNumber(thursday));
            }
          }
          return weeks;
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
              text: modelData
            }
          }
        }
      }

      // Calendar grid
      GridLayout {
        id: grid
        Layout.fillWidth: true
        columns: 7
        columnSpacing: Style.marginXXS
        rowSpacing: Style.marginXXS

        property int month: root.calendarMonth
        property int year: root.calendarYear

        property var daysModel: {
          const firstOfMonth = new Date(year, month, 1);
          const lastOfMonth = new Date(year, month + 1, 0);
          const daysInMonth = lastOfMonth.getDate();
          const firstDayOfWeek = root.firstDayOfWeek;
          const firstOfMonthDayOfWeek = firstOfMonth.getDay();
          let daysBefore = (firstOfMonthDayOfWeek - firstDayOfWeek + 7) % 7;
          const lastOfMonthDayOfWeek = lastOfMonth.getDay();
          const daysAfter = (firstDayOfWeek - lastOfMonthDayOfWeek - 1 + 7) % 7;
          const days = [];
          const today = new Date();

          // Previous month days
          const prevMonth = new Date(year, month, 0);
          const prevMonthDays = prevMonth.getDate();
          for (var i = daysBefore - 1; i >= 0; i--) {
            const day = prevMonthDays - i;
            days.push({
                        "day": day,
                        "month": month - 1,
                        "year": month === 0 ? year - 1 : year,
                        "today": false,
                        "currentMonth": false
                      });
          }

          // Current month days
          for (var day = 1; day <= daysInMonth; day++) {
            const date = new Date(year, month, day);
            const isToday = date.getFullYear() === today.getFullYear() && date.getMonth() === today.getMonth() && date.getDate() === today.getDate();
            days.push({
                        "day": day,
                        "month": month,
                        "year": year,
                        "today": isToday,
                        "currentMonth": true
                      });
          }

          // Next month days
          for (var i = 1; i <= daysAfter; i++) {
            days.push({
                        "day": i,
                        "month": month + 1,
                        "year": month === 11 ? year + 1 : year,
                        "today": false,
                        "currentMonth": false
                      });
          }

          return days;
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
                    return Color.mOnSecondary;
                  if (modelData.currentMonth)
                    return Color.mOnSurface;
                  return Color.mOnSurfaceVariant;
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
                    radius: Style.radiusXXS
                    color: parent.parent.parent.parent.parent.getEventColor(modelData, modelData.today)
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: Settings.data.location.showCalendarEvents

                onEntered: {
                  const events = parent.parent.parent.parent.getEventsForDate(modelData.year, modelData.month, modelData.day);
                  if (events.length > 0) {
                    const summaries = events.map(event => {
                                                   if (root.isAllDayEvent(event)) {
                                                     return event.summary;
                                                   } else {
                                                     const timeFormat = Settings.data.location.use12hourFormat ? "hh:mm AP" : "HH:mm";
                                                     const start = new Date(event.start * 1000);
                                                     const startFormatted = I18n.locale.toString(start, timeFormat);
                                                     const end = new Date(event.end * 1000);
                                                     const endFormatted = I18n.locale.toString(end, timeFormat);
                                                     return `${startFormatted}-${endFormatted} ${event.summary}`;
                                                   }
                                                 }).join('\n');
                    TooltipService.show(parent, summaries, "auto", Style.tooltipDelay, Settings.data.ui.fontFixed);
                  }
                }

                onClicked: {
                  const dateWithSlashes = `${(modelData.month + 1).toString().padStart(2, '0')}/${modelData.day.toString().padStart(2, '0')}/${modelData.year.toString().substring(2)}`;
                  if (ProgramCheckerService.gnomeCalendarAvailable) {
                    Quickshell.execDetached(["gnome-calendar", "--date", dateWithSlashes]);
                  }
                }

                onExited: {
                  TooltipService.hide();
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
