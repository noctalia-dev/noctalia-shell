# Launcher Category State Simplification Design

## Context

PR #2654 adds optional launcher category tabs. The current implementation stores the selected category inside `LauncherProvider` implementations, primarily `AppProvider`. That requires provider reset hooks and a separate `LauncherCategoryState` helper to avoid hidden filters when tabs are disabled, hidden, or the launcher reopens.

## Goal

Keep the current user experience while reducing state and test surface:

- Opening the launcher starts on the `All` category.
- Category selection only persists while the current launcher panel is open.
- Providers expose available categories but do not own selected UI state.
- Category tabs stay optional through `launcher.show_categories`.
- Launcher category tests should cover useful behavior, not removed reset plumbing.

## Design

`LauncherPanel` owns the selected category as opaque panel-local state. It stores only a provider-supplied category id and treats an empty id as "no category filter". It resets this state to empty on open and whenever category tabs are not active for the current view. The panel still asks providers for available categories so providers can opt in without panel-specific `AppProvider` checks.

`AppProvider` becomes stateless for category selection. It keeps `availableCategories()` and changes `query()` to accept an optional category argument. When the query text is empty, the provider filters entries by that category. Typed search continues to search all applications because category tabs are hidden while typing. The `all` category id remains an app-category detail; `LauncherPanel` does not include `app_categories.h` or compare against app-specific ids.

The generic provider API should expose the minimal data flow:

- `availableCategories() const`
- `query(std::string_view text, std::string_view category = {}) const`

The following API is removed:

- `selectedCategory()`
- `selectCategory()`
- `resetCategory()`
- `LauncherCategoryState`

## UI Flow

When the launcher opens, `LauncherPanel` clears `m_selectedCategory` and shows all entries. When category tabs are visible, the panel maps the empty selection to the first provider-supplied category for display. When the user selects a tab, the panel updates `m_selectedCategory`, refreshes results, and highlights the selected tab. When the user types, tabs are hidden and `m_selectedCategory` is cleared so no hidden filter remains.

`Tab` and `Shift+Tab` continue to cycle visible tabs using the panel-local selected index.

## Testing

Remove tests that assert provider reset behavior. Add or keep tests around category logic that remains meaningful:

- available categories include only present categories plus `All`;
- app entries match expected category aliases, such as `Audio`/`Video` matching `AudioVideo`;
- uncategorized entries are not accidentally filtered into unrelated categories.

Run the launcher/category unit tests and a full build target when practical.
