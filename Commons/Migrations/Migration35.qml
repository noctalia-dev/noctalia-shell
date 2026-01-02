import QtQuick

QtObject {
  id: root

  // Migrate bar.transparent to bar.backgroundOpacity + bar.useSeparateOpacity
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v35");

    if (rawJson?.bar?.transparent !== undefined) {
      if (rawJson.bar.transparent === true) {
        adapter.bar.backgroundOpacity = 0;
        adapter.bar.useSeparateOpacity = true;
        logger.i("Settings", "Migrated bar.transparent=true to backgroundOpacity=0, useSeparateOpacity=true");
      }
    }

    return true;
  }
}
