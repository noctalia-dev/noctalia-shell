#!/usr/bin/env python3
import gi

gi.require_version('EDataServer', '1.2')
gi.require_version('ECal', '2.0')

try:
    from gi.repository import ECal, EDataServer
    print("available")
except ImportError as e:
    print(f"unavailable: {e}")
