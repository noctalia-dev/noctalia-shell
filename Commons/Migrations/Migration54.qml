import QtQuick

QtObject {
  id: root

  // Add numpad Enter as a second default keybind for keyEnter
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v54");

    const keybinds = rawJson?.general?.keybinds;
    if (!keybinds)
      return true;

    const keyEnter = keybinds.keyEnter;
    if (!keyEnter || !Array.isArray(keyEnter))
      return true;

    // Only add "Enter" if the first entry is "Return" and "Enter" isn't already present
    if (keyEnter[0] === "Return" && !keyEnter.includes("Enter")) {
      var updated = Array.from(keyEnter);
      updated.splice(1, 0, "Enter");
      adapter.general.keybinds.keyEnter = updated;
      logger.i("Settings", "Added 'Enter' (numpad) as second default keybind for keyEnter");
    }

    return true;
  }
}
