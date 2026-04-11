# Theming Templates

`TemplateEngine` renders text and files from a theme token map. It supports inline expressions, block syntax for loops and conditionals, color formatting, filter pipelines, and TOML-driven batch processing.

This document describes the supported template syntax and data model.

## Scope

`TemplateEngine` is responsible for:

- Rendering template strings and files
- Reading values from theme token maps
- Applying color and string filters
- Executing loops and conditionals
- Processing TOML template configs
- Computing custom colors and `closest_color`

It is not responsible for image loading or palette extraction.

## Syntax

### Expressions

Inline expressions use:

```text
{{ ... }}
```

Examples:

```text
{{ colors.primary.default.hex }}
{{ colors.surface.dark.rgb }}
{{ mode }}
{{ image }}
```

### Blocks

Control blocks use:

```text
<* ... *>
```

Supported block tags:

- `for`
- `if`
- `else`
- `endif`
- `endfor`

Examples:

```text
<* for name, value in colors *>
{{ name }}={{ value.default.hex }}
<* endfor *>
```

```text
<* if {{ loop.first }} *>
first
<* else *>
not first
<* endif *>
```

### Standalone Block Trimming

If a block tag appears alone on a line, with only whitespace around it, that whole line is removed from the rendered output. This matters for whitespace-sensitive templates.

## Data Model

### Theme Colors

Colors are accessed with:

```text
{{ colors.<name>.<mode>.<format> }}
```

Examples:

```text
{{ colors.primary.default.hex }}
{{ colors.surface.light.hsl }}
{{ colors.terminal_foreground.default.hex_stripped }}
```

### Modes

Supported modes:

- `dark`
- `light`
- `default`

`default` resolves to the configured default mode.

### Special Values

The following values are available directly:

- `mode`
- `image`
- `closest_color`

`mode` is the current default mode.

`image` is the source image path when rendering from an image-driven theme.

`closest_color` is populated during config-driven rendering when `compare_to` and `colors_to_compare` are used.

### Color Aliases

Supported aliases:

- `hover` -> `surface_container_high`
- `on_hover` -> `on_surface`

## Formats

Supported output formats:

- `hex`
- `hex_stripped`
- `rgb`
- `rgb_csv`
- `rgba`
- `hsl`
- `hsla`
- `red`
- `green`
- `blue`
- `alpha`
- `hue`
- `saturation`
- `lightness`

Format behavior:

- `hex`: `#rrggbb`
- `hex_stripped`: `rrggbb`
- `rgb`: `rgb(r, g, b)`
- `rgb_csv`: `r,g,b`
- `rgba`: `rgba(r, g, b, a)`
- `hsl`: `hsl(h, s%, l%)`
- `hsla`: `hsla(h, s%, l%, a)`
- `red`, `green`, `blue`: integer channels
- `alpha`: floating-point alpha
- `hue`: integer hue
- `saturation`, `lightness`: integer percentages

## Filters

Filters are chained with pipe syntax:

```text
{{ colors.primary.default.hex | grayscale }}
{{ colors.primary.default.hex | set_alpha 0.5 }}
{{ colors.primary.default.hex | blend: "#ff0000", 0.5 }}
```

Supported syntaxes:

- `| filter`
- `| filter arg`
- `| filter: arg`

### Color Filters

These operate on colors:

- `grayscale`
- `invert`
- `set_alpha`
- `set_lightness`
- `set_hue`
- `set_saturation`
- `set_red`
- `set_green`
- `set_blue`
- `lighten`
- `darken`
- `saturate`
- `desaturate`
- `auto_lightness`

### Color-Argument Filters

These accept another color:

- `blend`
- `harmonize`
- `to_color`

Examples:

```text
{{ colors.primary.default.hex | blend: "#ff0000", 0.5 }}
{{ colors.primary.default.hex | harmonize: "#00ff88" }}
{{ "#ffaa00" | to_color | darken 0.1 }}
```

### String Filters

These operate on strings:

- `replace`
- `lower_case`
- `camel_case`
- `pascal_case`
- `snake_case`
- `kebab_case`

Examples:

```text
{{ mode | replace: "dark", "night" }}
{{ "surface container high" | snake_case }}
```

## Control Flow

### For Loops

Supported forms:

```text
<* for item in iterable *>
...
<* endfor *>
```

```text
<* for key, value in colors *>
...
<* endfor *>
```

### Conditionals

Supported forms:

```text
<* if {{ expr }} *>
...
<* endif *>
```

```text
<* if not {{ expr }} *>
...
<* else *>
...
<* endif *>
```

Truthiness rules:

- `false` is false
- numeric `0` is false
- empty strings are false
- case-insensitive `"false"`, `"0"`, and `"none"` are false
- empty arrays and maps are false
- everything else is true

## Iterables

Supported iterable expressions:

- `colors`
- `palettes.primary`
- `palettes.secondary`
- `palettes.tertiary`
- `palettes.error`
- `palettes.neutral`
- `palettes.neutral_variant`
- numeric ranges like `0..10` and `-5..5`
- arrays and maps from the current scope

### `colors`

`colors` iterates all available token names and their mode maps:

```text
<* for name, value in colors *>
{{ name }}={{ value.default.hex }}
<* endfor *>
```

### `palettes.*`

`palettes.*` iterates derived tone steps for the selected palette family.

Supported families:

- `primary`
- `secondary`
- `tertiary`
- `error`
- `neutral`
- `neutral_variant`

Tone values:

- `0`
- `5`
- `10`
- `15`
- `20`
- `25`
- `30`
- `35`
- `40`
- `50`
- `60`
- `70`
- `80`
- `90`
- `95`
- `98`
- `99`
- `100`

## Loop Metadata

Inside `for` loops, the `loop` object provides:

- `loop.index`
- `loop.first`
- `loop.last`

`loop.index` is zero-based.

## File Rendering

When rendering files, `TemplateEngine`:

- reads the template file
- renders the output
- creates parent directories when needed
- skips rewriting unchanged files
- reports render failures through the file render result

Skipping unchanged output avoids unnecessary timestamp updates and downstream reloads.

## Config Processing

`TemplateEngine` supports TOML-driven template processing.

Top-level sections:

- `[config]`
- `[templates]`

### Custom Colors

`[config.custom_colors]` supports both forms:

```toml
[config.custom_colors]
brand = "#ff0000"
```

```toml
[config.custom_colors.brand]
color = "#ff0000"
blend = true
```

Generated tokens per mode:

- `{name}_source`
- `{name}_value`
- `{name}`
- `on_{name}`
- `{name}_container`
- `on_{name}_container`

### Template Entries

Each template entry supports:

- `input_path`
- `output_path`
- `colors_to_compare`
- `compare_to`
- `pre_hook`
- `post_hook`

### Closest Color

`compare_to` and `colors_to_compare` can be used to compute `closest_color`.

Behavior:

- `compare_to` is rendered first
- `colors_to_compare` provides named comparison candidates
- the closest candidate becomes available as `{{ closest_color }}`

### Hooks

Supported hooks:

- `pre_hook`
- `post_hook`

Behavior:

- hook commands are rendered through the template engine first
- hooks run only when the target file was written
- `closest_color` is available inside hooks

## Terminal Tokens

Themes may expose flattened terminal tokens such as:

- `terminal_foreground`
- `terminal_background`
- `terminal_cursor`
- `terminal_cursor_text`
- `terminal_selection_fg`
- `terminal_selection_bg`
- `terminal_normal_black`
- `terminal_normal_red`
- `terminal_normal_green`
- `terminal_normal_yellow`
- `terminal_normal_blue`
- `terminal_normal_magenta`
- `terminal_normal_cyan`
- `terminal_normal_white`
- `terminal_bright_black`
- `terminal_bright_red`
- `terminal_bright_green`
- `terminal_bright_yellow`
- `terminal_bright_blue`
- `terminal_bright_magenta`
- `terminal_bright_cyan`
- `terminal_bright_white`

These are accessed like any other color token:

```text
{{ colors.terminal_background.default.hex }}
{{ colors.terminal_normal_red.default.rgb }}
```

## CLI Usage

Template rendering is available through `noctalia theme`.

Render one file:

```sh
noctalia theme <image> -r input.txt:output.txt
```

Render from a precomputed theme JSON:

```sh
noctalia theme --theme-json theme.json -r input.txt:output.txt
```

Process a TOML config:

```sh
noctalia theme <image> -c templates.toml
```

Set the default template mode:

```sh
noctalia theme <image> --default-mode light -r input.txt:output.txt
```
