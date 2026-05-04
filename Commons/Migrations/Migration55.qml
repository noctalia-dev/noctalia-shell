import QtQuick

QtObject {
  id: root

  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v55");

    // Check if the old setting exists
    if (rawJson.controlCenter && rawJson.controlCenter.openAtMouseOnBarRightClick !== undefined) {
      if (!rawJson.bar)
        rawJson.bar = {};

      rawJson.bar.rightClickFollowMouse = rawJson.controlCenter.openAtMouseOnBarRightClick;
      delete rawJson.controlCenter.openAtMouseOnBarRightClick;

      logger.i("Settings", "Successfully moved openAtMouseOnBarRightClick to bar.rightClickFollowMouse");
    }

    return true;
  }
}
