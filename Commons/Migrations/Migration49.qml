import QtQuick

QtObject {
  id: root

  function migrate(adapter, logger, rawJson) {
    logger.i("Migration49", "Adding easing curve settings (defaults apply automatically)");

    // Easing curve settings have defaults in Settings.qml, no data transformation needed
    // New settings: easingType, easingTypeFast, easingTypeSlow

    return true;
  }
}
