pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  property bool initComplete: false
  property bool nextDarkModeState: false

  Connections {
    target: LocationService.data
    enabled: Settings.data.colorSchemes.schedulingMode == "location"
    function onWeatherChanged() {
      if (LocationService.data.weather !== null) {
        const changes = root.collectWeatherChanges(LocationService.data.weather);
        if (!root.initComplete) {
          root.initComplete = true;
          root.applyCurrentMode(changes);
        }
        root.scheduleNextMode(changes);
      }
    }
  }

  Connections {
    target: Settings.data.colorSchemes
    enabled: Settings.data.colorSchemes.schedulingMode == "manual"
    function onManualSunriseChanged() {
      const changes = root.collectManualChanges();
      root.applyCurrentMode(changes);
      root.scheduleNextMode(changes);
    }
    function onManualSunsetChanged() {
      const changes = root.collectManualChanges();
      root.applyCurrentMode(changes);
      root.scheduleNextMode(changes);
    }
  }

  Connections {
    target: Settings.data.colorSchemes
    function onSchedulingModeChanged() {
      root.update();
    }
  }

  Connections {
    target: Time
    function onResumed() {
      Logger.i("DarkModeService", "System resumed - re-evaluating dark mode");
      root.update();
    }
  }

  Timer {
    id: timer
    onTriggered: {
      Settings.data.colorSchemes.darkMode = root.nextDarkModeState;
      root.update();
    }
  }

  function init() {
    Logger.i("DarkModeService", "Service started");
    root.update();
  }

  function update() {
    if (Settings.data.colorSchemes.schedulingMode == "manual") {
      const changes = collectManualChanges();
      initComplete = true;
      applyCurrentMode(changes);
      scheduleNextMode(changes);
    } else if (Settings.data.colorSchemes.schedulingMode == "location" && LocationService.data.weather) {
      const changes = collectWeatherChanges(LocationService.data.weather);
      initComplete = true;
      applyCurrentMode(changes);
      scheduleNextMode(changes);
    }
  }

  function parseTime(timeString) {
    const parts = timeString.split(":").map(Number);
    return {
      "hour": parts[0],
      "minute": parts[1]
    };
  }

  function collectManualChanges() {
    const sunriseTime = parseTime(Settings.data.colorSchemes.manualSunrise);
    const sunsetTime = parseTime(Settings.data.colorSchemes.manualSunset);

    const now = new Date();
    const year = now.getFullYear();
    const month = now.getMonth();
    const day = now.getDate();

    const yesterdaysSunset = new Date(year, month, day - 1, sunsetTime.hour, sunsetTime.minute);
    const todaysSunrise = new Date(year, month, day, sunriseTime.hour, sunriseTime.minute);
    const todaysSunset = new Date(year, month, day, sunsetTime.hour, sunsetTime.minute);
    const tomorrowsSunrise = new Date(year, month, day + 1, sunriseTime.hour, sunriseTime.minute);

    return [
          {
            "time": yesterdaysSunset.getTime(),
            "darkMode": true
          },
          {
            "time": todaysSunrise.getTime(),
            "darkMode": false
          },
          {
            "time": todaysSunset.getTime(),
            "darkMode": true
          },
          {
            "time": tomorrowsSunrise.getTime(),
            "darkMode": false
          }
        ];
  }

  function collectWeatherChanges(weather) {
    const changes = [];

    if (Date.now() < Date.parse(weather.daily.sunrise[0])) {
      // The sun has not risen yet
      changes.push({
                     "time": Date.now() - 1,
                     "darkMode": true
                   });
    }

    for (var i = 0; i < weather.daily.sunrise.length; i++) {
      changes.push({
                     "time": Date.parse(weather.daily.sunrise[i]),
                     "darkMode": false
                   });
      changes.push({
                     "time": Date.parse(weather.daily.sunset[i]),
                     "darkMode": true
                   });
    }

    return changes;
  }

  function applyCurrentMode(changes) {
    const now = Date.now();

    // changes.findLast(change => change.time < now) // not available in QML...
    let lastChange = null;
    for (var i = 0; i < changes.length; i++) {
      if (changes[i].time < now) {
        lastChange = changes[i];
      }
    }

    if (lastChange) {
      Settings.data.colorSchemes.darkMode = lastChange.darkMode;
      Logger.d("DarkModeService", `Reset: darkmode=${lastChange.darkMode}`);
    }
  }

  function scheduleNextMode(changes) {
    const now = Date.now();
    const nextChange = changes.find(change => change.time > now);
    if (nextChange) {
      root.nextDarkModeState = nextChange.darkMode;
      timer.interval = nextChange.time - now;
      timer.restart();
      Logger.d("DarkModeService", `Scheduled: darkmode=${nextChange.darkMode} in ${timer.interval} ms`);
    }
  }
}
