import QtQuick

QtObject {
  /**
  * Migration 45: Migrate 'floating' bar setting to 'barType'
  */
  function migrate(adapter, logger, rawJson) {
    logger.i("Migration45", "Migrating bar settings...");

    if (adapter.bar.floating) {
      adapter.bar.barType = "floating";
    } else {
      adapter.bar.barType = "simple";
    }

    return true;
  }
}
