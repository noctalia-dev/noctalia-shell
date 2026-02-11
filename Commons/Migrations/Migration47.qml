import QtQuick
import Quickshell

QtObject {
  id: root

  function migrate(adapter, logger, rawJson) {
    logger.i("Migration47", "Removing network_stats.json cache and updating polling intervals");

    // Remove the network_stats.json cache file (no longer used - autoscaling from history now)
    const shellName = "noctalia";
    const cacheDir = Quickshell.env("NOCTALIA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/" + shellName + "/";
    const networkStatsFile = cacheDir + "network_stats.json";
    Quickshell.execDetached(["rm", "-f", networkStatsFile]);

    // Update polling intervals to 1000ms for smoother graphs (only if currently slower)
    if (adapter.systemMonitor.cpuPollingInterval > 1000)
      adapter.systemMonitor.cpuPollingInterval = 1000;
    if (adapter.systemMonitor.memPollingInterval > 1000)
      adapter.systemMonitor.memPollingInterval = 1000;
    if (adapter.systemMonitor.networkPollingInterval > 1000)
      adapter.systemMonitor.networkPollingInterval = 1000;

    logger.d("Migration47", "Removed network_stats.json and adjusted polling intervals");

    return true;
  }
}
