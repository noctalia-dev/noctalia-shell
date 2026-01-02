import QtQuick

QtObject {
  id: root

  // Migrate wallpaper.randomEnabled to wallpaper.wallpaperChangeMode
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v33");

    if (rawJson?.wallpaper?.randomEnabled !== undefined) {
      // We'll keep randomEnabled for backward compatibility but set wallpaperChangeMode
      if (rawJson.wallpaper.randomEnabled === true) {
        adapter.wallpaper.wallpaperChangeMode = "random";
        logger.i("Settings", "Migrated wallpaper.randomEnabled=true to wallpaperChangeMode=random");
      } else {
        adapter.wallpaper.wallpaperChangeMode = "random";
        logger.i("Settings", "Set wallpaperChangeMode=random (randomEnabled was false)");
      }
    } else {
      adapter.wallpaper.wallpaperChangeMode = "random";
      logger.i("Settings", "Set default wallpaperChangeMode=random");
    }

    return true;
  }
}
