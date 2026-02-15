import QtQuick

QtObject {
  id: root

  // Migrate battery thresholds from notifications to systemMonitor
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v48");

    if (rawJson?.notifications?.batteryWarningThreshold !== undefined) {
      adapter.systemMonitor.batteryWarningThreshold = rawJson.notifications.batteryWarningThreshold;
      logger.i("Settings", "Migrated notifications.batteryWarningThreshold to systemMonitor: " + adapter.systemMonitor.batteryWarningThreshold);
    }

    if (rawJson?.notifications?.batteryCriticalThreshold !== undefined) {
      adapter.systemMonitor.batteryCriticalThreshold = rawJson.notifications.batteryCriticalThreshold;
      logger.i("Settings", "Migrated notifications.batteryCriticalThreshold to systemMonitor: " + adapter.systemMonitor.batteryCriticalThreshold);
    }

    return true;
  }
}
