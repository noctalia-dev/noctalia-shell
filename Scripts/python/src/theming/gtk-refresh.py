#!/usr/bin/env python3

import asyncio
import os
import sys
import shutil
from pathlib import Path


async def run_command(*args):
    process = await asyncio.create_subprocess_exec(
        *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    stdout, stderr = await process.communicate()
    if process.returncode != 0:
        print(f"Error running {' '.join(args)}: {stderr.decode().strip()}", file=sys.stderr)
    return stdout.decode().strip()


def theme_exists(theme_name: str) -> bool:
    """Check if a GTK theme exists in common locations."""
    search_paths = [
        Path.home() / ".themes",
        Path.home() / ".local/share/themes",
        Path("/usr/share/themes"),
        Path("/usr/local/share/themes"),
    ]

    # Add paths from XDG_DATA_DIRS
    xdg_data_dirs = os.environ.get("XDG_DATA_DIRS", "")
    if xdg_data_dirs:
        for path in xdg_data_dirs.split(":"):
            if path:
                search_paths.append(Path(path) / "themes")

    for base_path in search_paths:
        if (base_path / theme_name).is_dir():
            return True

    return False


GTK_IMPORT = '@import url("noctalia.css");'


def ensure_gtk_css_import(gtk_css: Path, colors_file: Path, label: str) -> bool:
    """
    Append the noctalia.css import to gtk.css if not already present.
    If gtk.css doesn't exist, create it with the import.
    Does not overwrite user modifications (similar to niri template).
    """
    if not colors_file.exists():
        print(f"Error: {label} noctalia.css not found at {colors_file}", file=sys.stderr)
        return False

    if gtk_css.exists() or gtk_css.is_symlink():
        content = gtk_css.read_text()
        # Already has the import (flexible: allow optional whitespace / different quoting)
        if "noctalia.css" in content and "@import" in content:
            return True
        # Need to modify — convert symlink to regular file first
        if gtk_css.is_symlink():
            resolved = gtk_css.resolve()
            gtk_css.unlink()
            gtk_css.write_text(resolved.read_text())
        # Append import to the end
        new_content = content.rstrip()
        if new_content and not new_content.endswith("\n"):
            new_content += "\n"
        new_content += "\n" + GTK_IMPORT + "\n"
        gtk_css.write_text(new_content)
        print(f"Appended {label} noctalia.css import to gtk.css")
    else:
        gtk_css.write_text(GTK_IMPORT + "\n")
        print(f"Created {label} gtk.css with noctalia.css import")
    return True


async def apply_gtk3_colors(config_dir: Path):
    gtk3_dir = config_dir / "gtk-3.0"
    colors_file = gtk3_dir / "noctalia.css"
    gtk_css = gtk3_dir / "gtk.css"
    return ensure_gtk_css_import(gtk_css, colors_file, "GTK3")


async def apply_gtk4_colors(config_dir: Path):
    gtk4_dir = config_dir / "gtk-4.0"
    colors_file = gtk4_dir / "noctalia.css"
    gtk_css = gtk4_dir / "gtk.css"
    return ensure_gtk_css_import(gtk_css, colors_file, "GTK4")


async def sync_system_appearance(mode: str, *, update_gtk_theme: bool = True) -> None:
    """
    Push light/dark to org.gnome.desktop.interface (gsettings or dconf fallback).
    Used by the GTK template post-hook (also sets gtk-theme when update_gtk_theme)
    and by Noctalia on dark-mode toggle (--appearance-only: color-scheme only).
    """
    has_gsettings = shutil.which("gsettings")
    has_dconf = shutil.which("dconf")

    if not has_gsettings and not has_dconf:
        print("No gsettings or dconf found, skip system appearance sync")
        return

    target_theme = "adw-gtk3" if mode == "light" else "adw-gtk3-dark"
    theme_available = update_gtk_theme and theme_exists(target_theme)
    if update_gtk_theme and not theme_available:
        print(f"Theme '{target_theme}' not found, skipping GTK theme set")

    if has_gsettings:
        schemas = await run_command("gsettings", "list-schemas")
        if schemas and "org.gnome.desktop.interface" in schemas:
            await run_command("gsettings", "set", "org.gnome.desktop.interface", "color-scheme", f"prefer-{mode}")
            if theme_available:
                await run_command("gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", f"{target_theme}")
            return

    if has_dconf:
        await run_command("dconf", "write", "/org/gnome/desktop/interface/color-scheme", f"'prefer-{mode}'")
        if theme_available:
            await run_command("dconf", "write", "/org/gnome/desktop/interface/gtk-theme", f"'{target_theme}'")


async def get_config_dir() -> Path:
    # Returns the XDG config home (e.g. ~/.config)
    # GTK config lives at ~/.config/gtk-3.0/ and ~/.config/gtk-4.0/.

    # 1. XDG standard
    if value := os.environ.get("XDG_CONFIG_HOME"):
        return Path(value).expanduser()

    # 2. fallback
    return Path.home() / ".config"


def parse_args():
    argv = sys.argv[1:]
    appearance_only = False
    if argv and argv[0] == "--appearance-only":
        appearance_only = True
        argv = argv[1:]
    if len(argv) != 1 or argv[0] not in ("dark", "light"):
        print(
            "Usage: gtk-refresh.py [--appearance-only] (dark|light)",
            file=sys.stderr,
        )
        sys.exit(1)
    return appearance_only, argv[0]


async def main():
    appearance_only, mode = parse_args()

    if appearance_only:
        await sync_system_appearance(mode, update_gtk_theme=False)
        return

    config_dir = await get_config_dir()

    if not config_dir.is_dir():
        print(f"Error: Config directory not found: {config_dir}", file=sys.stderr)
        sys.exit(1)

    (config_dir / "gtk-3.0").mkdir(parents=True, exist_ok=True)
    (config_dir / "gtk-4.0").mkdir(parents=True, exist_ok=True)

    results = await asyncio.gather(apply_gtk3_colors(config_dir), apply_gtk4_colors(config_dir))

    if all(results):
        await sync_system_appearance(mode, update_gtk_theme=True)
        print("GTK colors applied successfully")
    else:
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
