#!/usr/bin/env python3
"""Apply a named KDE color scheme.

Loads kdeglobals, overrides with values from color scheme, saves and notifies
running applications about the change.

Will use jeepney for the D-Bus signal if available, otherwise runs dbus-send.
"""

import configparser
import sys
from pathlib import Path

kglobals = Path('~/.config/kdeglobals').expanduser()
scheme = (
    Path('~/.local/share/color-schemes') / sys.argv[1]
).with_suffix('.colors').expanduser()

kcfg = configparser.RawConfigParser()
kcfg.optionxform = lambda option: option
kcfg.read(kglobals)
scfg = configparser.RawConfigParser()
scfg.optionxform = lambda option: option
scfg.read(scheme)

for s in scfg.sections():
    for k, v in scfg[s].items():
        if s not in kcfg.sections():
            kcfg.add_section(s)
        kcfg[s][k] = v

with open(kglobals, 'w') as out:
    kcfg.write(out, space_around_delimiters=False)

try:
    from jeepney import DBusAddress, new_signal
    from jeepney.io.blocking import open_dbus_connection

    kgs = DBusAddress('/KGlobalSettings', interface='org.kde.KGlobalSettings')
    with open_dbus_connection(bus='SESSION') as sbus:
        msg = new_signal(kgs, 'notifyChange', 'ii', (0, 0))
        reply = sbus.send(msg)
except ModuleNotFoundError:
    from subprocess import run
    run((
        'dbus-send',
        '/KGlobalSettings',
        'org.kde.KGlobalSettings.notifyChange',
        'int32:0',
        'int32:0',
    ), start_new_session=True)
