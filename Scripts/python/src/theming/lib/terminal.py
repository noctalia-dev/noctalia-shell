"""
Terminal theme generation for multiple terminal emulators.

Generates native theme files from a unified terminal color schema.
Supports: foot, ghostty, kitty, alacritty, wezterm
"""

from __future__ import annotations

from dataclasses import dataclass


def darken_hex(color: str, percent: float) -> str:
    """Darken a hex color by a percentage (0-100)."""
    hex_color = color.lstrip("#")
    r = int(hex_color[0:2], 16)
    g = int(hex_color[2:4], 16)
    b = int(hex_color[4:6], 16)

    factor = 1 - (percent / 100)
    r = max(0, int(r * factor))
    g = max(0, int(g * factor))
    b = max(0, int(b * factor))

    return f"#{r:02x}{g:02x}{b:02x}"


@dataclass
class TerminalColors:
    """Terminal color scheme data."""

    # Base colors (from JSON)
    foreground: str
    background: str
    cursor: str
    cursor_text: str
    selection_fg: str
    selection_bg: str
    normal: dict[str, str]  # black, red, green, yellow, blue, magenta, cyan, white
    bright: dict[str, str]  # same keys

    # WezTerm extended colors (always derived)
    compose_cursor: str
    scrollbar_thumb: str
    split: str
    visual_bell: str
    indexed: dict[int, str]
    tab_bar: dict

    @classmethod
    def from_dict(cls, data: dict, scheme: dict) -> "TerminalColors":
        """Create TerminalColors with auto-derived WezTerm extended colors.

        Args:
            data: Terminal color data (foreground, background, cursor, normal, bright, etc.)
            scheme: Scheme UI colors (mPrimary, mOnPrimary, mSecondary)
        """
        # Base colors
        foreground = data["foreground"]
        background = data["background"]
        cursor = data.get("cursor", foreground)
        cursor_text = data.get("cursorText", background)
        selection_fg = data.get("selectionFg", foreground)
        selection_bg = data.get("selectionBg", "#585b70")
        normal = data["normal"]
        bright = data["bright"]

        # Scheme accent colors
        m_primary = scheme.get("mPrimary", cursor)
        m_on_primary = scheme.get("mOnPrimary", cursor_text)
        m_secondary = scheme.get("mSecondary", normal["yellow"])

        return cls(
            foreground=foreground,
            background=background,
            cursor=cursor,
            cursor_text=cursor_text,
            selection_fg=selection_fg,
            selection_bg=selection_bg,
            normal=normal,
            bright=bright,
            # Derived WezTerm colors
            compose_cursor=cursor,
            scrollbar_thumb=selection_bg,
            split=bright["black"],
            visual_bell=normal["black"],
            indexed={16: m_secondary, 17: cursor},
            tab_bar={
                "background": darken_hex(background, 10),
                "inactiveTabEdge": selection_bg,
                "activeTab": {"bg": m_primary, "fg": m_on_primary},
                "inactiveTab": {"bg": darken_hex(background, 5), "fg": foreground},
                "inactiveTabHover": {"bg": background, "fg": foreground},
                "newTab": {"bg": selection_bg, "fg": foreground},
                "newTabHover": {"bg": bright["black"], "fg": foreground},
            },
        )


# Color name to index mapping for ANSI colors
COLOR_ORDER = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]


class TerminalGenerator:
    """Generate terminal themes in native formats."""

    def __init__(self, colors: TerminalColors):
        self.colors = colors

    def _strip_hash(self, color: str) -> str:
        """Remove # prefix from hex color."""
        return color.lstrip("#")

    def _ensure_hash(self, color: str) -> str:
        """Ensure # prefix on hex color."""
        return color if color.startswith("#") else f"#{color}"

    def generate_foot(self) -> str:
        """Generate foot terminal theme (INI format, no # prefix)."""
        c = self.colors
        lines = ["[colors]"]

        # Primary colors
        lines.append(f"foreground={self._strip_hash(c.foreground)}")
        lines.append(f"background={self._strip_hash(c.background)}")

        # Normal colors (regular0-7)
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"regular{i}={self._strip_hash(c.normal[name])}")

        # Bright colors (bright0-7)
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"bright{i}={self._strip_hash(c.bright[name])}")

        # Selection
        lines.append(f"selection-foreground={self._strip_hash(c.selection_fg)}")
        lines.append(f"selection-background={self._strip_hash(c.selection_bg)}")

        # Cursor (format: bg fg)
        lines.append(
            f"cursor={self._strip_hash(c.cursor_text)} {self._strip_hash(c.cursor)}"
        )

        return "\n".join(lines) + "\n"

    def generate_ghostty(self) -> str:
        """Generate ghostty theme (key=value with palette indices)."""
        c = self.colors
        lines = []

        # Palette (0-7 normal, 8-15 bright)
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"palette = {i}={self._ensure_hash(c.normal[name])}")
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"palette = {i + 8}={self._ensure_hash(c.bright[name])}")

        # Primary colors
        lines.append(f"background = {self._ensure_hash(c.background)}")
        lines.append(f"foreground = {self._ensure_hash(c.foreground)}")

        # Cursor
        lines.append(f"cursor-color = {self._ensure_hash(c.cursor)}")
        lines.append(f"cursor-text = {self._ensure_hash(c.cursor_text)}")

        # Selection
        lines.append(f"selection-background = {self._ensure_hash(c.selection_bg)}")
        lines.append(f"selection-foreground = {self._ensure_hash(c.selection_fg)}")

        return "\n".join(lines) + "\n"

    def generate_kitty(self) -> str:
        """Generate kitty theme (key value pairs with # prefix)."""
        c = self.colors
        lines = []

        # Colors 0-15
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"color{i} {self._ensure_hash(c.normal[name])}")
        for i, name in enumerate(COLOR_ORDER):
            lines.append(f"color{i + 8} {self._ensure_hash(c.bright[name])}")

        # Primary colors
        lines.append(f"background {self._ensure_hash(c.background)}")
        lines.append(f"selection_foreground {self._ensure_hash(c.cursor_text)}")
        lines.append(f"cursor {self._ensure_hash(c.cursor)}")
        lines.append(f"cursor_text_color {self._ensure_hash(c.cursor_text)}")
        lines.append(f"foreground {self._ensure_hash(c.foreground)}")
        lines.append(f"selection_background {self._ensure_hash(c.foreground)}")

        return "\n".join(lines) + "\n"

    def generate_alacritty(self) -> str:
        """Generate alacritty theme (TOML format)."""
        c = self.colors
        lines = ["# Colors (Noctalia)", ""]

        # Bright colors
        lines.append("[colors.bright]")
        for name in sorted(COLOR_ORDER):
            lines.append(f"{name} = '{self._ensure_hash(c.bright[name])}'")
        lines.append("")

        # Cursor
        lines.append("[colors.cursor]")
        lines.append(f"cursor = '{self._ensure_hash(c.cursor)}'")
        lines.append(f"text = '{self._ensure_hash(c.cursor_text)}'")
        lines.append("")

        # Normal colors
        lines.append("[colors.normal]")
        for name in sorted(COLOR_ORDER):
            lines.append(f"{name} = '{self._ensure_hash(c.normal[name])}'")
        lines.append("")

        # Primary
        lines.append("[colors.primary]")
        lines.append(f"background = '{self._ensure_hash(c.background)}'")
        lines.append(f"foreground = '{self._ensure_hash(c.foreground)}'")
        lines.append("")

        # Selection
        lines.append("[colors.selection]")
        lines.append(f"background = '{self._ensure_hash(c.selection_bg)}'")
        lines.append(f"text = '{self._ensure_hash(c.selection_fg)}'")

        return "\n".join(lines) + "\n"

    def generate_wezterm(self) -> str:
        """Generate wezterm theme (full TOML with metadata)."""
        c = self.colors
        tb = c.tab_bar
        lines = ["[colors]"]

        # Ansi colors array
        lines.append("ansi = [")
        for name in COLOR_ORDER:
            lines.append(f'    "{self._ensure_hash(c.normal[name])}",')
        lines.append("]")

        lines.append(f'background = "{self._ensure_hash(c.background)}"')

        # Brights array
        lines.append("brights = [")
        for name in COLOR_ORDER:
            lines.append(f'    "{self._ensure_hash(c.bright[name])}",')
        lines.append("]")

        # Extended colors
        lines.append(f'compose_cursor = "{self._ensure_hash(c.compose_cursor)}"')
        lines.append(f'cursor_bg = "{self._ensure_hash(c.cursor)}"')
        lines.append(f'cursor_border = "{self._ensure_hash(c.cursor)}"')
        lines.append(f'cursor_fg = "{self._ensure_hash(c.cursor_text)}"')
        lines.append(f'foreground = "{self._ensure_hash(c.foreground)}"')
        lines.append(f'scrollbar_thumb = "{self._ensure_hash(c.scrollbar_thumb)}"')
        lines.append(f'selection_bg = "{self._ensure_hash(c.selection_bg)}"')
        lines.append(f'selection_fg = "{self._ensure_hash(c.selection_fg)}"')
        lines.append(f'split = "{self._ensure_hash(c.split)}"')
        lines.append(f'visual_bell = "{self._ensure_hash(c.visual_bell)}"')

        # Indexed colors
        lines.append("")
        lines.append("[colors.indexed]")
        for idx, color in sorted(c.indexed.items()):
            lines.append(f'{idx} = "{self._ensure_hash(color)}"')

        # Tab bar
        lines.append("")
        lines.append("[colors.tab_bar]")
        lines.append(f'background = "{self._ensure_hash(tb["background"])}"')
        lines.append(f'inactive_tab_edge = "{self._ensure_hash(tb["inactiveTabEdge"])}"')

        for section, key in [
            ("activeTab", "active_tab"),
            ("inactiveTab", "inactive_tab"),
            ("inactiveTabHover", "inactive_tab_hover"),
            ("newTab", "new_tab"),
            ("newTabHover", "new_tab_hover"),
        ]:
            lines.append("")
            lines.append(f"[colors.tab_bar.{key}]")
            lines.append(f'bg_color = "{self._ensure_hash(tb[section]["bg"])}"')
            lines.append(f'fg_color = "{self._ensure_hash(tb[section]["fg"])}"')
            lines.append('intensity = "Normal"')
            lines.append("italic = false")
            lines.append("strikethrough = false")
            lines.append('underline = "None"')

        # Metadata
        lines.append("")
        lines.append("[metadata]")
        lines.append('author = "Noctalia"')
        lines.append('name = "Noctalia"')

        return "\n".join(lines) + "\n"

    def generate(self, terminal_id: str) -> str:
        """Generate theme for specified terminal."""
        generators = {
            "foot": self.generate_foot,
            "ghostty": self.generate_ghostty,
            "kitty": self.generate_kitty,
            "alacritty": self.generate_alacritty,
            "wezterm": self.generate_wezterm,
        }

        if terminal_id not in generators:
            raise ValueError(f"Unknown terminal: {terminal_id}")

        return generators[terminal_id]()
