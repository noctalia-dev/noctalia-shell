"""
Template rendering for Matugen compatibility.

This module provides the TemplateRenderer class for processing template files
using the {{colors.name.mode.format}} syntax compatible with Matugen.

Supports:
- Pipe filters: {{ colors.primary.dark.hex | set_alpha 0.5 | grayscale }}
- For loops: <* for name, value in colors *> ... <* endfor *>
- If/else: <* if {{ expr }} *> ... <* else *> ... <* endif *>
- Loop variables: loop.index, loop.first, loop.last
- Color filters: grayscale, invert, set_alpha, set_lightness, set_hue,
  set_saturation, set_red, set_green, set_blue, lighten, darken,
  saturate, desaturate, auto_lightness, blend, harmonize, to_color
- String filters: replace, lower_case, camel_case, pascal_case,
  snake_case, kebab_case
- Custom colors: [config.custom_colors] in TOML config generates
  {name}, on_{name}, {name}_container, on_{name}_container tokens
"""

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional, Union

try:
    import tomllib
except ImportError:
    tomllib = None

from .color import Color, find_closest_color
from .hct import Hct


# --- Node Types for the template AST ---

@dataclass
class TextNode:
    text: str

@dataclass
class ForNode:
    variables: list[str]
    iterable: str
    body: list

@dataclass
class IfNode:
    condition_expr: str
    negated: bool
    then_body: list
    else_body: list = field(default_factory=list)


# --- Variable Scope Stack ---

class VariableScope:
    """Stack-based variable scope for loop variables."""

    def __init__(self):
        self._scopes: list[dict[str, Any]] = []

    def push(self, bindings: Optional[dict[str, Any]] = None):
        self._scopes.append(bindings or {})

    def pop(self):
        if self._scopes:
            self._scopes.pop()

    def set(self, name: str, value: Any):
        if self._scopes:
            self._scopes[-1][name] = value

    def get(self, name: str) -> Optional[Any]:
        """Look up variable, searching from innermost scope outward."""
        for scope in reversed(self._scopes):
            if name in scope:
                return scope[name]
        return None

    @property
    def is_active(self) -> bool:
        return len(self._scopes) > 0


# --- Known color format types ---

KNOWN_FORMATS = frozenset({
    "hex", "hex_stripped", "rgb", "rgba", "hsl", "hsla",
    "red", "green", "blue", "alpha", "hue", "saturation", "lightness",
})


class TemplateRenderer:
    """
    Renders templates using the generated theme colors.
    Compatible with Matugen-style {{colors.name.mode.format}} tags.

    Supports filters via pipe syntax:
        {{ colors.primary.dark.hex | grayscale }}
        {{ colors.primary.dark.rgba | set_alpha 0.5 }}

    Supports block constructs:
        <* for name, value in colors *> ... <* endfor *>
        <* if {{ loop.first }} *> ... <* else *> ... <* endif *>

    Theme data uses snake_case keys (e.g., 'primary', 'surface_container').
    """

    # Aliases for custom/legacy keys
    COLOR_ALIASES = {
        "hover": "surface_container_high",
        "on_hover": "on_surface",
    }

    # Supported color filters and their argument requirements
    SUPPORTED_FILTERS = {
        # No arguments
        "grayscale": 0,
        "invert": 0,
        # One argument (float)
        "set_alpha": 1,
        "set_lightness": 1,
        "set_hue": 1,
        "set_saturation": 1,
        "set_red": 1,
        "set_green": 1,
        "set_blue": 1,
        "lighten": 1,
        "darken": 1,
        "saturate": 1,
        "desaturate": 1,
        "auto_lightness": 1,
    }

    # Filters that take a hex color argument (+ optional numeric)
    COLOR_ARG_FILTERS = {"blend", "harmonize"}

    # Regex for block delimiters: <* ... *>
    _BLOCK_RE = re.compile(r'<\*\s*(.*?)\s*\*>', re.DOTALL)

    # Regex for expression tags: {{ ... }}
    _EXPR_RE = re.compile(r"\{\{\s*([^}\n]+?)\s*\}\}")

    def __init__(self, theme_data: dict[str, dict[str, str]], verbose: bool = True, default_mode: str = "dark", image_path: Optional[str] = None, scheme_type: str = "content"):
        self.theme_data = theme_data
        self.closest_color = ""
        self.verbose = verbose
        self.default_mode = default_mode
        self.image_path = image_path
        self.scheme_type = scheme_type
        self._current_file: Optional[str] = None
        self._error_count = 0
        self._colors_map: Optional[dict[str, dict[str, str]]] = None

    def _log_error(self, message: str, line_hint: str = ""):
        """Log an error to stderr."""
        self._error_count += 1
        prefix = f"[{self._current_file}] " if self._current_file else ""
        hint = f" near '{line_hint}'" if line_hint else ""
        print(f"Template error: {prefix}{message}{hint}", file=sys.stderr)

    def _log_warning(self, message: str):
        """Log a warning to stderr."""
        if self.verbose:
            prefix = f"[{self._current_file}] " if self._current_file else ""
            print(f"Template warning: {prefix}{message}", file=sys.stderr)

    # --- Colors Map ---

    def _build_colors_map(self) -> dict[str, dict[str, str]]:
        """Build iterable colors map: {name: {mode: hex_value, ...}}."""
        if self._colors_map is not None:
            return self._colors_map

        colors_map: dict[str, dict[str, str]] = {}
        all_names: set[str] = set()
        for mode_data in self.theme_data.values():
            all_names.update(mode_data.keys())

        for name in sorted(all_names):
            color_modes: dict[str, str] = {}
            for mode, mode_data in self.theme_data.items():
                if name in mode_data:
                    color_modes[mode] = mode_data[name]
            # Add "default" as alias for self.default_mode
            if self.default_mode in color_modes:
                color_modes["default"] = color_modes[self.default_mode]
            colors_map[name] = color_modes

        self._colors_map = colors_map
        return colors_map

    # --- Palette Support ---

    def _get_palette_entries(self, palette_name: str) -> list[dict[str, str]]:
        """Get tonal palette entries for iteration."""
        from .hct import Hct, TonalPalette

        TONES = [0, 5, 10, 15, 20, 25, 30, 35, 40, 50, 60, 70, 80, 90, 95, 98, 99, 100]

        palette_color_map = {
            "primary": "primary",
            "secondary": "secondary",
            "tertiary": "tertiary",
            "error": "error",
            "neutral": "surface",
            "neutral_variant": "surface_variant",
        }

        color_name = palette_color_map.get(palette_name)
        if not color_name:
            self._log_warning(f"Unknown palette: {palette_name}")
            return []

        mode_data = self.theme_data.get(self.default_mode, {})
        hex_color = mode_data.get(color_name)
        if not hex_color:
            return []

        color = Color.from_hex(hex_color)
        palette = TonalPalette.from_rgb(color.r, color.g, color.b)

        entries = []
        for tone in TONES:
            tone_hex = palette.get_hex(tone)
            # Each entry is a color modes dict (same hex for all modes in palette context)
            entries.append({"default": tone_hex, "dark": tone_hex, "light": tone_hex})

        return entries

    # --- Block Parser ---

    def _parse_template(self, text: str) -> list:
        """Parse template text into a tree of nodes."""
        tokens = self._tokenize(text)
        nodes, _ = self._parse_nodes(tokens, 0)
        return nodes

    def _tokenize(self, text: str) -> list[Union[str, tuple[str, str]]]:
        """Split text into raw text strings and ('block', content) tuples.

        Standalone block tags (only content on their line) consume the entire
        line including the trailing newline, matching matugen's behavior.
        """
        tokens = []
        last_end = 0

        for match in self._BLOCK_RE.finditer(text):
            start = match.start()
            end = match.end()

            # Check if this block tag is standalone on its line:
            # preceded only by whitespace (after newline or start), followed by optional whitespace + newline
            line_start = text.rfind('\n', last_end, start)
            line_start = line_start + 1 if line_start != -1 else (last_end if last_end <= start else 0)
            before_on_line = text[line_start:start]

            if before_on_line.strip() == '':
                # Check what follows the block tag
                after_end = end
                while after_end < len(text) and text[after_end] in (' ', '\t'):
                    after_end += 1
                if after_end < len(text) and text[after_end] == '\n':
                    # Standalone: consume leading whitespace and trailing newline
                    start = line_start
                    end = after_end + 1
                elif after_end == len(text):
                    # At end of file, still standalone
                    start = line_start
                    end = after_end

            # Text before the block
            if start > last_end:
                tokens.append(text[last_end:start])
            # The block command
            tokens.append(("block", match.group(1).strip()))
            last_end = end

        # Remaining text after last block
        if last_end < len(text):
            tokens.append(text[last_end:])

        return tokens

    def _parse_nodes(self, tokens: list, pos: int, stop_keywords: Optional[set[str]] = None) -> tuple[list, int]:
        """Parse tokens into nodes, stopping at specified keywords.

        Returns (nodes, position_after_stop_keyword).
        """
        nodes = []
        stop_keywords = stop_keywords or set()

        while pos < len(tokens):
            token = tokens[pos]

            if isinstance(token, str):
                # Raw text
                if token:
                    nodes.append(TextNode(token))
                pos += 1
            else:
                # Block command
                _, cmd = token

                # Check if this is a stop keyword
                if any(cmd.startswith(kw) for kw in stop_keywords):
                    return nodes, pos

                if cmd.startswith("for "):
                    node, pos = self._parse_for(tokens, pos)
                    nodes.append(node)
                elif cmd.startswith("if "):
                    node, pos = self._parse_if(tokens, pos)
                    nodes.append(node)
                else:
                    # Unknown block command - treat as text
                    self._log_warning(f"Unknown block command: {cmd}")
                    pos += 1

        return nodes, pos

    def _parse_for(self, tokens: list, pos: int) -> tuple[ForNode, int]:
        """Parse a for loop block starting at pos."""
        _, cmd = tokens[pos]
        pos += 1

        # Parse: for var1, var2 in iterable
        for_match = re.match(r'for\s+(.+?)\s+in\s+(.+)$', cmd)
        if not for_match:
            self._log_error(f"Invalid for syntax: {cmd}")
            return ForNode([], "", []), pos

        vars_str, iterable = for_match.groups()
        variables = [v.strip() for v in vars_str.split(',')]
        iterable = iterable.strip()

        # Parse body until endfor
        body, pos = self._parse_nodes(tokens, pos, stop_keywords={"endfor"})

        # Skip past 'endfor'
        if pos < len(tokens):
            pos += 1

        return ForNode(variables, iterable, body), pos

    def _parse_if(self, tokens: list, pos: int) -> tuple[IfNode, int]:
        """Parse an if/else/endif block starting at pos."""
        _, cmd = tokens[pos]
        pos += 1

        # Parse: if [not] {{ expr }}
        negated = False
        condition_part = cmd[3:].strip()  # Remove 'if '

        if condition_part.startswith("not "):
            negated = True
            condition_part = condition_part[4:].strip()

        # Extract expression from {{ ... }} if present
        expr_match = re.match(r'\{\{\s*(.+?)\s*\}\}', condition_part)
        if expr_match:
            condition_expr = expr_match.group(1).strip()
        else:
            condition_expr = condition_part

        # Parse then body until else or endif
        then_body, pos = self._parse_nodes(tokens, pos, stop_keywords={"else", "endif"})

        else_body = []
        if pos < len(tokens):
            _, stop_cmd = tokens[pos]
            if stop_cmd.strip() == "else":
                pos += 1
                # Parse else body until endif
                else_body, pos = self._parse_nodes(tokens, pos, stop_keywords={"endif"})

        # Skip past 'endif'
        if pos < len(tokens):
            pos += 1

        return IfNode(condition_expr, negated, then_body, else_body), pos

    # --- Node Evaluation ---

    def _evaluate_nodes(self, nodes: list, scope: VariableScope) -> str:
        """Evaluate a list of nodes with the given variable scope."""
        parts = []
        for node in nodes:
            if isinstance(node, TextNode):
                parts.append(self._resolve_text(node.text, scope))
            elif isinstance(node, ForNode):
                parts.append(self._evaluate_for(node, scope))
            elif isinstance(node, IfNode):
                parts.append(self._evaluate_if(node, scope))
        return ''.join(parts)

    def _evaluate_for(self, node: ForNode, scope: VariableScope) -> str:
        """Evaluate a for loop node."""
        iterable = self._resolve_iterable(node.iterable, scope)
        if not iterable:
            return ""

        results = []
        total = len(iterable)

        for index, item in enumerate(iterable):
            loop_meta = {
                "index": index,
                "first": index == 0,
                "last": index == total - 1,
            }

            scope.push({"loop": loop_meta})

            if isinstance(item, tuple) and len(item) == 2:
                # Map iteration: (key, value)
                if len(node.variables) >= 2:
                    scope.set(node.variables[0], item[0])
                    scope.set(node.variables[1], item[1])
                elif len(node.variables) == 1:
                    scope.set(node.variables[0], item[0])
            else:
                # Array or range iteration
                if node.variables:
                    scope.set(node.variables[0], item)

            results.append(self._evaluate_nodes(node.body, scope))
            scope.pop()

        return ''.join(results)

    def _evaluate_if(self, node: IfNode, scope: VariableScope) -> str:
        """Evaluate an if/else node."""
        condition_value = self._resolve_expression(node.condition_expr, scope)
        is_truthy = self._is_truthy(condition_value)

        if node.negated:
            is_truthy = not is_truthy

        if is_truthy:
            return self._evaluate_nodes(node.then_body, scope)
        else:
            return self._evaluate_nodes(node.else_body, scope)

    def _is_truthy(self, value: Any) -> bool:
        """Determine if a value is truthy."""
        if value is None:
            return False
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return value != 0
        s = str(value).strip().lower()
        return s not in ("", "false", "0", "none")

    # --- Iterable Resolution ---

    def _resolve_iterable(self, iterable_expr: str, scope: VariableScope) -> list:
        """Resolve an iterable expression to a list of items."""
        # Range: "0..10" or "-5..5"
        range_match = re.match(r'^(-?\d+)\.\.(-?\d+)$', iterable_expr)
        if range_match:
            start, end = int(range_match.group(1)), int(range_match.group(2))
            return list(range(start, end))

        # Colors map: "colors"
        if iterable_expr == "colors":
            colors_map = self._build_colors_map()
            return list(colors_map.items())

        # Palette: "palettes.primary" etc.
        if iterable_expr.startswith("palettes."):
            palette_name = iterable_expr.split('.', 1)[1]
            entries = self._get_palette_entries(palette_name)
            # Return as list of dicts (each entry is a color modes dict)
            return entries

        # Check scope for iterable variable
        val = scope.get(iterable_expr)
        if val is not None:
            if isinstance(val, dict):
                return list(val.items())
            if isinstance(val, (list, tuple)):
                return list(val)

        self._log_warning(f"Unknown iterable: {iterable_expr}")
        return []

    # --- Expression Resolution ---

    def _resolve_text(self, text: str, scope: VariableScope) -> str:
        """Resolve all {{ expr }} tags in a text segment."""
        def replace(match):
            expr = match.group(1).strip()
            return str(self._resolve_expression(expr, scope))

        return self._EXPR_RE.sub(replace, text)

    def _resolve_expression(self, expr: str, scope: VariableScope) -> Any:
        """Resolve an expression, checking scope variables first, then colors."""
        # Split by pipe for filters
        parts = self._split_pipes(expr)

        if not parts:
            return ""

        base = parts[0].strip()
        filters = [p.strip() for p in parts[1:]]

        # Try scope resolution first
        resolved = self._resolve_from_scope(base, scope)
        if resolved is not None:
            result_str = str(resolved)
            for filter_str in filters:
                result_str = self._apply_string_or_color_filter(result_str, filter_str, expr)
            return result_str

        # Handle {{image}} tag - resolves to source image path
        if base == 'image':
            result_str = self.image_path or ""
            for filter_str in filters:
                result_str = self._apply_string_or_color_filter(result_str, filter_str, expr)
            return result_str

        # Fall back to colors.name.mode.format parsing
        if base.startswith('colors.'):
            return self._process_color_expression(base, filters, expr)

        # Unknown expression - return as-is
        return f"{{{{{expr}}}}}"

    def _split_pipes(self, expr: str) -> list[str]:
        """Split expression by pipe, respecting quoted strings."""
        parts = []
        current = []
        in_quotes = False
        quote_char = None

        for char in expr:
            if char in ('"', "'") and not in_quotes:
                in_quotes = True
                quote_char = char
                current.append(char)
            elif char == quote_char and in_quotes:
                in_quotes = False
                quote_char = None
                current.append(char)
            elif char == '|' and not in_quotes:
                parts.append(''.join(current))
                current = []
            else:
                current.append(char)

        if current:
            parts.append(''.join(current))

        return parts

    def _resolve_from_scope(self, base: str, scope: VariableScope) -> Optional[Any]:
        """Resolve a dotted path from scope variables."""
        if not scope.is_active:
            return None

        parts = base.split('.')
        first = parts[0]

        val = scope.get(first)
        if val is None:
            return None

        # Navigate dotted path
        for i, part in enumerate(parts[1:], 1):
            if isinstance(val, dict) and part in val:
                val = val[part]
            elif isinstance(val, str) and val.startswith('#') and part in KNOWN_FORMATS:
                # It's a hex color string and remaining part is a format specifier
                color = Color.from_hex(val)
                return self._format_color(color, part)
            else:
                return None

        # If the final value is a hex color string, return it as-is
        return val

    def _process_color_expression(self, base: str, filters: list[str], raw_expr: str) -> str:
        """Process a colors.name.mode.format expression with optional filters."""
        base_match = re.match(r'^colors\.([a-z_0-9]+)\.([a-z_0-9]+)\.([a-z_0-9]+)$', base)

        if not base_match:
            self._log_error(f"Invalid syntax '{base}'. Expected: colors.<name>.<mode>.<format>", raw_expr)
            return f"{{{{{raw_expr}}}}}"

        color_name, mode, format_type = base_match.groups()

        hex_color = self._get_hex_color(color_name, mode)
        if not hex_color:
            return f"{{{{UNKNOWN:{color_name}.{mode}}}}}"

        color = Color.from_hex(hex_color)

        # Apply color filters
        for filter_str in filters:
            filter_name, arg = self._parse_filter(filter_str)
            if filter_name:
                if filter_name == "replace":
                    # Replace works on the formatted string, apply after formatting
                    formatted = self._format_color(color, format_type)
                    return self._apply_replace(formatted, arg, raw_expr)
                elif filter_name in self.COLOR_ARG_FILTERS:
                    hex_result = self._apply_color_arg_filter(color.to_hex(), filter_name, arg, raw_expr)
                    color = Color.from_hex(hex_result)
                elif filter_name == "to_color":
                    pass  # Already a color, no-op
                elif filter_name in self.SUPPORTED_FILTERS:
                    color = self._apply_filter(color, filter_name, arg, raw_expr)
                elif filter_name in ("lower_case", "camel_case", "pascal_case", "snake_case", "kebab_case"):
                    # String case filters apply to formatted output
                    formatted = self._format_color(color, format_type)
                    return self._apply_string_or_color_filter(formatted, filter_str, raw_expr)
                else:
                    self._log_warning(f"Unknown filter '{filter_name}'")

        return self._format_color(color, format_type)

    # --- Color Access ---

    def _get_hex_color(self, color_name: str, mode: str) -> Optional[str]:
        """Get raw hex color value for a color name and mode."""
        key = self.COLOR_ALIASES.get(color_name, color_name)

        if mode == "default":
            mode_data = self.theme_data.get(self.default_mode) or self.theme_data.get("dark") or self.theme_data.get("light")
        else:
            mode_data = self.theme_data.get(mode)

        if not mode_data:
            self._log_error(f"Unknown mode '{mode}'", f"colors.{color_name}.{mode}")
            return None

        hex_color = mode_data.get(key)
        if not hex_color:
            self._log_error(f"Unknown color '{key}'", f"colors.{color_name}.{mode}")
            return None

        return hex_color

    def _format_color(self, color: Color, format_type: str) -> str:
        """Format a Color object to the requested format string."""
        if format_type == "hex":
            return color.to_hex()
        elif format_type == "hex_stripped":
            return color.to_hex().lstrip('#')
        elif format_type == "rgb":
            return f"rgb({color.r}, {color.g}, {color.b})"
        elif format_type == "rgba":
            alpha = getattr(color, 'alpha', 1.0)
            return f"rgba({color.r}, {color.g}, {color.b}, {alpha})"
        elif format_type == "hsl":
            h, s, l = color.to_hsl()
            return f"hsl({int(h)}, {int(s * 100)}%, {int(l * 100)}%)"
        elif format_type == "hsla":
            h, s, l = color.to_hsl()
            alpha = getattr(color, 'alpha', 1.0)
            return f"hsla({int(h)}, {int(s * 100)}%, {int(l * 100)}%, {alpha})"
        elif format_type == "hue":
            h, _, _ = color.to_hsl()
            return str(int(h))
        elif format_type == "saturation":
            _, s, _ = color.to_hsl()
            return str(int(s * 100))
        elif format_type == "lightness":
            _, _, l = color.to_hsl()
            return str(int(l * 100))
        elif format_type == "red":
            return str(color.r)
        elif format_type == "green":
            return str(color.g)
        elif format_type == "blue":
            return str(color.b)
        elif format_type == "alpha":
            return str(getattr(color, 'alpha', 1.0))
        else:
            self._log_error(f"Unknown format '{format_type}'")
            return color.to_hex()

    # --- Filters ---

    def _parse_filter(self, filter_str: str) -> tuple[str, Optional[str]]:
        """Parse a filter string into (name, argument).

        Supports both syntaxes:
          | set_alpha 0.5       (space-separated)
          | set_alpha: 0.5      (colon-separated, matugen-style)
          | replace: "_", "-"   (colon with quoted args)
        """
        filter_str = filter_str.strip()

        # Check for colon syntax: name: args
        colon_match = re.match(r'^([a-z_]+)\s*:\s*(.+)$', filter_str)
        if colon_match:
            return colon_match.group(1), colon_match.group(2).strip()

        # Space syntax: name arg
        if ' ' in filter_str:
            name, arg = filter_str.split(None, 1)
            return name.strip(), arg.strip()

        return filter_str, None

    def _apply_string_or_color_filter(self, value: str, filter_str: str, raw_expr: str) -> str:
        """Apply a filter to a string value (may be a color hex or plain string)."""
        name, arg = self._parse_filter(filter_str)

        if name == "replace":
            return self._apply_replace(value, arg, raw_expr)

        # String case transforms (work on any string)
        if name == "lower_case":
            return value.lower()
        if name == "camel_case":
            return self._to_camel_case(value)
        if name == "pascal_case":
            return self._to_pascal_case(value)
        if name == "snake_case":
            return self._to_snake_case(value)
        if name == "kebab_case":
            return self._to_kebab_case(value)

        # to_color: treat value as color string (pass-through, validates hex)
        if name == "to_color":
            if value.startswith('#') and len(value) in (7, 9):
                return value
            self._log_error(f"to_color: value '{value}' is not a valid hex color", raw_expr)
            return value

        # Color-arg filters (blend, harmonize) - need hex color argument
        if name in self.COLOR_ARG_FILTERS:
            if not (value.startswith('#') and len(value) == 7):
                self._log_error(f"Filter '{name}' requires a hex color value", raw_expr)
                return value
            return self._apply_color_arg_filter(value, name, arg, raw_expr)

        # Try as color filter if value looks like a hex color
        if name in self.SUPPORTED_FILTERS and value.startswith('#') and len(value) == 7:
            color = Color.from_hex(value)
            color = self._apply_filter(color, name, arg, raw_expr)
            return color.to_hex()

        self._log_warning(f"Cannot apply filter '{name}' to non-color value")
        return value

    def _apply_color_arg_filter(self, value: str, name: str, arg: Optional[str], raw_expr: str) -> str:
        """Apply blend or harmonize filter (takes hex color argument)."""
        if not arg:
            self._log_error(f"Filter '{name}' requires a color argument", raw_expr)
            return value

        # Parse arguments: "#hexcolor", amount (for blend) or just "#hexcolor" (for harmonize)
        # Support both quoted and unquoted hex
        hex_match = re.match(r'["\']?(#[0-9a-fA-F]{6})["\']?\s*(?:,\s*(.+))?', arg)
        if not hex_match:
            self._log_error(f"Filter '{name}' requires a hex color argument, got '{arg}'", raw_expr)
            return value

        target_hex = hex_match.group(1)
        extra_arg = hex_match.group(2)

        src = Color.from_hex(value)
        target = Color.from_hex(target_hex)

        src_hct = Hct.from_rgb(src.r, src.g, src.b)
        target_hct = Hct.from_rgb(target.r, target.g, target.b)

        if name == "blend":
            # Blend hue in HCT space by amount, keep source chroma/tone
            if not extra_arg:
                self._log_error("blend filter requires amount argument: blend: \"#hex\", 0.5", raw_expr)
                return value
            try:
                amount = float(extra_arg.strip().strip('"\''))
            except ValueError:
                self._log_error(f"blend amount must be numeric, got '{extra_arg}'", raw_expr)
                return value
            amount = max(0.0, min(1.0, amount))

            # Shortest arc hue interpolation
            diff = target_hct.hue - src_hct.hue
            if diff > 180.0:
                diff -= 360.0
            elif diff < -180.0:
                diff += 360.0
            new_hue = (src_hct.hue + diff * amount) % 360.0
            result_hct = Hct(new_hue, src_hct.chroma, src_hct.tone)

        elif name == "harmonize":
            # M3 harmonize: rotate hue toward target by min(diff * 0.5, 15°)
            diff = target_hct.hue - src_hct.hue
            if diff > 180.0:
                diff -= 360.0
            elif diff < -180.0:
                diff += 360.0
            max_rotation = 15.0
            rotation = min(abs(diff) * 0.5, max_rotation)
            if diff < 0:
                rotation = -rotation
            new_hue = (src_hct.hue + rotation) % 360.0
            result_hct = Hct(new_hue, src_hct.chroma, src_hct.tone)
        else:
            return value

        r, g, b = result_hct.to_rgb()
        return Color(r, g, b).to_hex()

    @staticmethod
    def _split_words(s: str) -> list[str]:
        """Split a string into words for case conversion."""
        # Handle camelCase/PascalCase boundaries
        s = re.sub(r'([a-z])([A-Z])', r'\1_\2', s)
        # Split on non-alphanumeric
        return [w for w in re.split(r'[^a-zA-Z0-9]+', s) if w]

    def _to_camel_case(self, s: str) -> str:
        words = self._split_words(s)
        if not words:
            return s
        return words[0].lower() + ''.join(w.capitalize() for w in words[1:])

    def _to_pascal_case(self, s: str) -> str:
        words = self._split_words(s)
        if not words:
            return s
        return ''.join(w.capitalize() for w in words)

    def _to_snake_case(self, s: str) -> str:
        words = self._split_words(s)
        return '_'.join(w.lower() for w in words)

    def _to_kebab_case(self, s: str) -> str:
        words = self._split_words(s)
        return '-'.join(w.lower() for w in words)

    def _apply_replace(self, value: str, args: Optional[str], raw_expr: str) -> str:
        """Apply the replace filter: | replace: "search", "replacement" """
        if not args:
            self._log_error("replace filter requires arguments", raw_expr)
            return value

        # Parse quoted arguments: "search", "replacement"
        match = re.match(r'"([^"]*?)"\s*,\s*"([^"]*?)"', args)
        if match:
            find_str, replace_str = match.groups()
            return value.replace(find_str, replace_str)

        # Try single-quoted: 'search', 'replacement'
        match = re.match(r"'([^']*?)'\s*,\s*'([^']*?)'", args)
        if match:
            find_str, replace_str = match.groups()
            return value.replace(find_str, replace_str)

        self._log_error(f"replace filter syntax: replace: \"find\", \"replacement\"", raw_expr)
        return value

    def _apply_filter(self, color: Color, filter_name: str, arg: Optional[str], raw_expr: str) -> Color:
        """Apply a single color filter."""
        if filter_name not in self.SUPPORTED_FILTERS:
            supported = ", ".join(sorted(self.SUPPORTED_FILTERS.keys()))
            self._log_error(f"Unknown filter '{filter_name}'. Supported: {supported}", raw_expr)
            return color

        expected_args = self.SUPPORTED_FILTERS[filter_name]

        if expected_args > 0 and arg is None:
            self._log_error(f"Filter '{filter_name}' requires an argument", raw_expr)
            return color
        if expected_args == 0 and arg is not None:
            self._log_warning(f"Filter '{filter_name}' ignores argument '{arg}'")

        num_arg = None
        if expected_args > 0:
            try:
                num_arg = float(arg)
            except (ValueError, TypeError):
                self._log_error(f"Filter '{filter_name}' requires numeric argument, got '{arg}'", raw_expr)
                return color

        h, s, l = color.to_hsl()

        if filter_name == "grayscale":
            gray = int(0.299 * color.r + 0.587 * color.g + 0.114 * color.b)
            result = Color(gray, gray, gray)
        elif filter_name == "invert":
            result = Color(255 - color.r, 255 - color.g, 255 - color.b)
        elif filter_name == "set_alpha":
            result = Color(color.r, color.g, color.b)
            result.alpha = max(0.0, min(1.0, num_arg))
        elif filter_name == "set_lightness":
            new_l = max(0.0, min(1.0, num_arg / 100.0))
            result = Color.from_hsl(h, s, new_l)
        elif filter_name == "set_hue":
            new_h = num_arg % 360
            result = Color.from_hsl(new_h, s, l)
        elif filter_name == "set_saturation":
            new_s = max(0.0, min(1.0, num_arg / 100.0))
            result = Color.from_hsl(h, new_s, l)
        elif filter_name == "lighten":
            new_l = max(0.0, min(1.0, l + num_arg / 100.0))
            result = Color.from_hsl(h, s, new_l)
        elif filter_name == "darken":
            new_l = max(0.0, min(1.0, l - num_arg / 100.0))
            result = Color.from_hsl(h, s, new_l)
        elif filter_name == "saturate":
            new_s = max(0.0, min(1.0, s + num_arg / 100.0))
            result = Color.from_hsl(h, new_s, l)
        elif filter_name == "desaturate":
            new_s = max(0.0, min(1.0, s - num_arg / 100.0))
            result = Color.from_hsl(h, new_s, l)
        elif filter_name == "auto_lightness":
            # If lightness < 50%, lighten; otherwise darken (push toward mid-lightness)
            if l < 0.5:
                new_l = max(0.0, min(1.0, l + num_arg / 100.0))
            else:
                new_l = max(0.0, min(1.0, l - num_arg / 100.0))
            result = Color.from_hsl(h, s, new_l)
        elif filter_name == "set_red":
            result = Color(max(0, min(255, int(num_arg))), color.g, color.b)
        elif filter_name == "set_green":
            result = Color(color.r, max(0, min(255, int(num_arg))), color.b)
        elif filter_name == "set_blue":
            result = Color(color.r, color.g, max(0, min(255, int(num_arg))))
        else:
            result = color

        if hasattr(color, 'alpha') and not hasattr(result, 'alpha'):
            result.alpha = color.alpha

        return result

    # --- Main Render Methods ---

    def render(self, template_text: str) -> str:
        """Render a template string, processing blocks and expressions."""
        self._error_count = 0

        # Parse template into node tree
        nodes = self._parse_template(template_text)

        # Evaluate with empty scope
        scope = VariableScope()
        result = self._evaluate_nodes(nodes, scope)

        if self.closest_color:
            result = self._substitute_closest_color(result)

        # Process escape sequences (matugen-compatible)
        result = result.replace('\\\\', '\\')

        if self._error_count > 0:
            print(f"Template rendering completed with {self._error_count} error(s)", file=sys.stderr)

        return result

    def render_file(self, input_path: Path, output_path: Path) -> bool:
        """Render a template file to an output path.

        Returns True if successful, False if skipped due to errors.
        """
        self._current_file = str(input_path)
        success = False
        try:
            template_text = input_path.read_text()
            rendered_text = self.render(template_text)

            if self._error_count > 0:
                print(f"Skipping {output_path}: template has {self._error_count} error(s)", file=sys.stderr)
            else:
                output_path.parent.mkdir(parents=True, exist_ok=True)
                output_path.write_text(rendered_text)
                success = True
        except FileNotFoundError:
            self._log_error(f"Template file not found: {input_path}")
        except PermissionError:
            self._log_error(f"Permission denied: {output_path}")
        except Exception as e:
            self._log_error(f"Unexpected error: {e}")
        finally:
            self._current_file = None
        return success

    # --- Custom Colors ---

    # Standard M3 tone mappings for primary color group
    _CUSTOM_COLOR_TONES = {
        "dark": {
            "color": 80,
            "on_color": 20,
            "color_container": 30,
            "on_color_container": 90,
        },
        "light": {
            "color": 40,
            "on_color": 100,
            "color_container": 90,
            "on_color_container": 10,
        },
    }

    def _apply_custom_colors(self, custom_colors: dict[str, Any]):
        """Generate and merge custom color tokens into theme_data.

        Matches matugen's [config.custom_colors] behavior:
        - Each custom color generates 6 tokens per mode
        - Optional blend (harmonize toward source color)
        - Uses the same scheme type as the main theme for palette generation
        - Tokens: {name}_source, {name}_value, {name}, on_{name},
          {name}_container, on_{name}_container
        """
        from .hct import Hct, TonalPalette
        from .material import (
            SchemeTonalSpot, SchemeFruitSalad, SchemeRainbow,
            SchemeContent, SchemeMonochrome
        )

        SCHEME_CLASSES = {
            "tonal-spot": SchemeTonalSpot,
            "content": SchemeContent,
            "fruit-salad": SchemeFruitSalad,
            "rainbow": SchemeRainbow,
            "monochrome": SchemeMonochrome,
        }
        scheme_class = SCHEME_CLASSES.get(self.scheme_type, SchemeContent)

        # Get source color for harmonization (primary from default mode)
        source_hex = None
        mode_data = self.theme_data.get(self.default_mode, {})
        source_hex = mode_data.get("primary") or mode_data.get("source_color")

        for name, config in custom_colors.items():
            # Parse config: either a string "#hex" or {color: "#hex", blend: bool}
            if isinstance(config, str):
                color_hex = config
                blend = True
            elif isinstance(config, dict):
                color_hex = config.get("color", "")
                blend = config.get("blend", True)
            else:
                self._log_warning(f"Invalid custom_color config for '{name}': {config}")
                continue

            # Validate hex color
            if not (color_hex.startswith('#') and len(color_hex) == 7):
                self._log_error(f"Custom color '{name}' has invalid hex: '{color_hex}'")
                continue

            original_color = Color.from_hex(color_hex)

            # Optionally harmonize toward source color
            if blend and source_hex:
                src = Color.from_hex(color_hex)
                target = Color.from_hex(source_hex)
                src_hct = Hct.from_rgb(src.r, src.g, src.b)
                target_hct = Hct.from_rgb(target.r, target.g, target.b)

                # M3 harmonize: rotate hue toward target by min(diff * 0.5, 15°)
                diff = target_hct.hue - src_hct.hue
                if diff > 180.0:
                    diff -= 360.0
                elif diff < -180.0:
                    diff += 360.0
                max_rotation = 15.0
                rotation = min(abs(diff) * 0.5, max_rotation)
                if diff < 0:
                    rotation = -rotation
                new_hue = (src_hct.hue + rotation) % 360.0
                harmonized_hct = Hct(new_hue, src_hct.chroma, src_hct.tone)
                r, g, b = harmonized_hct.to_rgb()
                palette_color = Color(r, g, b)
            else:
                palette_color = original_color

            # Generate palette using the scheme class (matches matugen behavior)
            palette_hct = Hct.from_rgb(palette_color.r, palette_color.g, palette_color.b)
            scheme = scheme_class(palette_hct)
            palette = scheme.primary_palette

            # Generate tokens for each mode
            for mode in self.theme_data:
                tones = self._CUSTOM_COLOR_TONES.get(mode)
                if not tones:
                    continue

                # Source/value tokens (always the original unharmonized color)
                self.theme_data[mode][f"{name}_source"] = original_color.to_hex()
                self.theme_data[mode][f"{name}_value"] = original_color.to_hex()

                # Primary role tokens from the tonal palette
                self.theme_data[mode][name] = palette.get_hex(tones["color"])
                self.theme_data[mode][f"on_{name}"] = palette.get_hex(tones["on_color"])
                self.theme_data[mode][f"{name}_container"] = palette.get_hex(tones["color_container"])
                self.theme_data[mode][f"on_{name}_container"] = palette.get_hex(tones["on_color_container"])

        # Invalidate colors map cache so new colors appear in iterations
        self._colors_map = None

    def _substitute_closest_color(self, text: str) -> str:
        """Substitute {{closest_color}} in text."""
        return re.sub(r"\{\{\s*closest_color\s*\}\}", self.closest_color, text)

    def process_config_file(self, config_path: Path):
        """Process Matugen TOML configuration file."""
        if not tomllib:
            print("Error: tomllib module not available (requires Python 3.11+)", file=sys.stderr)
            return

        try:
            with open(config_path, "rb") as f:
                data = tomllib.load(f)

            # Apply custom colors before rendering templates
            config_section = data.get("config", {})
            custom_colors = config_section.get("custom_colors")
            if custom_colors:
                self._apply_custom_colors(custom_colors)

            templates = data.get("templates", {})
            for name, template in templates.items():
                input_path = template.get("input_path")
                output_path = template.get("output_path")

                if not input_path or not output_path:
                    print(f"Warning: Template '{name}' missing input_path or output_path", file=sys.stderr)
                    continue

                # Handle closest_color if configured (matugen-compatible)
                # Reset for each template to avoid state pollution between templates
                self.closest_color = ""
                colors_to_compare = template.get("colors_to_compare")
                compare_to = template.get("compare_to")

                if colors_to_compare and compare_to:
                    rendered_compare_to = self.render(compare_to)
                    self.closest_color = find_closest_color(rendered_compare_to, colors_to_compare)

                self.render_file(Path(input_path).expanduser(), Path(output_path).expanduser())

                # Execute pre_hook if specified
                pre_hook = template.get("pre_hook")
                if pre_hook:
                    import subprocess
                    if self.closest_color:
                        pre_hook = self._substitute_closest_color(pre_hook)
                    pre_hook = self.render(pre_hook)
                    try:
                        subprocess.run(pre_hook, shell=True, check=False)
                    except Exception as e:
                        print(f"Error running pre_hook for {name}: {e}", file=sys.stderr)

                # Execute post_hook if specified
                post_hook = template.get("post_hook")
                if post_hook:
                    import subprocess
                    if self.closest_color:
                        post_hook = self._substitute_closest_color(post_hook)
                    post_hook = self.render(post_hook)
                    try:
                        subprocess.run(post_hook, shell=True, check=False)
                    except Exception as e:
                        print(f"Error running post_hook for {name}: {e}", file=sys.stderr)

        except FileNotFoundError:
            print(f"Error: Config file not found: {config_path}", file=sys.stderr)
        except Exception as e:
            print(f"Error processing config file {config_path}: {e}", file=sys.stderr)
