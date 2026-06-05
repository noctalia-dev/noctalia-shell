#pragma once

#include "calendar/calendar_types.h"

#include <string_view>
#include <vector>

namespace calendar {

  // Parse iCalendar (RFC 5545) text into concrete event instances. Recurrence is not expanded here:
  // callers request server-side expansion (CalDAV <C:expand>), so each VEVENT is one instance.
  // UID/SUMMARY/DTSTART/DTEND/LOCATION are read; VTODO/VALARM and other components are ignored.
  std::vector<CalendarEvent> parseICalEvents(std::string_view ics);

} // namespace calendar
