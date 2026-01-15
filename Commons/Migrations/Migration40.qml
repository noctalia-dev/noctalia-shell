import QtQuick

QtObject {
  id: root

  // List of all template IDs that existed as booleans in the old format
  readonly property var templateIds: ["gtk", "qt", "kcolorscheme", "alacritty", "kitty", "ghostty", "foot", "wezterm", "fuzzel", "discord", "pywalfox", "vicinae", "walker", "code", "spicetify", "telegram", "cava", "yazi", "emacs", "niri", "hyprland", "mango", "zed", "helix", "zenBrowser"]

  function migrate(adapter, logger, rawJson) {
    logger.i("Migration39", "Migrating templates from boolean format to activeTemplates array");

    // Check if old format exists (any boolean template property)
    const oldTemplates = rawJson?.templates;
    if (!oldTemplates) {
      logger.d("Migration39", "No templates section found, skipping migration");
      return true;
    }

    // Check if already migrated (has activeTemplates array)
    if (Array.isArray(oldTemplates.activeTemplates)) {
      logger.d("Migration39", "Already has activeTemplates array, skipping migration");
      return true;
    }

    // Build the new activeTemplates array from old boolean values
    const activeTemplates = [];
    for (const templateId of templateIds) {
      if (oldTemplates[templateId] === true) {
        activeTemplates.push({
                               "id": templateId,
                               "enabled": true
                             });
        logger.d("Migration39", "Migrated enabled template: " + templateId);
      }
    }

    // Write the new format
    adapter.templates.activeTemplates = activeTemplates;
    logger.i("Migration39", "Migrated " + activeTemplates.length + " templates to new array format");

    return true;
  }
}
