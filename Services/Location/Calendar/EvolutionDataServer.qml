pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Location

Singleton {
  id: root

  // Python scripts
  readonly property string checkCalendarAvailableScript: Quickshell.shellDir + '/Scripts/python/src/calendar/check-calendar.py'
  readonly property string listCalendarsScript: Quickshell.shellDir + '/Scripts/python/src/calendar/list-calendars.py'
  readonly property string calendarEventsScript: Quickshell.shellDir + '/Scripts/python/src/calendar/calendar-events.py'

  function init() {
    availabilityCheckProcess.running = true;
  }
  function loadCalendars() {
    listCalendarsProcess.running = true;
  }
  function loadEvents(daysAhead = 31, daysBehind = 14) {
    CalendarService.loading = true;
    CalendarService.lastError = "";

    const now = new Date();
    const startDate = new Date(now.getTime() - (daysBehind * 24 * 60 * 60 * 1000));
    const endDate = new Date(now.getTime() + (daysAhead * 24 * 60 * 60 * 1000));

    loadEventsProcess.startTime = Math.floor(startDate.getTime() / 1000);
    loadEventsProcess.endTime = Math.floor(endDate.getTime() / 1000);
    loadEventsProcess.running = true;

    Logger.d("Calendar", `Loading events (${daysBehind} days behind, ${daysAhead} days ahead): ${startDate.toLocaleDateString()} to ${endDate.toLocaleDateString()}`);
  }

  // Process to check for evolution-data-server libraries
  Process {
    id: availabilityCheckProcess
    running: false
    command: ["sh", "-c", "command -v python3 >/dev/null 2>&1 && python3 " + root.checkCalendarAvailableScript + " || echo 'unavailable: python3 not installed'"]

    stdout: StdioCollector {
      onStreamFinished: {
        const result = text.trim();
        if (result === "available") {
          CalendarService.dataProvider = CalendarService.dataProvider || root;
          CalendarService.available = true;
        }

        if (CalendarService.available) {
          Logger.i("Calendar", "EDS libraries available");
          loadCalendars();
        } else {
          Logger.w("Calendar", "EDS libraries not available: " + result);
          CalendarService.lastError = "Evolution Data Server libraries not installed";
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.d("Calendar", "Availability check error: " + text);
          CalendarService.lastError = "Failed to check library availability";
        }
      }
    }
  }

  // Process to list available calendars
  Process {
    id: listCalendarsProcess
    running: false
    command: ["python3", root.listCalendarsScript]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const result = JSON.parse(text.trim());
          CalendarService.setCalendars(result);
          Logger.d("Calendar", `Found ${result.length} calendar(s)`);

          // Auto-load events after discovering calendars
          if (result.length > 0) {
            loadEvents();
          }
        } catch (e) {
          Logger.d("Calendar", "Failed to parse calendars: " + e);
          CalendarService.lastError = "Failed to parse calendar list";
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.d("Calendar", "List calendars error: " + text);
          CalendarService.lastError = text.trim();
        }
      }
    }
  }

  // Process to load events
  Process {
    id: loadEventsProcess
    running: false
    property int startTime: 0
    property int endTime: 0

    command: ["python3", root.calendarEventsScript, startTime.toString(), endTime.toString()]

    stdout: StdioCollector {
      onStreamFinished: {
        CalendarService.loading = false;

        try {
          const events = JSON.parse(text.trim());
          CalendarService.setEvents(events);
          Logger.d("Calendar", `Loaded ${events.length} events(s)`);
        } catch (e) {
          Logger.d("Calendar", "Failed to parse events: " + e);
          CalendarService.lastError = "Failed to parse events";
          // Fall back to cached events
          CalendarService.loadCachedEvents();
          Logger.d("Calendar", "Using cached events");
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        CalendarService.loading = false;

        if (text.trim()) {
          Logger.d("Calendar", "Load events error: " + text);
          CalendarService.lastError = text.trim();

          // Fall back to cached events
          CalendarService.loadCachedEvents();
          Logger.d("Calendar", "Using cached events");
        }
      }
    }
  }
}
