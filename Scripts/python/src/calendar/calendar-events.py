#!/usr/bin/env python3
import gi
gi.require_version('EDataServer', '1.2')
gi.require_version('ECal', '2.0')
gi.require_version('ICalGLib', "3.0")

import json, sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
from gi.repository import ECal, EDataServer, ICalGLib

start_time = int(sys.argv[1])
end_time = int(sys.argv[2])

print(f"Starting with time range: {start_time} to {end_time}", file=sys.stderr)

all_events = []

def safe_get_time(ical_time):
    if not ical_time:
        return None, False
    try:
        year, month, day = ical_time.get_year(), ical_time.get_month(), ical_time.get_day()
        is_all_day = hasattr(ical_time, "is_date") and ical_time.is_date()
        if is_all_day:
            # All-day events (birthdays, holidays) should not need
            # to be timezone converted
            return int(datetime(year, month, day).timestamp()), True

        hour, minute, second = ical_time.get_hour(), ical_time.get_minute(), ical_time.get_second()

        # Determine timezone for proper conversion
        tz_obj = ical_time.get_timezone() if hasattr(ical_time, 'get_timezone') else None
        tzid = tz_obj.get_tzid() if tz_obj else None
        tz = None
        if ical_time.is_utc() if hasattr(ical_time, 'is_utc') else False:
            tz = timezone.utc  # Explicit UTC time
        elif tzid:
            # Evolution uses non-standard format: /freeassociation.sourceforge.net/America/Los_Angeles
            # Strip prefix to get IANA name: America/Los_Angeles
            iana = tzid.replace('/freeassociation.sourceforge.net/', '') if tzid.startswith('/') else tzid
            try: tz = ZoneInfo(iana)
            except: pass

        # Create timezone-aware datetime
        dt = datetime(year, month, day, hour, minute, second, tzinfo=tz)
        return int(dt.timestamp()), False
    except:
        return None, False

def add_event(summary, calendar_name, start_ts, end_ts, location="", description="", all_day=False):
    all_events.append({
        'calendar': calendar_name,
        'summary': summary,
        'start': start_ts,
        'end': end_ts,
        'location': location,
        'description': description
    })

registry = EDataServer.SourceRegistry.new_sync(None)
sources = registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR)

for source in sources:
    if not source.get_enabled():
        continue

    calendar_name = source.get_display_name()
    print(f"\nProcessing calendar: {calendar_name}", file=sys.stderr)

    try:
        client = ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, 30, None)

        start_dt = datetime.fromtimestamp(start_time)
        end_dt = datetime.fromtimestamp(end_time)
        start_str = start_dt.strftime("%Y%m%dT%H%M%S")
        end_str = end_dt.strftime("%Y%m%dT%H%M%S")

        query = f'(occur-in-time-range? (make-time "{start_str}") (make-time "{end_str}"))'
        success, raw_events = client.get_object_list_sync(query, None)
        
        if not success or not raw_events:
            continue

        for raw_obj in raw_events:
            obj = raw_obj[1] if isinstance(raw_obj, tuple) else raw_obj
            comp = None

            if isinstance(obj, ICalGLib.Component):
                comp = obj
            elif isinstance(obj, ECal.Component):
                try:
                    ical_str = obj.to_string()
                    temp_comp = ICalGLib.Component.new_from_string(ical_str)
                    if temp_comp.getName() == "VEVENT":
                        comp = temp_comp
                except Exception:
                    comp = None

            if not comp:
                summary = getattr(obj, "get_summary", lambda: "(No title)")()
                dtstart = getattr(obj, "get_dtstart", lambda: None)()
                dtend = getattr(obj, "get_dtend", lambda: None)()
                start_ts, all_day = safe_get_time(dtstart)
                end_ts, _ = safe_get_time(dtend)
                if start_ts:
                    if end_ts is None:
                        end_ts = start_ts + 3600
                    add_event(summary, calendar_name, start_ts, end_ts)
                continue

            summary = getattr(comp, "get_summary", lambda: "(No title)")()
            dtstart = getattr(comp, "get_dtstart", lambda: None)()
            dtend = getattr(comp, "get_dtend", lambda: None)()
            start_ts, all_day = safe_get_time(dtstart)
            end_ts, _ = safe_get_time(dtend)
            if end_ts is None and start_ts is not None:
                end_ts = start_ts + 3600

            rrule_getter = getattr(comp, "get_first_property", None)
            if rrule_getter:
                rrule_prop = comp.get_first_property(73)  # ICAL_RRULE_PROPERTY
                if rrule_prop:
                    rrule_value = rrule_prop.get_value()  # ICalGLib.Value
                    
                    try:
                        recurrence = rrule_value.get_recur()  # -> ICalGLib.Recurrence
                        
                    except AttributeError:
                        rrule_str = str(rrule_value)
                        recurrence = ICalGLib.Recurrence.new_from_string(rrule_str)

                    if recurrence:
                        freq = recurrence.get_freq()
                        
            rdates = getattr(comp, "get_rdate_list", lambda: [])()
            exdates = getattr(comp, "get_exdate_list", lambda: [])()

            # --- normal event ---
            if not rrule_prop and not rdates:
                add_event(summary, calendar_name, start_ts, end_ts)
                continue

            # --- recurrent events ---
            if freq:
                summary = comp.get_summary() or "(No title)"
                dtstart = comp.get_dtstart()
                dtend = comp.get_dtend()
                start_ts, all_day = safe_get_time(dtstart)
                end_ts, _ = safe_get_time(dtend)
                if end_ts is None and start_ts is not None:
                    end_ts = start_ts + 3600  # 1h default

                interval = recurrence.get_interval() or 1
                count = recurrence.get_count()
                until_dt = recurrence.get_until()
                until_ts, _ = safe_get_time(until_dt) if until_dt else (None, False)
                if until_ts is None:
                    until_ts = end_time

                occurrences = []
                current_ts = start_ts
                added = 0

                match freq:
                    case 0: #SECONDLY
                        delta = timedelta(seconds=interval)
                        while (current_ts <= until_ts) and (not count or added < count):
                            occurrences.append((current_ts, current_ts + (end_ts - start_ts)))
                            current_ts += int(delta.total_seconds())
                            added += 1

                    case 1: #MINUTELY
                        delta = timedelta(minutes=interval)
                        while (current_ts <= until_ts) and (not count or added < count):
                            occurrences.append((current_ts, current_ts + (end_ts - start_ts)))
                            current_ts += int(delta.total_seconds())
                            added += 1
                            
                    case 2: #HOURLY
                        delta = timedelta(hours=interval)
                        while (current_ts <= until_ts) and (not count or added < count):
                            occurrences.append((current_ts, current_ts + (end_ts - start_ts)))
                            current_ts += int(delta.total_seconds())
                            added += 1

                    case 3:  # DAILY
                        delta = timedelta(days=interval)
                        while (current_ts <= until_ts) and (not count or added < count):
                            occurrences.append((current_ts, current_ts + (end_ts - start_ts)))
                            current_ts += int(delta.total_seconds())
                            added += 1

                    case 4:  # WEEKLY
                        delta = timedelta(weeks=interval)
                        while (current_ts <= until_ts) and (not count or added < count):
                            occurrences.append((current_ts, current_ts + (end_ts - start_ts)))
                            current_ts += int(delta.total_seconds())
                            added += 1

                    case 5:  # MONTHLY
                        from dateutil.relativedelta import relativedelta
                        dt = datetime.fromtimestamp(current_ts)
                        while (current_ts <= until_ts) and (not count or added < count):
                            occurrences.append((current_ts, current_ts + (end_ts - start_ts)))
                            dt += relativedelta(months=interval)
                            current_ts = int(dt.timestamp())
                            added += 1

                    case 6:  # YEARLY
                        from dateutil.relativedelta import relativedelta
                        dt = datetime.fromtimestamp(current_ts)
                        while (current_ts <= until_ts) and (not count or added < count):
                            occurrences.append((current_ts, current_ts + (end_ts - start_ts)))
                            dt += relativedelta(years=interval)
                            current_ts = int(dt.timestamp())
                            added += 1

                    case _:  # NONE
                        occurrences.append((start_ts, end_ts))

                # --- add occurences to all_events ---
                for occ_start, occ_end in occurrences:
                    add_event(summary, calendar_name, occ_start, occ_end)


    except Exception as e:
        print(f"  Error for {calendar_name}: {e}", file=sys.stderr)

all_events.sort(key=lambda x: x['start'])
print(json.dumps(all_events, indent=4))

