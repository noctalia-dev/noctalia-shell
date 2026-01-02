import QtQuick

QtObject {
  id: root

  // Migrate systemMonitor.enableNvidiaGpu to systemMonitor.enableDgpuMonitoring
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v32");

    // Check rawJson for old property (adapter doesn't expose removed properties)
    if (rawJson?.systemMonitor?.enableNvidiaGpu !== undefined) {
      adapter.systemMonitor.enableDgpuMonitoring = rawJson.systemMonitor.enableNvidiaGpu;
      logger.i("Settings", "Migrated systemMonitor.enableNvidiaGpu to enableDgpuMonitoring: " + adapter.systemMonitor.enableDgpuMonitoring);
    }

    return true;
  }
}
