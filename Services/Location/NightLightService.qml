pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  // Night Light properties - directly bound to settings
  readonly property var params: Settings.data.nightLight
  property var lastCommand: []

  function apply(force = false) {
    // If using LocationService, wait for it to be ready
    if (!params.forced && params.autoSchedule && !LocationService.coordinatesReady) {
      return;
    }

    var command = buildCommand();

    // Compare with previous command to avoid unnecessary restart
    if (force || JSON.stringify(command) !== JSON.stringify(lastCommand)) {
      lastCommand = command;
      runner.command = command;

      // Set running to false so it may restart below if still enabled
      runner.running = false;
    }
    runner.running = params.enabled;
  }

  function buildCommand() {
    var cmd = ["wlsunset"];
    if (params.forced) {
      // Force immediate full night temperature regardless of time
      // Keep distinct day/night temps but set times so we're effectively always in "night"
      cmd.push("-t", `${params.nightTemp}`, "-T", `${params.dayTemp}`);
      // Night spans from sunset (00:00) to sunrise (23:59) covering almost the full day
      cmd.push("-S", "23:59"); // sunrise very late
      cmd.push("-s", "00:00"); // sunset at midnight
      // Near-instant transition
      cmd.push("-d", 1);
    } else {
      cmd.push("-t", `${params.nightTemp}`, "-T", `${params.dayTemp}`);
      if (params.autoSchedule) {
        cmd.push("-l", `${LocationService.stableLatitude}`, "-L", `${LocationService.stableLongitude}`);
      } else {
        cmd.push("-S", params.manualSunrise);
        // Avoid midnight edge case - 00:00 causes wlsunset issues at day transition
        var sunset = params.manualSunset === "00:00" ? "23:59" : params.manualSunset;
        cmd.push("-s", sunset);
      }
      cmd.push("-d", 60 * 15); // 15min progressive fade at sunset/sunrise
    }
    return cmd;
  }

  // Observe setting changes and location readiness
  Connections {
    target: Settings.data.nightLight
    function onEnabledChanged() {
      apply();
      // Toast: night light toggled
      const enabled = !!Settings.data.nightLight.enabled;
      ToastService.showNotice(I18n.tr("common.night-light"), enabled ? I18n.tr("common.enabled") : I18n.tr("common.disabled"), enabled ? "nightlight-on" : "nightlight-off");
    }
    function onForcedChanged() {
      apply();
      if (Settings.data.nightLight.enabled) {
        ToastService.showNotice(I18n.tr("common.night-light"), Settings.data.nightLight.forced ? I18n.tr("toast.night-light.forced") : I18n.tr("toast.night-light.normal"), Settings.data.nightLight.forced ? "nightlight-forced" : "nightlight-on");
      }
    }
    function onNightTempChanged() {
      apply();
    }
    function onDayTempChanged() {
      apply();
    }
  }

  Connections {
    target: LocationService
    function onCoordinatesReadyChanged() {
      if (LocationService.coordinatesReady) {
        root.apply();
      }
    }
  }

  Timer {
    id: resumeRetryTimer
    interval: 2000
    repeat: false
    onTriggered: {
      Logger.i("NightLight", "Resume retry - re-applying night light again");
      root.apply(true);
    }
  }

  Connections {
    target: Time
    function onResumed() {
      Logger.i("NightLight", "System resumed - re-applying night light");
      root.apply(true);
      resumeRetryTimer.restart();
    }
  }

  // Foreground process runner
  Process {
    id: runner
    running: false
    onStarted: {
      Logger.i("NightLight", "Wlsunset started:", runner.command);
    }
    onExited: function (code, status) {
      Logger.i("NightLight", "Wlsunset exited:", code, status);
    }
  }
}
