import QtQuick
import qs.Commons

QtObject {
  function migrate(adapter, logger, rawJson) {
    logger.i("Migration38", "Migrating bar margins from percentages to integers");

    // Use rawJson to read original values, adapter to write new values (following migration patterns)
    const rawVertical = rawJson?.bar?.marginVertical;
    const rawHorizontal = rawJson?.bar?.marginHorizontal;

    // Only migrate if values exist and are percentages (<= 1.0)
    if (rawVertical !== undefined && typeof rawVertical === 'number' && rawVertical <= 1.0) {
      const marginXL = 18; // Standard value of Style.marginXL
      adapter.bar.marginVertical = Math.round(rawVertical * marginXL);
      logger.d("Migration38", "Converted marginVertical from " + rawVertical + " to " + adapter.bar.marginVertical + "px");
    }

    if (rawHorizontal !== undefined && typeof rawHorizontal === 'number' && rawHorizontal <= 1.0) {
      const marginXL = 18; // Standard value of Style.marginXL
      adapter.bar.marginHorizontal = Math.round(rawHorizontal * marginXL);
      logger.d("Migration38", "Converted marginHorizontal from " + rawHorizontal + " to " + adapter.bar.marginHorizontal + "px");
    }

    return true;
  }
}
