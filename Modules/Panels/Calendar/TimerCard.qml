import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Widgets

// Timer card for the Calendar panel
NBox {
  id: root

  implicitHeight: content.implicitHeight + (Style.marginM * 2)
  Layout.fillWidth: true
  clip: true

  enum TabMode {
    Countdown,
    Pomodoro,
    Stopwatch
  }

  // Detect pomodoro phase changes
  Connections {
    target: Time

    function onTimerRunningChanged() {
      if (!Time.timerRunning && Time.timerRemainingSeconds === 0 && modeTabs.currentIndex === TimerCard.TabMode.Pomodoro) {
        root.advancePomodoroPhase();
        Time.timerStart();
        SoundService.playSound(Settings.data.timer.alarmSound);
      }
    }

    // Fixes "First Time" loop / Race Condition
    function onTimerSoundPlayingChanged() {
      if (Time.timerSoundPlaying && modeTabs.currentIndex === TimerCard.TabMode.Pomodoro) {

        // Stop only looping sounds (leaving our one-shot from above playing)
        SoundService.stopSound();
        Time.timerSoundPlaying = false;
      }
    }
  }

  ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginM
    clip: true

    // Header
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NIcon {
        icon: {
          if (modeTabs.currentIndex === TimerCard.TabMode.Pomodoro)
            return "brain";
          if (modeTabs.currentIndex === TimerCard.TabMode.Stopwatch)
            return "stopwatch";
          return "hourglass";
        }
        pointSize: Style.fontSizeL
        color: Color.mPrimary
      }

      NText {
        text: I18n.tr("calendar.timer.title")
        pointSize: Style.fontSizeL
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
        Layout.fillWidth: true
      }

      // Pomodoro Status Badge
      NBox {
        visible: modeTabs.currentIndex === TimerCard.TabMode.Pomodoro
        color: Qt.lighter(Color.mSurfaceVariant, 1.1)
        border.width: 0

        implicitWidth: pomoLabel.implicitWidth + Style.marginL
        implicitHeight: pomoLabel.implicitHeight + Style.marginXS

        NText {
          id: pomoLabel
          anchors.centerIn: parent
          text: root.isWorkPhase ? I18n.tr("calendar.timer.pomodoro") + " #" + root.pomodoroCycle : (root.pomodoroCycle % 4 === 0 ? I18n.tr("calendar.timer.longBreak") : I18n.tr("calendar.timer.shortBreak"))
          font.pointSize: Style.fontSizeS
          font.weight: Style.fontWeightBold
          color: root.isWorkPhase ? Color.mPrimary : Color.mTertiary
        }
      }
    }

    // Timer display (editable when not running)
    NBox {
      id: timerDisplayItem
      Layout.fillWidth: true
      Layout.preferredHeight: isRunning ? Math.max(160 * Style.uiScaleRatio, timerInput.contentWidth + 60) : timerInput.implicitHeight
      Layout.alignment: Qt.AlignHCenter
      readonly property bool showHighlight: (displayMouseArea.containsMouse || isEditing) && !isRunning && modeTabs.currentIndex === TimerCard.TabMode.Countdown
      color: showHighlight ? Color.mSurfaceVariant : "transparent"
      border.width: showHighlight ? Style.borderS : 0

      property string inputBuffer: ""
      property bool isEditing: false

      // Circular progress ring (only for countdown mode when running)
      Canvas {
        id: progressRing
        anchors.fill: parent
        anchors.margins: 12
        visible: modeTabs.currentIndex !== TimerCard.TabMode.Stopwatch && isRunning
        z: -1

        property real progressRatio: {
          if (totalSeconds <= 0)
            return 0;
          // Inverted: show remaining time (starts at 1, goes to 0)
          const ratio = remainingSeconds / totalSeconds;
          return Math.max(0, Math.min(1, ratio));
        }

        onProgressRatioChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d");
          if (width <= 0 || height <= 0) {
            return;
          }

          var centerX = width / 2;
          var centerY = height / 2;
          var radius = Math.max(0, Math.min(width, height) / 2 - 6);

          ctx.reset();

          // Background circle (full track)
          ctx.beginPath();
          ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
          ctx.lineWidth = 4;
          ctx.strokeStyle = Qt.alpha(Color.mOnSurface, 0.2);
          ctx.stroke();

          // Progress arc (elapsed portion)
          if (progressRatio > 0) {
            ctx.beginPath();
            ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + progressRatio * 2 * Math.PI);
            ctx.lineWidth = 4;
            ctx.strokeStyle = (modeTabs.currentIndex === TimerCard.TabMode.Pomodoro && !root.isWorkPhase) ? Color.mTertiary : Color.mPrimary;
            ctx.lineCap = "round";
            ctx.stroke();
          }
        }
      }

      TextInput {
        id: timerInput
        anchors.centerIn: parent
        width: Math.max(implicitWidth, parent.width)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        selectByMouse: false
        cursorVisible: timerDisplayItem.isEditing || displayMouseArea.containsMouse
        readOnly: modeTabs.currentIndex !== TimerCard.TabMode.Countdown || isRunning
        enabled: !isRunning
        font.family: Settings.data.ui.fontFixed

        // Calculate if hours are being shown
        readonly property bool showingHours: {
          if (modeTabs.currentIndex === TimerCard.TabMode.Stopwatch) {
            return elapsedSeconds >= 3600;
          }
          // In edit mode, always show hours (HH:MM:SS format)
          if (timerDisplayItem.isEditing) {
            return true;
          }
          // When not editing, only show hours if >= 1 hour
          return remainingSeconds >= 3600;
        }

        font.pointSize: {
          if (!isRunning) {
            return Style.fontSizeXXXL;
          }
          // When running, use smaller font if hours are shown
          return showingHours ? Style.fontSizeXXL : (Style.fontSizeXXL * 1.2);
        }

        font.weight: Style.fontWeightBold
        color: {
          if (isRunning) {
            return Color.mPrimary;
          }
          if (timerDisplayItem.isEditing) {
            return Color.mPrimary;
          }
          return Color.mOnSurface;
        }

        // Display formatted time, but show input buffer when editing
        text: {
          if (modeTabs.currentIndex === TimerCard.TabMode.Stopwatch) {
            return formatTime(elapsedSeconds, false);
          }
          if (!timerDisplayItem.isEditing || timerDisplayItem.inputBuffer === "") {
            return formatTime(remainingSeconds, isRunning);
          }
          return formatHMS(parseDigits(timerDisplayItem.inputBuffer), ":");
        }

        // Only accept digit keys
        Keys.onPressed: event => {
          if (isRunning || modeTabs.currentIndex !== TimerCard.TabMode.Countdown) {
            event.accepted = true;
            return;
          }

          // Handle backspace
          if (event.key === Qt.Key_Backspace) {
            if (timerDisplayItem.isEditing && timerDisplayItem.inputBuffer.length > 0) {
              timerDisplayItem.inputBuffer = timerDisplayItem.inputBuffer.slice(0, -1);
              if (timerDisplayItem.inputBuffer !== "") {
                parseDigitsToTime(timerDisplayItem.inputBuffer);
              } else {
                Time.timerRemainingSeconds = 0;
              }
            }
            event.accepted = true;
            return;
          }

          // Handle delete
          if (event.key === Qt.Key_Delete) {
            if (timerDisplayItem.isEditing) {
              timerDisplayItem.inputBuffer = "";
              Time.timerRemainingSeconds = 0;
            }
            event.accepted = true;
            return;
          }

          // Allow navigation keys (but don't let them modify text)
          if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Home || event.key === Qt.Key_End || (event.modifiers & Qt.ControlModifier) || (event.modifiers & Qt.ShiftModifier)) {
            event.accepted = false;
            return;
          }

          // Handle enter/return
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            applyTimeFromBuffer();
            timerDisplayItem.isEditing = false;
            focus = false;
            event.accepted = true;
            return;
          }

          // Handle escape
          if (event.key === Qt.Key_Escape) {
            timerDisplayItem.inputBuffer = "";
            Time.timerRemainingSeconds = 0;
            timerDisplayItem.isEditing = false;
            focus = false;
            event.accepted = true;
            return;
          }

          // Only allow digits 0-9
          if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            if (timerDisplayItem.inputBuffer.length >= 6) {
              event.accepted = true;
              return;
            }
            timerDisplayItem.inputBuffer += String.fromCharCode(event.key);
            parseDigitsToTime(timerDisplayItem.inputBuffer);
            event.accepted = true;
          } else {
            event.accepted = true;
          }
        }

        Keys.onReturnPressed: {
          applyTimeFromBuffer();
          timerDisplayItem.isEditing = false;
          focus = false;
        }

        Keys.onEscapePressed: {
          timerDisplayItem.inputBuffer = "";
          Time.timerRemainingSeconds = 0;
          timerDisplayItem.isEditing = false;
          focus = false;
        }

        onActiveFocusChanged: {
          if (activeFocus) {
            timerDisplayItem.isEditing = true;
            const val = parseInt(formatHMS(getHMS(remainingSeconds), ""));
            timerDisplayItem.inputBuffer = val > 0 ? val.toString() : "";
          } else {
            applyTimeFromBuffer();
            timerDisplayItem.isEditing = false;
            timerDisplayItem.inputBuffer = "";
          }
        }

        MouseArea {
          id: displayMouseArea
          hoverEnabled: true
          anchors.fill: parent
          enabled: !isRunning && modeTabs.currentIndex === TimerCard.TabMode.Countdown
          cursorShape: enabled ? Qt.IBeamCursor : Qt.ArrowCursor
          onClicked: {
            if (!isRunning && modeTabs.currentIndex === TimerCard.TabMode.Countdown) {
              timerInput.forceActiveFocus();
            }
          }
        }
      }
    }

    // Control buttons
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        implicitHeight: startButton.implicitHeight
        color: Color.transparent

        NButton {
          id: startButton
          anchors.fill: parent
          text: isRunning ? I18n.tr("calendar.timer.pause") : I18n.tr("calendar.timer.start")
          icon: isRunning ? "player-pause" : "player-play"
          enabled: modeTabs.currentIndex === TimerCard.TabMode.Stopwatch || remainingSeconds > 0
          onClicked: {
            if (isRunning) {
              Time.timerPause();
            } else {
              Time.timerStart();
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        implicitHeight: startButton.implicitHeight
        color: Color.transparent
        visible: modeTabs.currentIndex == TimerCard.TabMode.Countdown

        NButton {
          id: addButton
          anchors.fill: parent
          text: "+ " + formatDuration(Settings.data.timer.skipValue)
          icon: {
            // Change icon for specific value that Tabler.io supports
            if ([5, 10, 15, 20, 30, 40, 50, 60].includes(Settings.data.timer.skipValue)) {
              return "rewind-forward-" + Settings.data.timer.skipValue;
            }
            return "arrow-forward-up";
          }
          enabled: modeTabs.currentIndex == TimerCard.TabMode.Countdown
          onClicked: {
            if (timerDisplayItem.isEditing) {
              var baseSeconds = 0;
              if (timerDisplayItem.inputBuffer !== "") {
                var t = parseDigits(timerDisplayItem.inputBuffer);
                baseSeconds = (t.h * 3600) + (t.m * 60) + t.s;
              } else {
                baseSeconds = remainingSeconds;
              }

              var newSeconds = baseSeconds + Settings.data.timer.skipValue;
              var tNew = getHMS(newSeconds);
              var str = formatHMS(tNew, "");
              timerDisplayItem.inputBuffer = parseInt(str).toString();
              parseDigitsToTime(timerDisplayItem.inputBuffer);
            } else {
              Time.timerTotalSeconds += Settings.data.timer.skipValue;
              Time.timerRemainingSeconds += Settings.data.timer.skipValue;
            }
          }
        }
      }
      // Restart Phase Button (Pomodoro Only)
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        implicitHeight: restartButton.implicitHeight
        color: Color.transparent
        visible: modeTabs.currentIndex === TimerCard.TabMode.Pomodoro

        NButton {
          id: restartButton
          anchors.fill: parent
          text: "Restart"
          icon: "rotate-clockwise"

          onClicked: {
            var wasRunning = isRunning;
            if (isRunning)
              Time.timerPause();
            resetTimer();
            var duration = root.isWorkPhase ? Settings.data.timer.pomodoro : (root.pomodoroCycle % 4 === 0 ? Settings.data.timer.longRest : Settings.data.timer.shortRest);
            setTimerPreset(duration);
            if (wasRunning)
              Time.timerStart();
          }
        }
      }

      // Reset Button
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        implicitHeight: resetButton.implicitHeight
        color: Color.transparent

        NButton {
          id: resetButton
          anchors.fill: parent
          text: I18n.tr("calendar.timer.reset")
          icon: "refresh"
          enabled: (modeTabs.currentIndex === TimerCard.TabMode.Stopwatch && (elapsedSeconds > 0 || isRunning)) || (modeTabs.currentIndex !== TimerCard.TabMode.Stopwatch && (remainingSeconds > 0 || isRunning || soundPlaying))

          onClicked: {
            resetTimer();
            if (modeTabs.currentIndex === TimerCard.TabMode.Pomodoro) {
              root.isWorkPhase = true;
              root.pomodoroCycle = 1;
              setTimerPreset(Settings.data.timer.pomodoro);
            }
          }
        }
      }
    }

    // Mode tabs (Android-style) - below buttons
    NTabBar {
      id: modeTabs
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      visible: !isRunning
      spacing: Style.marginXS

      currentIndex: Time.timerStopwatchMode ? TimerCard.TabMode.Stopwatch : TimerCard.TabMode.Countdown

      onCurrentIndexChanged: {
        if (isRunning)
          Time.timerPause();
        SoundService.stopSound(Settings.data.timer.alarmSound);
        Time.timerSoundPlaying = false;
        const isStopwatch = (currentIndex === TimerCard.TabMode.Stopwatch);
        Time.timerStopwatchMode = isStopwatch;

        // Reset Counters
        if (isStopwatch) {
          Time.timerElapsedSeconds = 0;
        } else if (currentIndex === TimerCard.TabMode.Pomodoro) {
          root.isWorkPhase = true;
          root.pomodoroCycle = 1;
          setTimerPreset(Settings.data.timer.pomodoro);
        } else {
          Time.timerRemainingSeconds = 0;
        }
      }

      NTabButton {
        text: I18n.tr("calendar.timer.countdown")
        tabIndex: TimerCard.TabMode.Countdown
      }

      NTabButton {
        text: I18n.tr("calendar.timer.pomodoro")
        tabIndex: TimerCard.TabMode.Pomodoro
      }

      NTabButton {
        text: I18n.tr("calendar.timer.stopwatch")
        tabIndex: TimerCard.TabMode.Stopwatch
      }
    }
  }

  // Bind to Time for persistent timer state
  readonly property bool isRunning: Time.timerRunning
  property bool isStopwatchMode: Time.timerStopwatchMode
  readonly property int remainingSeconds: Time.timerRemainingSeconds
  readonly property int totalSeconds: Time.timerTotalSeconds
  readonly property int elapsedSeconds: Time.timerElapsedSeconds
  readonly property bool soundPlaying: Time.timerSoundPlaying

  // Pomodoro State
  property bool isWorkPhase: true
  property int pomodoroCycle: 1

  function formatTime(seconds, hideHoursWhenZero) {
    const t = getHMS(seconds);
    if (hideHoursWhenZero && t.h === 0) {
      return `${pad(t.m)}:${pad(t.s)}`;
    }
    return formatHMS(t, ":");
  }

  // Standardizes 0-padding
  function pad(val) {
    return val.toString().padStart(2, '0');
  }

  // Standardizes combining H/M/S with a separator (or empty string)
  function formatHMS(t, separator) {
    return `${pad(t.h)}${separator}${pad(t.m)}${separator}${pad(t.s)}`;
  }

  // Decomposes total seconds into {h, m, s}
  function getHMS(totalSeconds) {
    return {
      h: Math.floor(totalSeconds / 3600),
      m: Math.floor((totalSeconds % 3600) / 60),
      s: Math.floor(totalSeconds % 60)
    };
  }

  // Parses raw digit string (e.g. "123") into {h, m, s} for input editing
  function parseDigits(digits) {
    const len = digits.length;
    let s = 0, m = 0, h = 0;

    if (len > 0)
      s = parseInt(digits.substring(Math.max(0, len - 2))) || 0;
    if (len > 2)
      m = parseInt(digits.substring(Math.max(0, len - 4), len - 2)) || 0;
    if (len > 4)
      h = parseInt(digits.substring(0, len - 4)) || 0;

    return {
      h: Math.min(99, h) // Clamp hours
      ,
      m: Math.min(59, m) // Clamp minutes
      ,
      s: Math.min(59, s)  // Clamp seconds
    };
  }

  // Helper to extract H/M/S from raw digits string
  function parseDigitsToTime(digits) {
    const t = parseDigits(digits);
    Time.timerRemainingSeconds = (t.h * 3600) + (t.m * 60) + t.s;
  }

  function formatDuration(totalSeconds) {
    const t = getHMS(totalSeconds);
    const parts = [];

    if (t.h > 0)
      parts.push(t.h + "h");
    if (t.m > 0)
      parts.push(t.m + "m");
    if (t.s > 0 || parts.length === 0)
      parts.push(t.s + "s");

    return parts.join(" ");
  }

  function applyTimeFromBuffer() {
    if (timerDisplayItem.inputBuffer !== "") {
      parseDigitsToTime(timerDisplayItem.inputBuffer);
      timerDisplayItem.inputBuffer = "";
    }
  }

  function setTimerPreset(seconds) {
    Time.timerRemainingSeconds = seconds;
    Time.timerTotalSeconds = seconds;
  }

  function advancePomodoroPhase() {
    if (isWorkPhase) {
      // Switch to Break
      if (pomodoroCycle % 4 === 0) {
        setTimerPreset(Settings.data.timer.longRest);
      } else {
        setTimerPreset(Settings.data.timer.shortRest);
      }
      isWorkPhase = false;
    } else {
      // Switch to Work
      if (pomodoroCycle % 4 === 0)
        pomodoroCycle = 0;
      pomodoroCycle++;
      setTimerPreset(Settings.data.timer.pomodoro);
      isWorkPhase = true;
    }
  }

  function resetTimer() {
    timerDisplayItem.inputBuffer = "";
    timerDisplayItem.isEditing = false;
    timerInput.focus = false;
    if (Time.timerSoundPlaying) {
      SoundService.stopSound();
      Time.timerSoundPlaying = false;
    }
    Time.timerReset();
  }
}
