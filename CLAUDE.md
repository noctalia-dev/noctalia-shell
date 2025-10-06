# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Noctalia Shell is a beautiful, minimal Wayland desktop shell built with **Quickshell** (Qt6/QML). It provides a complete desktop environment with a customizable bar, dock, launcher, notifications, control center, and more. Built with a warm lavender aesthetic that's fully customizable through color schemes.

**Technology Stack**: QML (Qt6), JavaScript, Nix
**Supported Compositors**: Niri (primary), Hyprland (primary), other Wayland compositors (generic support)

## Development Commands

### Running the Shell

```bash
# Run using Nix flake (recommended)
nix run .

# Run with Quickshell directly (requires quickshell installed)
quickshell -p /home/chris/src/noctalia-shell

# Build the Nix package
nix build .
```

### Development Tools

```bash
# Format QML files
./Bin/qmlfmt.sh

# Check translations (i18n)
./Bin/i18n-json-check.sh  # Check JSON translation files
./Bin/i18n-qml-check.sh   # Check QML translation strings

# Compile shaders
./Bin/shaders-compile.sh

# Test notifications
./Bin/notifications-test.sh
```

### NixOS Integration

The flake provides both a home-manager module and a NixOS module for easy integration:

```nix
# Home Manager module
programs.noctalia-shell.enable = true;
programs.noctalia-shell.settings = { /* custom settings */ };

# NixOS systemd service
services.noctalia-shell.enable = true;
services.noctalia-shell.target = "graphical-session.target";
```

## Architecture Overview

### Core Shell Structure

The shell initialization flow (shell.qml):
1. **Load Commons**: Settings, I18n, Logger, Colors
2. **Initialize Services**: Wallpaper, ColorScheme, BarWidgetRegistry, Location, NightLight, Font, Hooks, Bluetooth
3. **Load Modules**: Background, Bar, Dock, Launcher, ControlCenter, Notification, OSD, LockScreen, SessionMenu, Toast

### Key Architectural Patterns

#### 1. Service Architecture
All services are QML Singletons in `/Services/` that provide system-level functionality:
- **CompositorService**: Abstraction layer for Hyprland/Niri/generic compositors
- **BarWidgetRegistry**: Central registry for all bar widgets (extensibility pattern)
- **WallpaperService**: Wallpaper management with transitions
- **ColorSchemeService**: Theme/color scheme management
- **NotificationService**: FreeDesktop notifications
- **AudioService/MediaService**: PipeWire audio and MPRIS media control
- **NetworkService/BluetoothService**: System connectivity
- **BrightnessService**: Display and DDC/CI monitor brightness
- **SystemStatService**: CPU, memory, network, disk stats

Services are accessed as globals throughout QML: `CompositorService.switchToWorkspace()`, `Settings.bar.position`, etc.

#### 2. Compositor Abstraction Pattern
The `CompositorService` provides a facade over compositor-specific backends:
- Automatically detects compositor (Hyprland via `HYPRLAND_INSTANCE_SIGNATURE`, otherwise Niri)
- Loads appropriate backend service (`HyprlandService.qml` or `NiriService.qml`)
- Provides unified API: `workspaces`, `windows`, `switchToWorkspace()`, `focusWindow()`, etc.
- Backend signals are forwarded: `workspaceChanged`, `activeWindowChanged`, `windowListChanged`

When adding compositor support, implement the backend interface and add to CompositorService detection.

#### 3. Bar Widget System
Widgets are dynamically loaded based on `settings.json` configuration:
- **Registry**: `BarWidgetRegistry` maps widget IDs to QML components
- **Loading**: `BarWidgetLoader` instantiates widgets from registry
- **Configuration**: Each widget has metadata (user settings schema) in BarWidgetRegistry
- **Settings UI**: Auto-generated from widget metadata in Settings panel

To add a new bar widget:
1. Create widget component in `Modules/Bar/Widgets/YourWidget.qml`
2. Register in `BarWidgetRegistry.qml` (add to widgets object and metadata)
3. Create settings component in `Modules/Settings/Bar/WidgetSettings/YourWidgetSettings.qml` (if configurable)

#### 4. Panel/Overlay System
UI panels inherit from `NPanel` widget (`Widgets/NPanel.qml`):
- Centralized show/hide/toggle logic
- Consistent animation behavior
- Multiple display modes: popup, dialog, fullscreen
- Position management: center, top, bottom, left, right
- Background dimming support via `general.dimDesktop` setting
- Examples: Launcher, ControlCenter, Calendar, Settings, WiFi, Bluetooth panels

`PanelService` provides global panel state management and references.

#### 5. Settings System
Settings are managed through `Settings` singleton (Commons/Settings.qml):
- Loads from `~/.config/noctalia/settings.json`
- Falls back to `Assets/settings-default.json`
- Schema versioning with `settingsVersion`
- Deep merge with defaults when using Nix home-manager module
- Hot-reload support: changes to settings.json trigger automatic updates

Access settings: `Settings.bar.position`, `Settings.wallpaper.directory`, etc.

#### 6. Color Scheme System
Multi-source color theming:
- **Material Design 3 colors**: mPrimary, mSecondary, mSurface, mOnSurface, etc. (accessed via `Color.mPrimary`)
- **Predefined schemes**: JSON files in `Assets/ColorScheme/`
- **Wallpaper colors**: Auto-generated with `matugen` tool
- **Color singleton**: `Color.qml` provides global color access and dark/light mode switching

Color generation flow: Wallpaper → matugen → Material Design 3 palette → ColorSchemeService → Color singleton

#### 7. Internationalization (i18n)
Translation system via `I18n` singleton (Commons/I18n.qml):
- Translation files: `Assets/Translations/{locale}.json`
- Usage: `I18n.t("key")` or `I18n.t("key with %1 placeholder", value)`
- Current languages: en, es, fr, de, pt, zh-CN
- Translation coverage checked by `Bin/i18n-json-check.sh` and `Bin/i18n-qml-check.sh`

### Directory Structure

```
Assets/               # Static assets (color schemes, translations, icons, default settings)
Bin/                  # Development scripts (formatting, i18n checks, shader compilation)
Commons/              # Global singletons (Settings, I18n, Logger, Color, Style, Icons)
Helpers/              # JavaScript utilities (FuzzySort, AdvancedMath, sha256, object conversion)
Modules/              # UI modules (Bar, Dock, Launcher, Notification, ControlCenter, etc.)
  Bar/                # Bar and bar widgets
    Widgets/          # Individual bar widgets
    Extras/           # Bar UI components (BarPill, TrayMenu, BarWidgetLoader)
  Settings/           # Settings panel with tabs and widget settings
Services/             # Backend services (singletons providing system functionality)
Shaders/              # GLSL shaders for visual effects
Widgets/              # Reusable UI components (NButton, NPanel, NSlider, NTextInput, etc.)
shell.qml             # Main entry point
```

### Reusable Widgets (Widgets/)

The shell provides a comprehensive set of custom QML widgets with consistent styling:
- **NButton, NIconButton**: Buttons with hover/press states
- **NPanel**: Base for all panels/overlays
- **NSlider, NValueSlider**: Sliders with labels
- **NTextInput**: Text input with validation
- **NComboBox, NSearchableComboBox**: Dropdowns
- **NCheckbox, NToggle, NRadioButton**: Boolean inputs
- **NFilePicker**: File/directory picker dialog
- **NColorPicker**: Color picker with dialog
- **NScrollView, NListView**: Scrollable containers
- **NImageCached, NImageCircled, NImageRounded**: Image display components
- **NCollapsible**: Expandable sections

All widgets follow Material Design 3 color system and respond to theme changes.

### Runtime Dependencies

Critical for functionality (defined in flake.nix):
- `matugen`: Material Design color generation from wallpapers
- `brightnessctl`: Backlight control
- `ddcutil`: External monitor brightness control (DDC/CI)
- `networkmanager`: Network connectivity
- `bluez`: Bluetooth management
- `wl-clipboard`: Wayland clipboard access
- `cliphist`: Clipboard history
- `cava`: Audio visualizer
- `gpu-screen-recorder`: Screen recording (x86_64 only)
- `wlsunset`: Night light/color temperature
- `libnotify`: Notification sending

### Key Implementation Details

#### Compositor-Specific Code
- Hyprland: Uses `hyprctl` for IPC and workspace management
- Niri: Uses `niri msg` for IPC and custom event-stream parsing
- Generic: Limited workspace support, focuses on bar/panels

#### Background/Wallpaper System
- Supports per-monitor wallpapers with `monitors` array in settings
- Multiple fill modes: crop, contain, cover, fill, tile
- Animated transitions between wallpapers (random, fade, slide, etc.)
- Shader-based transitions in `Shaders/`

#### Screen Recording
- Uses `gpu-screen-recorder` on x86_64 systems
- Configurable codec, quality, frame rate, audio source
- Portal-based screen selection
- Outputs to configured directory or ~/Videos

#### Brightness Control
- Internal displays: `brightnessctl`
- External monitors: `ddcutil` with DDC/CI protocol
- Per-monitor brightness control
- Brightness overlays (OSD) when changing

#### Performance Considerations
- Lazy loading: Modules load after Settings and I18n initialization
- Widget registry: Components defined once, instantiated as needed
- Background transitions: Avoid multiple active transitions to prevent flickering
- Hot-reload support: Use `Quickshell.inhibitReloadPopup()` to prevent popups during development

## Common Development Patterns

### Adding a New Service

1. Create `Services/YourService.qml` as a Singleton
2. Add initialization in `shell.qml` Component.onCompleted: `YourService.init()`
3. Access globally: `YourService.property` or `YourService.method()`

### Adding a New Panel

1. Create `Modules/YourPanel/YourPanel.qml` inheriting from `NPanel`
2. Add instance in shell.qml with unique `objectName`
3. Access via `PanelService` or direct reference
4. Implement show/hide/toggle logic using NPanel properties

### Working with Settings

Always check settings exist before accessing:
```qml
readonly property bool enabled: Settings?.yourModule?.enabled ?? false
```

For new settings sections, add to `Assets/settings-default.json` with appropriate defaults.

### Compositor Compatibility

Test changes with both Niri and Hyprland. Use `CompositorService.isNiri` or `CompositorService.isHyprland` for compositor-specific logic.

### Debugging

Use `Logger` singleton for consistent logging:
```qml
Logger.log("ComponentName", "Message")
Logger.warn("ComponentName", "Warning message")
Logger.error("ComponentName", "Error message")
```

## Important Notes

- **Hot Reload**: Quickshell supports hot reload during development (Ctrl+Q to quit)
- **Settings Format**: Always increment `settingsVersion` when changing settings schema
- **Color Theme**: All colors should use Material Design 3 tokens from `Color` singleton
- **Translations**: Add new strings to all translation files in `Assets/Translations/`
- **Widget Naming**: Bar widgets must follow naming convention and be registered in BarWidgetRegistry
- **Panel Management**: Never create multiple instances of panels, reference the singleton instances in shell.qml
