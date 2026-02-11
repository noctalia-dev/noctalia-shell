import QtQuick
import Quickshell
import qs.Commons

QtObject {
  id: root

  // Remove old launcher_app_usage.json (usage tracking moved to ShellState)
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v49");

    Quickshell.execDetached(["rm", "-f", Settings.cacheDir + "launcher_app_usage.json"]);
    logger.i("Settings", "Removed old launcher_app_usage.json");

    return true;
  }
}
