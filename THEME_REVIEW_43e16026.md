# Review: commit `43e16026`

## Summary

I agree with the overall direction of the commit:

- moving theme changes from full UI rebuilds to in-place scene mutation plus redraws is the right performance model
- palette interpolation in `ThemeService` is a reasonable foundation for animated theme transitions
- controls owning their own reactive updates is the right layer to solve this

I do **not** think the implementation is complete or where I would want it long-term.

## Main concerns

### 1. Redraw propagation is incomplete

The theme change callback currently only wakes:

- `m_bar.requestRedraw()`
- `m_panelManager.requestRedraw()`

in `src/app/application.cpp`.

That means other visible surfaces can hold updated palette state but never repaint until some unrelated event happens. The transition is therefore not truly global.

Examples likely affected:

- notifications
- lockscreen
- OSD
- overview
- any other active shell surface not covered by bar/panel redraw

## 2. The migration is only partial

Some controls and shell call sites still snapshot colors by value instead of participating in the reactive theme path.

Examples:

- `src/ui/controls/toggle.cpp`
  - recomputes colors from `palette` only when toggle state changes
  - has no palette subscription
- `src/ui/controls/progress_bar.cpp`
  - snapshots palette colors in the constructor
  - has no palette subscription
- `src/shell/control_center/overview_tab.cpp`
  - avatar background/border still use value-based theme colors
- `src/shell/control_center/calendar_tab.cpp`
  - weekday header label colors still use value-based assignments

So the commit establishes the mechanism, but not a consistently reactive system.

## 3. Theme binding leaked into shell code

The new `const Color*` pattern works mechanically, but it pushes palette-binding details into higher-level UI code:

- `setColor(&palette.primary)`
- `setBackground(&palette.surfaceVariant)`
- `setBorderColor(&palette.outline)`

That makes misses easy and spreads theming mechanics across the shell layer.

I would prefer the shell layer to stay declarative and not care how theme reactivity is implemented.

## 4. Control boundary drift

The repo guidance says shell code should prefer controls and avoid raw scene nodes for text. Some code touched in this area still works directly with lower-level nodes for theme-sensitive styling.

That is not caused by this commit alone, but a reactive theming pass is exactly where those shortcuts become expensive, because each low-level direct use becomes another one-off styling path to remember during theme updates.

## What I would have done differently

### A. Use `ColorRole` instead of raw palette pointers

This is the main design change I would make.

Instead of exposing reactivity as:

- `setColor(const Color*)`
- `setBackground(const Color*)`
- `setBorderColor(const Color*)`

I would move to something closer to:

- `setColorRole(ColorRole::OnSurface)`
- `setBackgroundRole(ColorRole::SurfaceVariant)`
- `setBorderRole(ColorRole::Outline)`

Benefits:

- shell code stays semantic and declarative
- controls own theme lookup and subscription internally
- fewer accidental value snapshots
- easier to audit coverage
- easier to evolve if palette structure changes later

For cases that truly need a fixed explicit color, keep the direct `Color` overloads as an escape hatch.

## B. Finish the migration in the controls layer first

Before converting lots of shell code, I would make sure the core controls are fully theme-reactive:

- `Label`
- `Glyph`
- `Box`
- `Flex`
- `Button`
- `Toggle`
- `ProgressBar`
- `Input`
- `Select`
- `Slider`
- `Image` if it exposes themed border/background treatment

That gives a much stronger foundation and keeps the shell conversion mostly mechanical.

## C. Centralize redraw fanout

If theme animation is global, redraw orchestration should also be global.

I would prefer one place that can request redraw from every active surface manager, rather than each new themed subsystem having to be remembered manually inside the theme callback.

That could mean:

- expanding the application-level redraw callback to include all visible surface systems
- or introducing a dedicated redraw coordinator for active shell surfaces

## D. Avoid calling the work done before coverage is complete

The current patch is a good intermediate step, but not a finished reactive-theme architecture.

I would treat it as:

- infrastructure added
- partial migration completed
- follow-up required before relying on it as the canonical pattern

## Practical next direction

If continuing from here, I would do the next pass in this order:

1. Add `ColorRole` / semantic theme roles in the controls layer.
2. Convert core controls to role-based theme binding.
3. Convert remaining shell code from raw palette values/pointers to roles.
4. Audit all active surfaces for redraw participation during theme transitions.
5. Remove or minimize direct palette-pointer usage from shell code.

## Bottom line

I agree with the intent and with replacing rebuild-on-theme-change with in-place reactive restyling.

I would not keep the raw `const Color*` API as the long-term design.

I would move to `ColorRole`, finish reactivity in the controls layer, and make redraw propagation truly global so theme transitions are complete and predictable across the whole shell.
