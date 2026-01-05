import QtQuick

QtObject {
  id: root

  // Rename WiFi widgets/shortcuts to Network
  function migrate(adapter, logger, rawJson) {
    logger.i("Settings", "Migrating settings to v37 (WiFi → Network)");

    let changed = false;

    function migrateArray(contextName, rawArr, adapterArr, setItem) {
      if (!adapterArr)
        return;
      const len = adapterArr.length;
      for (let i = 0; i < len; i++) {
        // Prefer raw item if present, otherwise use adapter item
        const item = rawArr && rawArr[i] !== undefined ? rawArr[i] : adapterArr[i];

        if (item === undefined || item === null)
          continue;

        // Case 1: simple string entries
        if (typeof item === "string") {
          if (item === "WiFi") {
            setItem(i, "Network");
            changed = true;
            logger.i("Settings", `Migrated ${contextName}[${i}] from WiFi to Network (string entry)`);
          }
          continue;
        }

        // Case 2: object entries with id
        let id = item.id !== undefined ? item.id : (item.widgetId !== undefined ? item.widgetId : undefined);
        if (id === "WiFi") {
          var newObj = {};
          for (var key in item)
            newObj[key] = item[key];
          if (newObj.id !== undefined)
            newObj.id = "Network";
          if (newObj.widgetId !== undefined && newObj.id === undefined)
            newObj.widgetId = "Network"; // fallback if older schema used widgetId
          setItem(i, newObj);
          changed = true;
          logger.i("Settings", `Migrated ${contextName}[${i}] from WiFi to Network (object entry)`);
        }
      }
    }

    // --- Bar widgets: left/center/right
    const sections = ["left", "center", "right"];
    for (const section of sections) {
      const rawArr = rawJson?.bar?.widgets?.[section];
      const adapterArr = adapter?.bar?.widgets?.[section];
      migrateArray(`bar.widgets.${section}`, rawArr, adapterArr, function (i, v) {
        adapter.bar.widgets[section][i] = v;
      });
    }

    // --- Control Center shortcuts: left/right
    const rawLeft = rawJson?.controlCenter?.shortcuts?.left;
    const adLeft = adapter?.controlCenter?.shortcuts?.left;
    migrateArray("controlCenter.shortcuts.left", rawLeft, adLeft, function (i, v) {
      adapter.controlCenter.shortcuts.left[i] = v;
    });

    const rawRight = rawJson?.controlCenter?.shortcuts?.right;
    const adRight = adapter?.controlCenter?.shortcuts?.right;
    migrateArray("controlCenter.shortcuts.right", rawRight, adRight, function (i, v) {
      adapter.controlCenter.shortcuts.right[i] = v;
    });

    if (!changed) {
      logger.i("Settings", "No WiFi widget IDs found to migrate; leaving settings unchanged");
    }

    return true;
  }
}
