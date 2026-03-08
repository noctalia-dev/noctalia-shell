import QtQuick
import Quickshell

QtObject {
  id: root

  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v56 (Color Scheme Migration)");

    const scriptPath = Quickshell.shellDir + "/Scripts/python/src/theming/migrate-colorschemes.py";
    const configDir = Quickshell.env("NOCTALIA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/noctalia";

    logger.i("Settings", `Running color scheme migration script: ${scriptPath} with configDir: ${configDir}`);

    // Run the migration script detached
    Quickshell.execDetached(["python3", scriptPath, configDir]);

    return true;
  }
}
