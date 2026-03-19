import QtQuick
import Quickshell
import qs.Commons

QtObject {
  id: root

  function migrate(adapter, logger, rawJson) {
    logger.i("Migration47", "Removing network_stats.json cache");

    const networkStatsFile = Settings.cacheDir + "network_stats.json";
    Quickshell.execDetached(["rm", "-f", networkStatsFile]);

    logger.d("Migration47", "Removed network_stats.json");

    return true;
  }
}
