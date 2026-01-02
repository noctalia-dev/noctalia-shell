import QtQuick
import Quickshell
import qs.Commons

QtObject {
  id: root

  // Clear legacy emoji usage cache to adopt new format
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v36");

    const usagePath = Settings.cacheDir + "emoji_usage.json";

    if (!usagePath.endsWith("emoji_usage.json")) {
      logger.w("Settings", "Skipping emoji usage cleanup due to unexpected path: " + usagePath);
      return true;
    }

    try {
      // Ensure dir exists then remove the file
      Quickshell.execDetached(["sh", "-c", `mkdir -p "${Settings.cacheDir}" && rm -f -- "${usagePath}"`]);
      logger.i("Settings", "Cleared legacy emoji usage file at: " + usagePath);
    } catch (e) {
      logger.w("Settings", "Failed to clear emoji usage cache: " + e);
    }

    return true;
  }
}
