pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Location

Singleton {
  id: root

  readonly property string khalEventsScript: Quickshell.shellDir + '/Scripts/python/src/calendar/khal-events.py'

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

    loadEventsProcess.startTime = formatDateYMD(startDate);
    loadEventsProcess.duration = `${daysAhead + daysBehind}d`;
    loadEventsProcess.running = true;

    Logger.d("Calendar", `Loading events (${daysBehind} days behind, ${daysAhead} days ahead): ${loadEventsProcess.startTime}  ${loadEventsProcess.duration}`);
  }

  // Process to check for khal installation
  Process {
    id: availabilityCheckProcess
    running: false
    command: ["sh", "-c", "command -v khal >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1"]
    onExited: function (exitCode) {
      if (exitCode === 0) {
        CalendarService.available = true;
        CalendarService.dataProvider = CalendarService.dataProvider || root;
      }

      if (CalendarService.available) {
        Logger.i("Calendar", "Khal available");
        loadCalendars();
      } else {
        Logger.w("Calendar", "Khal not available");
        CalendarService.lastError = "khal binary not installed";
      }
    }
  }

  // Process to list available calendars
  Process {
    id: listCalendarsProcess
    running: false
    command: ["khal", "printcalendars"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const calendars = text.trim().split("\n");
          CalendarService.setCalendars(calendars);

          Logger.d("Calendar", `Found ${calendars.length} calendar(s)`);

          // Auto-load events after discovering calendars
          if (calendars.length > 0) {
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
    property string startTime: ""
    property string duration: ""

    command: ["python3", root.khalEventsScript, startTime, duration]

    stdout: StdioCollector {
      onStreamFinished: {
        CalendarService.loading = false;

        try {
          const events = parseEvents(text.trim());
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

  function parseEvents(text) {
    const result = [];

    for (const line of text.split("\n")) {
      if (!line.trim())
        continue;
      const dayEvents = JSON.parse(line);
      for (const event of dayEvents) {
        result.push({
                      uid: event.uid,
                      calendar: event.calendar,
                      summary: event.title,
                      start: parseTimestamp(event["start-long-full"]),
                      end: parseTimestamp(event["end-long-full"]),
                      location: event.location,
                      description: event.description
                    });
      }
    }

    return result;
  }

  function parseTimestamp(timeStr) {
    // expects ISO8601 format
    return Math.floor((Date.parse(timeStr)).valueOf() / 1000);
  }

  function formatDateYMD(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, "0");
    const d = String(date.getDate()).padStart(2, "0");
    return y + "-" + m + "-" + d;
  }
}
