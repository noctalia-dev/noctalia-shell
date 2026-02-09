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
    has_gsettings = shutil.which("gsettings")
    has_dconf = shutil.which("dconf")

    if not has_gsettings and not has_dconf:
        print("No gsettings or dconf found, skip GTK refresh")
        return

    if mode == "light":
        target_theme = "adw-gtk3"
    else:
        target_theme = "adw-gtk3-dark"

    theme_available = theme_exists(target_theme)
    if not theme_available:
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
