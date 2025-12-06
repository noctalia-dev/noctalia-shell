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
        // Only allow editing when:
        // 1. Not in stopwatch mode
        // 2. Timer is not running
        // 3. Timer has never been started (totalSeconds == 0) - this includes after reset
        // This prevents editing when paused (when totalSeconds > 0)
        readOnly: isStopwatchMode || isRunning || totalSeconds > 0
        enabled: !isRunning && !isStopwatchMode && totalSeconds === 0
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
        // Use a computed property that explicitly tracks dependencies
        property string _cachedText: ""
        property int _textUpdateCounter: 0

        function updateText() {
          if (isStopwatchMode) {
            _cachedText = formatTime(elapsedSeconds, false);
          } else if (timerDisplayItem.isEditing && timerDisplayItem.inputBuffer !== "") {
            // Only use editing mode if we actually have input buffer content
            _cachedText = formatTimeFromDigits(timerDisplayItem.inputBuffer);
          } else {
            // When not editing OR when paused (not running), show the actual remaining time
            _cachedText = formatTime(remainingSeconds, isRunning);
          }
          _textUpdateCounter = _textUpdateCounter + 1;
        }

        text: {
          // Reference counter to force binding re-evaluation
          const counter = _textUpdateCounter;
          return _cachedText;
        }

        // Watch for changes to all relevant properties
        Connections {
          target: root
          function onRemainingSecondsChanged() {
            // Update immediately when remainingSeconds changes
            timerInput.updateText();
          }
          function onIsRunningChanged() {
            // When isRunning changes, update twice - once immediately and once after a delay
            // This ensures we catch the update even if remainingSeconds changes at the same time
            timerInput.updateText();
            Qt.callLater(() => {
                           timerInput.updateText();
                         });
          }
          function onElapsedSecondsChanged() {
            timerInput.updateText();
          }
          function onIsStopwatchModeChanged() {
            timerInput.updateText();
          }
        }

        // Also watch Time.timerRemainingSeconds directly as a backup
        Connections {
          target: Time
          function onTimerRemainingSecondsChanged() {
            timerInput.updateText();
          }
        }

        Connections {
          target: timerDisplayItem
          function onIsEditingChanged() {
            timerInput.updateText();
          }
        }

        // Initialize text on component completion
        Component.onCompleted: updateText()

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
            timerDisplayItem.inputBuffer = "";
          } else {
            applyTimeFromBuffer();
            timerDisplayItem.isEditing = false;
            timerDisplayItem.inputBuffer = "";
          }
        }

        MouseArea {
          anchors.fill: parent
          // Only allow clicking to edit when timer hasn't been started or has been reset
          enabled: !isRunning && !isStopwatchMode && totalSeconds === 0
          cursorShape: enabled ? Qt.IBeamCursor : Qt.ArrowCursor
          onClicked: {
            if (!isRunning && !isStopwatchMode && totalSeconds === 0) {
              timerInput.forceActiveFocus();
            }
          }
        }
      }
    }

    // Control buttons
    RowLayout {
      id: buttonRow
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
        implicitHeight: resetButton.implicitHeight
        color: Color.transparent

        NButton {
          id: resetButton
          anchors.fill: parent
          text: I18n.tr("calendar.timer.reset")
          icon: "refresh"
          enabled: (isStopwatchMode && (elapsedSeconds > 0 || isRunning)) || (!isStopwatchMode && (remainingSeconds > 0 || isRunning || soundPlaying))
          onClicked: {
            resetTimer();
          }
        }
      }
    }

    // Mode tabs (Android-style) - below buttons
    // Match width and height exactly with the control buttons above
    NTabBar {
      id: modeTabBar
      Layout.fillWidth: true
      Layout.preferredWidth: buttonRow.width
      Layout.preferredHeight: startButton.implicitHeight
      implicitHeight: startButton.implicitHeight
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
      // Match spacing exactly with button row
      spacing: Style.marginS

      // Access internal RowLayout to remove margins so spacing matches button row
      Component.onCompleted: {
        // The NTabBar has a RowLayout child (tabRow) with margins
        // We need to remove those margins to match the button row spacing
        Qt.callLater(() => {
                       if (modeTabBar.children && modeTabBar.children.length > 0) {
                         for (var i = 0; i < modeTabBar.children.length; i++) {
                           var child = modeTabBar.children[i];
                           // Look for RowLayout (it will have spacing property)
                           if (child && typeof child.spacing !== 'undefined' && child.anchors) {
                             child.anchors.margins = 0;
                             break;
                           }
                         }
                       }
                     });
      }

      NTabButton {
        text: I18n.tr("calendar.timer.countdown")
        tabIndex: 0
        checked: !isStopwatchMode
        radius: Style.iRadiusS
      }

      NTabButton {
        text: I18n.tr("calendar.timer.stopwatch")
        tabIndex: 1
        checked: isStopwatchMode
        radius: Style.iRadiusS
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
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;

    // If hideHoursWhenZero is true (when running), only show hours if > 0
    // Otherwise (when not running or editing), always show hours
    if (hideHoursWhenZero && hours === 0) {
      return `${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }
    return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }

  function formatTimeFromDigits(digits) {
    // Parse digits right-to-left: last 2 = seconds, next 2 = minutes, rest = hours
    const len = digits.length;
    let seconds = 0;
    let minutes = 0;
    let hours = 0;

    if (len > 0) {
      seconds = parseInt(digits.substring(Math.max(0, len - 2))) || 0;
    }
    if (len > 2) {
      minutes = parseInt(digits.substring(Math.max(0, len - 4), len - 2)) || 0;
    }
    if (len > 4) {
      hours = parseInt(digits.substring(0, len - 4)) || 0;
    }

    // Clamp values
    seconds = Math.min(59, seconds);
    minutes = Math.min(59, minutes);
    hours = Math.min(99, hours);

    // Always show HH:MM:SS format in edit mode
    return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }

  function parseDigitsToTime(digits) {
    // Parse digits right-to-left: last 2 = seconds, next 2 = minutes, rest = hours
    const len = digits.length;
    let seconds = 0;
    let minutes = 0;
    let hours = 0;

    if (len > 0) {
      seconds = parseInt(digits.substring(Math.max(0, len - 2))) || 0;
    }
    if (len > 2) {
      minutes = parseInt(digits.substring(Math.max(0, len - 4), len - 2)) || 0;
    }
    if (len > 4) {
      hours = parseInt(digits.substring(0, len - 4)) || 0;
    }

    // Clamp values
    seconds = Math.min(59, seconds);
    minutes = Math.min(59, minutes);
    hours = Math.min(99, hours);

    Time.timerRemainingSeconds = (hours * 3600) + (minutes * 60) + seconds;
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
    // Clear editing state when reset
    timerDisplayItem.isEditing = false;
    timerDisplayItem.inputBuffer = "";
    timerInput.focus = false;
  }
}
