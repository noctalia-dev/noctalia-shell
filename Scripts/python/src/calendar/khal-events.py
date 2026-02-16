#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

def get_khal_date_format():
    """Read the khal config and extract the longdatetimeformat."""
    xdg_config = os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config'))
    config_path = Path(xdg_config) / 'khal' / 'config'

    if not config_path.exists():
        return '%c'

    with open(config_path, 'r') as f:
        for line in f:
            if m := re.match(r'^longdatetimeformat\s?=\s?(.+?)\s*$', line):
                date_format = m.group(1).strip()
                return date_format

    return '%c'


def to_khal(date_str, khal_format):
    dt = datetime.strptime(date_str, "%Y-%m-%d")
    return dt.strftime(khal_format)

def from_khal(date_str, khal_format):
    if not date_str:
        return ''
    dt = datetime.strptime(date_str, khal_format)
    return dt.isoformat()

def convert_event(event, khal_format):
    event['start-long-full'] = from_khal(event.get('start-long-full', ''), khal_format)
    event['end-long-full'] = from_khal(event.get('end-long-full', ''), khal_format)
    return event

def main():
    start_date = sys.argv[1]
    duration = sys.argv[2]

    khal_format = get_khal_date_format()
    khal_start = to_khal(start_date, khal_format)

    cmd = [
        'khal', 'list',
        '--json', 'uid',
        '--json', 'title',
        '--json', 'start-long-full',
        '--json', 'end-long-full',
        '--json', 'calendar',
        '--json', 'description',
        '--json', 'location',
        khal_start,
        duration
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout.strip()

    for line in output.split('\n'):
        day_events = json.loads(line)
        print(json.dumps([convert_event(e, khal_format) for e in day_events]))

if __name__ == '__main__':
    main()
