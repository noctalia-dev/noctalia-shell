import QtQuick

QtObject {
  id: root

  // Add default keybinds (1-6) to session menu power options if none are defined
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v53");

    const powerOptions = rawJson?.sessionMenu?.powerOptions;
    if (!powerOptions || !Array.isArray(powerOptions))
      return true;

    // Check if any power option has a keybind defined
    const hasAnyKeybind = powerOptions.some(opt => opt.keybind && opt.keybind !== "");
    if (hasAnyKeybind)
      return true;

    // No keybinds defined — apply defaults matching the action order
    const defaultKeybinds = {
      "lock": "1",
      "suspend": "2",
      "hibernate": "3",
      "reboot": "4",
      "logout": "5",
      "shutdown": "6"
    };

    for (let i = 0; i < powerOptions.length; i++) {
      const action = powerOptions[i].action;
      if (defaultKeybinds[action]) {
        adapter.sessionMenu.powerOptions[i].keybind = defaultKeybinds[action];
        logger.i("Settings", "Set keybind '" + defaultKeybinds[action] + "' for session menu action: " + action);
      }
    }

    return true;
  }
}
