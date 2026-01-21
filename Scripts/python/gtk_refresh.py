#!/usr/bin/env python3

import asyncio
import os
import sys
from pathlib import Path


async def run_command(*args):
    try:
        process = await asyncio.create_subprocess_exec(
            *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
    except FileNotFoundError as e:
        return None

    stdout, stderr = await process.communicate()
    if process.returncode != 0:
        print(f"Error running {' '.join(args)}: {stderr.decode().strip()}", file=sys.stderr)
    return stdout.decode().strip()


async def apply_gtk3_colors(config_dir: Path):
    gtk3_dir = config_dir / "gtk-3.0"
    colors_file = gtk3_dir / "noctalia.css"
    gtk_css = gtk3_dir / "gtk.css"

    if not colors_file.exists():
        print(f"Error: noctalia.css not found at {colors_file}", file=sys.stderr)
        return False

    if gtk_css.is_symlink():
        gtk_css.unlink()
    elif gtk_css.exists():
        backup_name = f"gtk.css.backup.{int(os.path.getmtime(gtk_css))}"
        gtk_css.rename(gtk3_dir / backup_name)
        print(f"Backed up existing gtk.css to {backup_name}")

    gtk_css.symlink_to("noctalia.css")
    print(f"Created symlink: {gtk_css} -> noctalia.css")
    return True


async def apply_gtk4_colors(config_dir: Path):
    gtk4_dir = config_dir / "gtk-4.0"
    colors_file = gtk4_dir / "noctalia.css"
    gtk_css = gtk4_dir / "gtk.css"
    gtk4_import = '@import url("noctalia.css");'

    if not colors_file.exists():
        print(f"Error: GTK4 noctalia.css not found at {colors_file}", file=sys.stderr)
        return False

    gtk_css.write_text(gtk4_import)
    print("Updated GTK4 CSS import")
    return True


async def refresh_theme():
    """
    Trigger GTK theme refresh.
    1️⃣ Prefer gsettings if available and schema exists
    2️⃣ Fallback to dconf if gsettings not available or schema missing
    3️⃣ Skip entirely if neither backend is available
    """

    has_gsettings = await run_command("which", "gsettings")
    has_dconf = await run_command("which", "dconf")

    if not has_gsettings and not has_dconf:
        print("No gsettings or dconf found, skip GTK refresh")
        return

    # --- gsettings ---
    if has_gsettings:
        schemas = await run_command("gsettings", "list-schemas")
        if schemas and "org.gnome.desktop.interface" in schemas:
            await run_command("gsettings", "set", "org.gnome.desktop.interface", "color-scheme", f"prefer-{mode}")
            print("GTK refreshed via gsettings")
            return

    # --- fallback dconf ---
    if has_dconf:
        await run_command("dconf", "write", "/org/gnome/desktop/interface/color-scheme", f"'prefer-{mode}'")
        print("GTK refreshed via dconf")
        return

    print("GTK refresh skipped (no supported backend)")


async def get_config_dir() -> Path:
    # 1. project-specific override
    if value := os.environ.get("NOCTALIA_CONFIG_DIR"):
        return Path(value).expanduser()

    # 2. XDG standard
    if value := os.environ.get("XDG_CONFIG_HOME"):
        return Path(value).expanduser()

    # 3. fallback
    return Path.home() / ".config"


async def main():
    config_dir = await get_config_dir()

    if not config_dir.is_dir():
        print(f"Error: Config directory not found: {config_dir}", file=sys.stderr)
        sys.exit(1)

    (config_dir / "gtk-3.0").mkdir(parents=True, exist_ok=True)
    (config_dir / "gtk-4.0").mkdir(parents=True, exist_ok=True)

    results = await asyncio.gather(apply_gtk3_colors(config_dir), apply_gtk4_colors(config_dir))

    if all(results):
        await refresh_theme()
        print("GTK colors applied successfully")
    else:
        sys.exit(1)


if __name__ == "__main__":
    mode = sys.argv[1]  # light or dark
    asyncio.run(main())
