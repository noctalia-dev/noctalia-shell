#!/usr/bin/env python3
import gi

gi.require_version('EDataServer', '1.2')
import json

from gi.repository import EDataServer

registry = EDataServer.SourceRegistry.new_sync(None)
sources = registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR)

calendars = []
for source in sources:
    if source.get_enabled():
        calendars.append({
            'uid': source.get_uid(),
            'name': source.get_display_name(),
            'enabled': True
        })

print(json.dumps(calendars))
