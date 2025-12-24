# icon-resolver

A Rust service for resolving freedesktop icon theme icons. Resolves icon names to file paths following the XDG Icon Theme Specification.

## Problem

Qt's icon lookup searches `XDG_DATA_DIRS` in order and may find fallback icons (like hicolor) before themed icons, causing incorrect icons to be displayed. Additionally, building an icon cache from scratch takes several seconds on first run (varies by theme size), but subsequent runs load from persistent cache in milliseconds.

## Solution

This service:
1. Reads `QT_ICON_THEME` and `USER` environment variables at startup
2. Loads persistent cache from disk (~8ms) if available, or builds cache if missing/stale (varies by theme size)
3. Builds icon cache by scanning theme directories in priority order
4. Follows the theme's `Inherits=` chain from `index.theme` files
5. Maps icon names to full file paths with variation matching
6. Provides IPC via stdin/stdout JSON
7. Saves cache to disk for faster subsequent runs

## Performance

- **Cache load**: ~8ms (from disk, when cache exists for current theme)
- **Cache build**: Varies by theme size (parallelized with Rayon):
  - Small themes (hicolor, ~34 icons): <50ms
  - Medium themes (Adwaita, ~1000 icons): ~50-100ms
  - Large themes (Papirus-Dark, ~18000 icons): ~300-400ms
- **Runtime lookup**: ~150ns - 8µs per icon (in-memory hash map lookup)
- **Theme switching**: Cache is per-theme, so switching themes rebuilds the cache for the new theme

**Note**: The cache file stores one theme at a time. When switching themes, the cache for the previous theme is invalidated and rebuilt for the new theme. This means theme switches trigger a cache rebuild, but subsequent uses of the same theme load instantly from cache.

**Optimization**: Directory scanning is parallelized using Rayon, providing 5-10x speedup on multi-core systems. Large themes that previously took 2-4 seconds now build in under 400ms.

## Architecture

```
src/
├── lib.rs    # Icon resolution logic
└── main.rs   # IPC wrapper that handles stdin/stdout JSON protocol
```

**Why separate lib.rs and main.rs?**
- `lib.rs`: Contains all icon resolution logic
- `main.rs`: Thin IPC wrapper that handles stdin/stdout JSON protocol
- This separation keeps code organized and enables reuse

## Persistent Cache

**Cache Location:** `~/.cache/noctalia/icon-cache.json`

**Cache Format:**
```json
{
  "metadata": {
    "theme": "Papirus-Dark",
    "base_path": "/usr/share/icons",
    "additional_paths": ["/home/user/.local/share/icons"],
    "cache_time": 1702345678,
    "icon_count": 21643
  },
  "icons": {
    "zen-browser": {
      "path": "/path/to/zen-browser.svg",
      "size": 128,
      "is_svg": true,
      "theme_priority": 0
    }
  }
}
```

**Cache Invalidation:**
Cache is automatically invalidated and rebuilt if:
- Theme name changes (`QT_ICON_THEME` environment variable)
- Base path changes
- Additional paths (`XDG_DATA_DIRS`) change
- Theme's `index.theme` file is modified after cache creation

## Building

```bash
cd Services/Icons/icon-resolver
cargo build --release
```

The binary will be at `target/release/icon-resolver`.

## IPC Protocol

The service communicates via stdin/stdout using JSON messages. Each request is a single JSON object on one line, and each response is a single JSON object on one line.

### Resolve Request

**Input:**
```json
{"type": "resolve", "name": "com.mitchellh.ghostty"}
```

**Output:**
```json
{"path": "/usr/share/icons/Papirus-Dark/128x128/apps/com.mitchellh.ghostty.svg"}
```

If the icon is not found:
```json
{"path": ""}
```

### Reload Request

**Input:**
```json
{"type": "reload"}
```

**Output:**
```json
{"status": "ok", "count": 21643}
```

The `count` field indicates how many icons were cached after reloading. Cache is automatically saved to disk after reload.

### Search Request (Debug)

**Input:**
```json
{"type": "search", "pattern": "zen"}
```

**Output:**
```json
{"matches": ["zen", "zen-browser", "zenity", ...]}
```

Returns all icon names containing the pattern (case-insensitive, alphabetically sorted).

## Icon Resolution Priority

When resolving an icon name, the service uses this priority order:

### 1. Theme Priority

Follows the `Inherits=` chain from `index.theme`:
- Papirus-Dark → Papirus → breeze-dark → hicolor
- Earlier themes in the chain have higher priority
- System themes always win over hicolor fallback

### 2. Format Priority (Within Same Theme)

- SVG files are preferred over PNG files
- Fixed-size SVGs are preferred over scalable SVGs (when both exist)

### 3. Size Priority (Within Same Format)

- Larger sizes preferred (128x128 > 64x64 > 48x48 > ...)
- Scalable SVGs have lowest priority (size = 0)

### 4. Fallback Variations (If Exact Match Not Found)

If the exact icon name isn't in the cache, the service tries these variations in order:

1. **Browser/Client Suffixes**: `name + "-browser"`, `name + "-client"`
2. **Prefix Failover**: `"preferences-" + name`, `"utilities-" + name`, `"accessories-" + name`
3. **Case Normalization**: Lowercase version of name
4. **Reverse Domain**: Last part of domain (e.g., "com.mitchellh.ghostty" → "ghostty")
5. **Kebab/Underscore Conversion**: "visual-studio-code" ↔ "visual_studio_code"
6. **Org Prefix Variations**: `"org." + name + "." + Name`, `"org." + name`

Returns the first matching variation found, or empty string if none match.

## Directory Structure

Icons are expected at:
```
<BASE_PATH>/<THEME>/<SIZE>/<SUBDIR>/<ICON_NAME>.<ext>
```

Where:
- `<BASE_PATH>` is typically `/usr/share/icons` or `~/.local/share/icons`
- `<THEME>` is the theme name (e.g., "Papirus-Dark")
- `<SIZE>` is the size directory (e.g., "48x48", "scalable")
- `<SUBDIR>` is the icon category: `apps`, `actions`, `devices`, `places`, `status`, `mimetypes`, `categories`
- `<ICON_NAME>` is the icon name without extension
- `<ext>` is either "svg" or "png"

The service dynamically discovers directories from `index.theme` files (XDG Icon Theme Specification compliant).

## Environment Variables

- `QT_ICON_THEME`: Icon theme name (default: "Papirus-Dark")
- `USER`: Username for profile path detection (default: "user")
- `XDG_DATA_DIRS`: Colon-separated paths for additional icon roots (optional)
- `RESOLVER_DEBUG`: If set, enables debug logging to stderr

## Error Handling

- The service never crashes - it always returns valid JSON
- Errors are logged to stderr (only if `RESOLVER_DEBUG` is set)
- Invalid requests return empty path responses
- If environment variables are missing, sensible defaults are used
- If icon directories don't exist, falls back to `/usr/share/icons`

## Integration

This service is integrated into the shell through `IconResolver.qml` singleton, which manages communication and caching. Components use `AppSearch.resolveIconAsync()` for async resolution.

### Integration Architecture

```
Component
  ↓
AppSearch.guessIcon(windowClass) → icon name (synchronous)
  ↓
AppSearch.resolveIconAsync(iconName, callback) → themed path (async)
  ↓
IconResolver.qml (QML singleton, manages IPC + caching)
  ↓
icon-resolver (Rust binary, persistent cache)
  ↓
Theme directories
```

## Dependencies

- `serde` - Serialization framework (for JSON IPC + cache)
- `serde_json` - JSON support
- `dirs` - XDG directory discovery (for cache location)

## References

- [XDG Icon Theme Specification](https://specifications.freedesktop.org/icon-theme-spec/icon-theme-spec-latest.html)
- [Freedesktop Icon Naming Specification](https://specifications.freedesktop.org/icon-naming-spec/icon-naming-spec-latest.html)
