pragma Singleton
import QtQuick

import Quickshell
import qs.Commons
import qs.Services.System

Singleton {
  id: root

  // Current date
  property var now: new Date()

  // Unix timestamp of the last update
  property real _lastUpdateTs: Date.now()

  // Signal emitted when a significant time jump is detected (e.g. system resume)
  signal resumed

  // Returns a Unix Timestamp (in seconds)
  readonly property int timestamp: {
    return Math.floor(root.now / 1000);
  }

  // Timer state (for countdown/stopwatch)
  property bool timerRunning: false
  property bool timerStopwatchMode: false
  property int timerRemainingSeconds: 0
  property int timerTotalSeconds: 0
  property int timerElapsedSeconds: 0
  property bool timerSoundPlaying: false
  property int timerStartTimestamp: 0 // Unix timestamp when timer was started
  property int timerPausedAt: 0 // Value when paused (for resuming)

  Timer {
    id: updateTimer
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: false
    onTriggered: {
      var newTime = new Date();
      var currentTs = newTime.getTime();

      // Detect time jump (e.g. system resume) - threshold: 5 seconds
      if (currentTs - root._lastUpdateTs > 5000) {
        Logger.i("Time", "Time jump detected (" + Math.round((currentTs - root._lastUpdateTs) / 1000) + "s) - likely system resume");
        root.resumed();
      }
      root._lastUpdateTs = currentTs;

      root.now = newTime;

      // Update timer if running
      if (root.timerRunning && root.timerStartTimestamp > 0) {
        const elapsedSinceStart = root.timestamp - root.timerStartTimestamp;

        if (root.timerStopwatchMode) {
          root.timerElapsedSeconds = root.timerPausedAt + elapsedSinceStart;
        } else {
          root.timerRemainingSeconds = root.timerTotalSeconds - elapsedSinceStart;
          if (root.timerRemainingSeconds <= 0) {
            root.timerOnFinished();
          }
        }
      }

      // Adjust next interval to sync with the start of the next second
      var msIntoSecond = newTime.getMilliseconds();
      if (msIntoSecond > 100) {
        // If we're more than 100ms into the second, adjust for next time
        updateTimer.interval = 1000 - msIntoSecond + 10; // +10ms buffer
        updateTimer.restart();
      } else {
        updateTimer.interval = 1000;
      }
    }
  }

  Component.onCompleted: {
    // Start by syncing to the next second boundary
    var now = new Date();
    var msUntilNextSecond = 1000 - now.getMilliseconds();
    updateTimer.interval = msUntilNextSecond + 10; // +10ms buffer
    updateTimer.restart();
  }

  // Formats a Date object into a YYYYMMDD-HHMMSS string.
  function getFormattedTimestamp(date) {
    if (!date) {
      date = new Date();
    }
    const year = date.getFullYear();

    // getMonth() is zero-based, so we add 1
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');

    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const seconds = String(date.getSeconds()).padStart(2, '0');

    return `${year}${month}${day}-${hours}${minutes}${seconds}`;
  }

  // Format an easy to read approximate duration ex: 4h 32m
  // Used to display the time remaining on the Battery widget, computer uptime, etc..
  function formatVagueHumanReadableDuration(totalSeconds) {
    if (typeof totalSeconds !== 'number' || totalSeconds < 0) {
      return '0s';
    }

    // Floor the input to handle decimal seconds
    totalSeconds = Math.floor(totalSeconds);

    const days = Math.floor(totalSeconds / 86400);
    const hours = Math.floor((totalSeconds % 86400) / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    const parts = [];
    if (days)
      parts.push(`${days}d`);
    if (hours)
      parts.push(`${hours}h`);
    if (minutes)
      parts.push(`${minutes}m`);

    // Only show seconds if no hours and no minutes
    if (!hours && !minutes) {
      parts.push(`${seconds}s`);
    }

    return parts.join(' ');
  }

  // Format a date into
  function formatRelativeTime(date) {
    if (!date)
      return "";
    const diff = Date.now() - date.getTime();
    if (diff < 60000)
      return I18n.tr("notifications.time.now");
    if (diff < 120000)
      return I18n.tr("notifications.time.diff-m");
    if (diff < 3600000)
      return I18n.tr("notifications.time.diff-mm", {
                       "diff": Math.floor(diff / 60000)
                     });
    if (diff < 7200000)
      return I18n.tr("notifications.time.diff-h");
    if (diff < 86400000)
      return I18n.tr("notifications.time.diff-hh", {
                       "diff": Math.floor(diff / 3600000)
                     });
    if (diff < 172800000)
      return I18n.tr("notifications.time.diff-d");
    return I18n.tr("notifications.time.diff-dd", {
                     "diff": Math.floor(diff / 86400000)
                   });
  }

  // Timer functions
  function timerStart() {
    if (root.timerStopwatchMode) {
      root.timerRunning = true;
      root.timerStartTimestamp = root.timestamp;
      root.timerPausedAt = root.timerElapsedSeconds;
    } else {
      if (root.timerRemainingSeconds <= 0) {
        return;
      }
      root.timerRunning = true;
      root.timerTotalSeconds = root.timerRemainingSeconds;
      root.timerStartTimestamp = root.timestamp;
      root.timerPausedAt = 0;
    }
  }

  function timerPause() {
    if (root.timerRunning) {
      // Calculate and set remainingSeconds BEFORE changing timerRunning
      // This ensures the UI sees the correct value when it reacts to timerRunning changing
      if (root.timerStopwatchMode) {
        root.timerPausedAt = root.timerElapsedSeconds;
      } else {
        // Calculate remaining seconds at the exact moment of pause
        // Use current time directly to avoid stale timestamp issues
        const currentTimestamp = Math.floor(Date.now() / 1000);
        const elapsedSinceStart = currentTimestamp - root.timerStartTimestamp;
        const currentRemaining = root.timerTotalSeconds - elapsedSinceStart;
        root.timerPausedAt = Math.max(0, currentRemaining);

        // CRITICAL: Update timerRemainingSeconds to the paused value BEFORE changing timerRunning
        // This ensures UI sees correct value when it reacts to timerRunning change
        root.timerRemainingSeconds = root.timerPausedAt;
      }
    }
    root.timerRunning = false;
    root.timerStartTimestamp = 0;
    // Stop any repeating notification sound when pausing
    SoundService.stopSound("alarm-beep.wav");
    root.timerSoundPlaying = false;
  }

  function timerReset() {
    root.timerRunning = false;
    root.timerStartTimestamp = 0;
    if (root.timerStopwatchMode) {
      root.timerElapsedSeconds = 0;
      root.timerPausedAt = 0;
    } else {
      root.timerRemainingSeconds = 0;
      root.timerTotalSeconds = 0;
      root.timerPausedAt = 0;
    }
    // Stop any repeating notification sound
    SoundService.stopSound("alarm-beep.wav");
    root.timerSoundPlaying = false;
  }

  function timerOnFinished() {
    root.timerRunning = false;
    root.timerRemainingSeconds = 0;
    // Play notification sound with repeat at lower volume
    root.timerSoundPlaying = true;
    SoundService.playSound("alarm-beep.wav", {
                             repeat: true,
                             volume: 0.3
                           });
  }
}
