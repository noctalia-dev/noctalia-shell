import QtQuick
import Quickshell

QtObject {
  id: root

  function migrate(adapter, logger, rawJson) {
    logger.i("Migration46", "Removing legacy PAM configuration file");

    const shellName = "noctalia";
    const configDir = Quickshell.env("NOCTALIA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/" + shellName + "/";
    const pamConfigDir = configDir + "pam";
    // Remove the entire pam directory if it exists
    const script = `rm -rf '${pamConfigDir}'`;
    Quickshell.execDetached(["sh", "-c", script]);

    logger.d("Migration46", "Cleaned up legacy PAM config");

    return true;
  }
}
