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
        icon: isStopwatchMode ? "clock" : "hourglass"
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
    }

    // Timer display (editable when not running)
    Item {
      id: timerDisplayItem
      Layout.fillWidth: true
      Layout.preferredHeight: isRunning ? 160 * Style.uiScaleRatio : timerInput.implicitHeight
      Layout.alignment: Qt.AlignHCenter

      property string inputBuffer: ""
      property bool isEditing: false

      // Circular progress ring (only for countdown mode when running)
      Canvas {
        id: progressRing
        anchors.fill: parent
        anchors.margins: 12
        visible: !isStopwatchMode && isRunning && totalSeconds > 0
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
            ctx.strokeStyle = Color.mPrimary;
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
        cursorVisible: false
        cursorDelegate: Item {} // Empty cursor delegate to hide cursor
        readOnly: isStopwatchMode || isRunning
        enabled: !isRunning
        font.family: Settings.data.ui.fontFixed

        // Calculate if hours are being shown
        readonly property bool showingHours: {
          if (isStopwatchMode) {
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
          if (isStopwatchMode) {
            return formatTime(elapsedSeconds, false);
          }

          // FIX: If not editing OR if editing but haven't typed anything yet, show the current time
          if (!timerDisplayItem.isEditing || timerDisplayItem.inputBuffer === "") {
            return formatTime(remainingSeconds, isRunning);
          }

          // Only show the buffer processing if we actually have input
          return formatTimeFromDigits(timerDisplayItem.inputBuffer);
        }

        // Only accept digit keys
        Keys.onPressed: event => {
          if (isRunning || isStopwatchMode) {
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
            event.accepted = false; // Let default handling work for selection
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
            // Limit to 6 digits max
            if (timerDisplayItem.inputBuffer.length >= 6) {
              event.accepted = true; // Block if already at max
              return;
            }
            // Add the digit to the buffer
            timerDisplayItem.inputBuffer += String.fromCharCode(event.key);
            // Update the display and parse
            parseDigitsToTime(timerDisplayItem.inputBuffer);
            event.accepted = true; // We handled it
          } else {
            event.accepted = true; // Block all other keys
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
          anchors.fill: parent
          enabled: !isRunning && !isStopwatchMode
          cursorShape: enabled ? Qt.IBeamCursor : Qt.ArrowCursor
          onClicked: {
            if (!isRunning && !isStopwatchMode) {
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
          enabled: isStopwatchMode || remainingSeconds > 0
          onClicked: {
            if (isRunning) {
              pauseTimer();
            } else {
              startTimer();
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        implicitHeight: startButton.implicitHeight
        color: Color.transparent
        visible: !isStopwatchMode

        NButton {
          id: addButton
          anchors.fill: parent
          // property var skipValue: 99
          text: "+ " + formatDuration(Settings.data.timer.skipValue) //formatTime(skipValue, true)

          icon: {
            // Change icon for specific value that Tabler.io supports
            if ([5, 10, 15, 20, 30, 40, 50, 60].includes(Settings.data.timer.skipValue)) {
              return "rewind-forward-" + Settings.data.timer.skipValue;
            }
            return "arrow-forward-up";
          }
          enabled: !isStopwatchMode
          onClicked: {
            Time.timerTotalSeconds += Settings.data.timer.skipValue;
            Time.timerRemainingSeconds += Settings.data.timer.skipValue;
          }
        }
      }

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
          enabled: (isStopwatchMode && (elapsedSeconds > 0 || isRunning)) || (!isStopwatchMode && (remainingSeconds > 0 || isRunning || soundPlaying))
          onClicked: {
            timerDisplayItem.inputBuffer = "";
            timerDisplayItem.isEditing = false;
            timerInput.focus = false;
            resetTimer();
          }
        }
      }
    }

    // Mode tabs (Android-style) - below buttons
    NTabBar {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      visible: !isRunning
      currentIndex: isStopwatchMode ? 1 : 0
      onCurrentIndexChanged: {
        const newMode = currentIndex === 1;
        if (newMode !== isStopwatchMode) {
          if (isRunning) {
            pauseTimer();
          }
          // Stop any repeating notification sound when switching modes
          SoundService.stopSound("alarm-beep.wav");
          Time.timerSoundPlaying = false;
          Time.timerStopwatchMode = newMode;
          if (newMode) {
            // Reset to 0 for stopwatch
            Time.timerElapsedSeconds = 0;
          } else {
            Time.timerRemainingSeconds = 0;
          }
        }
      }
      spacing: Style.marginXS

      NTabButton {
        text: I18n.tr("calendar.timer.countdown")
        tabIndex: 0
        checked: !isStopwatchMode
      }

      NTabButton {
        text: I18n.tr("calendar.timer.stopwatch")
        tabIndex: 1
        checked: isStopwatchMode
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

  function formatTime(seconds, hideHoursWhenZero) {
    const t = getHMS(seconds);
    if (hideHoursWhenZero && t.h === 0) {
      return `${pad(t.m)}:${pad(t.s)}`;
    }
    return formatHMS(t, ":");
  }

  // Standardizes 0-padding (e.g. 5 -> "05")
  function pad(val) {
    return val.toString().padStart(2, '0');
  }

  // Combines H/M/S with a separator
  function formatTimeFromDigits(digits) {
    return formatHMS(parseDigits(digits), ":");
  }

  // NEW: Standardizes combining H/M/S with a separator (or empty string)
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

  function startTimer() {
    Time.timerStart();
  }

  function pauseTimer() {
    Time.timerPause();
  }

  function resetTimer() {
    Time.timerReset();
  }
}
