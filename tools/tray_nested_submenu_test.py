#!/usr/bin/env python3

import signal
import sys

import gi

gi.require_version("Gtk", "3.0")
try:
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3 as AppIndicator3
except ValueError:
    gi.require_version("AppIndicator3", "0.1")
    from gi.repository import AppIndicator3

from gi.repository import Gtk


def on_click(label: str):
    def _handler(_widget):
        print(f"[tray-test] clicked: {label}", flush=True)

    return _handler


def build_menu() -> Gtk.Menu:
    root = Gtk.Menu()

    direct = Gtk.MenuItem.new_with_label("Direct Item")
    direct.connect("activate", on_click("Direct Item"))
    root.append(direct)

    level1_item = Gtk.MenuItem.new_with_label("Level 1 Submenu")
    level1_menu = Gtk.Menu()

    level1_action = Gtk.MenuItem.new_with_label("Level 1 Action")
    level1_action.connect("activate", on_click("Level 1 Action"))
    level1_menu.append(level1_action)

    level2_item = Gtk.MenuItem.new_with_label("Level 2 Submenu")
    level2_menu = Gtk.Menu()

    level2_action_a = Gtk.MenuItem.new_with_label("Level 2 Action A")
    level2_action_a.connect("activate", on_click("Level 2 Action A"))
    level2_menu.append(level2_action_a)

    level2_action_b = Gtk.MenuItem.new_with_label("Level 2 Action B")
    level2_action_b.connect("activate", on_click("Level 2 Action B"))
    level2_menu.append(level2_action_b)

    level3_item = Gtk.MenuItem.new_with_label("Level 3 Submenu")
    level3_menu = Gtk.Menu()
    level3_action = Gtk.MenuItem.new_with_label("Level 3 Action")
    level3_action.connect("activate", on_click("Level 3 Action"))
    level3_menu.append(level3_action)
    level3_item.set_submenu(level3_menu)
    level2_menu.append(level3_item)

    level2_item.set_submenu(level2_menu)
    level1_menu.append(level2_item)

    level1_item.set_submenu(level1_menu)
    root.append(level1_item)

    sep = Gtk.SeparatorMenuItem()
    root.append(sep)

    quit_item = Gtk.MenuItem.new_with_label("Quit")
    quit_item.connect("activate", lambda _w: Gtk.main_quit())
    root.append(quit_item)

    root.show_all()
    return root


def main() -> int:
    indicator = AppIndicator3.Indicator.new(
        "noctalia-tray-nested-submenu-test",
        "applications-system",
        AppIndicator3.IndicatorCategory.APPLICATION_STATUS,
    )
    indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
    indicator.set_title("Tray Nested Submenu Test")
    indicator.set_menu(build_menu())

    signal.signal(signal.SIGINT, signal.SIG_DFL)
    print("[tray-test] running. Open tray icon and click nested submenu actions.", flush=True)
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
