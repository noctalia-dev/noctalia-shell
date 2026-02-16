import QtQuick

QtObject {
  id: root

  // Migrate keybinds from single strings to arrays of strings
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v50");

    const keybinds = rawJson?.general?.keybinds;
    if (!keybinds)
      return true;

    const keys = ["keyUp", "keyDown", "keyLeft", "keyRight", "keyEnter", "keyEscape"];
    for (const key of keys) {
      if (keybinds[key] !== undefined && typeof keybinds[key] === "string") {
        adapter.general.keybinds[key] = [keybinds[key]];
        logger.i("Settings", "Migrated keybinds." + key + " from string to array: [" + keybinds[key] + "]");
      }
    }

    return true;
  }
}
