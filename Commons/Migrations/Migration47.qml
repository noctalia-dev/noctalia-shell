import QtQuick
import Quickshell

QtObject {
  id: root

  function migrate(adapter, logger, rawJson) {
    logger.i("Migration47", "Removing network_stats.json cache");

    // Remove the network_stats.json cache file (no longer used - autoscaling from history now)
    const shellName = "noctalia";
    const cacheDir = Quickshell.env("NOCTALIA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/" + shellName + "/";
    const networkStatsFile = cacheDir + "network_stats.json";
    Quickshell.execDetached(["rm", "-f", networkStatsFile]);

    logger.d("Migration47", "Removed network_stats.json");

    return true;
  }
}
