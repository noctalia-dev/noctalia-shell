import QtQuick

QtObject {
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v58 (dock.dockType: static -> attached)");

    if (rawJson && rawJson.dock && rawJson.dock.dockType === "static") {
      adapter.dock.dockType = "attached";
      logger.i("Settings", "Migrated dock.dockType: static -> attached");
    }

    return true;
  }
}
