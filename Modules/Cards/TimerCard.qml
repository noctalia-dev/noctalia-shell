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
      Layout.preferredHeight: (totalSeconds > 0) ? 160 * Style.uiScaleRatio : timerInput.implicitHeight
      Layout.topMargin: Style.marginM
      Layout.bottomMargin: Style.marginM
      Layout.alignment: Qt.AlignHCenter

      property string inputBuffer: ""
      property bool isEditing: false

      // Wheel handler for adjusting time in 5 second steps
      WheelHandler {
        id: timerWheelHandler
        target: timerDisplayItem
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: !isRunning && !isStopwatchMode && totalSeconds === 0
        onWheel: function (event) {
          if (!enabled) {
            return;
          }
          const step = 5;
          if (event.angleDelta.y > 0) {
            Time.timerRemainingSeconds = Math.max(0, Time.timerRemainingSeconds + step);
            event.accepted = true;
          } else if (event.angleDelta.y < 0) {
            Time.timerRemainingSeconds = Math.max(0, Time.timerRemainingSeconds - step);
            event.accepted = true;
          }
        }
      }

      Rectangle {
        id: textboxBorder
        anchors.centerIn: parent
        anchors.margins: Style.marginM
        width: Math.max(timerInput.implicitWidth + Style.marginM * 2, parent.width * 0.8)
        height: timerInput.implicitHeight + Style.marginM * 2
        radius: Style.iRadiusM
        color: Color.mSurface
        border.color: (timerInput.activeFocus || timerDisplayItem.isEditing) ? Color.mPrimary : Color.mOutline
        border.width: Style.borderS
        visible: !isRunning && !isStopwatchMode && totalSeconds === 0
        z: 0

        Behavior on border.color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }
      }

      // Circular progress ring (only for countdown mode when running or paused)
      Canvas {
        id: progressRing
        anchors.fill: parent
        anchors.margins: 12
        visible: !isStopwatchMode && totalSeconds > 0
        z: -1

        property real progressRatio: {
          if (totalSeconds <= 0)
            return 0;
          // Inverted: show remaining time (starts at 1, goes to 0)
          const ratio = remainingSeconds / totalSeconds;
          return Math.max(0, Math.min(1, ratio));
        }

        // Check if hours are being shown (for radius calculation)
        readonly property bool showingHours: {
          if (isStopwatchMode) {
            return elapsedSeconds >= 3600;
          }
          return totalSeconds >= 3600;
        }

        onProgressRatioChanged: requestPaint()
        onShowingHoursChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d");
          if (width <= 0 || height <= 0) {
            return;
          }

          var centerX = width / 2;
          var centerY = height / 2;
          var radiusOffset = showingHours ? 6 : 16;
          var radius = Math.max(0, Math.min(width, height) / 2 - radiusOffset);

          ctx.reset();

          ctx.beginPath();
          ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
          ctx.lineWidth = 4;
          ctx.strokeStyle = Qt.alpha(Color.mOnSurface, 0.2);
          ctx.stroke();

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

      Item {
        id: timerContainer
        anchors.centerIn: parent
        width: timerInput.implicitWidth
        height: timerInput.implicitHeight + 8 // Always reserve space for underline

        TextInput {
          id: timerInput
          anchors.verticalCenter: parent.verticalCenter
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.max(implicitWidth, timerDisplayItem.width)
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

          // Calculate if hours are being shown (for font sizing)
          readonly property bool showingHours: {
            if (isStopwatchMode) {
              return elapsedSeconds >= 3600;
            }
            // In edit mode, always show hours (HH:MM:SS format)
            if (timerDisplayItem.isEditing) {
              return true;
            }
            // Show hours if total time >= 1 hour (formatting will show HH:MM:SS)
            return totalSeconds >= 3600;
          }

          font.pointSize: {
            if (totalSeconds === 0) {
              return Style.fontSizeXXXL;
            }
            // When running or paused, use smaller font if hours are shown
            return showingHours ? Style.fontSizeXXL : (Style.fontSizeXXL * 1.2);
          }

          font.weight: Style.fontWeightBold
          color: {
            if (totalSeconds > 0) {
              return Color.mPrimary;
            }
            if (timerDisplayItem.isEditing) {
              return Color.mPrimary;
            }
            return Color.mOnSurface;
          }

          // Use a computed property that explicitly tracks dependencies
          property string _cachedText: ""
          property int _textUpdateCounter: 0

          function updateText() {
            if (isStopwatchMode) {
              // For stopwatch, use elapsedSeconds as the reference for formatting
              _cachedText = formatTime(elapsedSeconds, elapsedSeconds);
            } else if (timerDisplayItem.isEditing && timerDisplayItem.inputBuffer !== "") {
              // Only use editing mode if we actually have input buffer content
              _cachedText = formatTimeFromDigits(timerDisplayItem.inputBuffer);
            } else if (timerDisplayItem.isEditing) {
              // When editing but buffer is empty, show placeholder (00:00:00)
              _cachedText = formatTime(0, 0);
            } else {
              _cachedText = formatTime(remainingSeconds, totalSeconds);
            }
            _textUpdateCounter = _textUpdateCounter + 1;
          }

          text: {
            const counter = _textUpdateCounter;
            return _cachedText;
          }

          Connections {
            target: root
            function onRemainingSecondsChanged() {
              timerInput.updateText();
            }
            function onIsRunningChanged() {
              // Update twice to catch updates even if remainingSeconds changes at the same time
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

          Component.onCompleted: updateText()

          Keys.onPressed: event => {
                            if (isRunning || isStopwatchMode || totalSeconds > 0) {
                              event.accepted = true;
                              return;
                            }

                            const keyText = event.text;

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

                            if (event.key === Qt.Key_Delete) {
                              if (timerDisplayItem.isEditing) {
                                timerDisplayItem.inputBuffer = "";
                                Time.timerRemainingSeconds = 0;
                              }
                              event.accepted = true;
                              return;
                            }

                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                              applyTimeFromBuffer();
                              timerDisplayItem.isEditing = false;
                              focus = false;
                              event.accepted = true;
                              return;
                            }

                            if (event.key === Qt.Key_Escape) {
                              timerDisplayItem.inputBuffer = "";
                              Time.timerRemainingSeconds = 0;
                              timerDisplayItem.isEditing = false;
                              focus = false;
                              event.accepted = true;
                              return;
                            }

                            // Only allow single digit characters 0-9 (check both key code and text)
                            const isDigitKey = event.key >= Qt.Key_0 && event.key <= Qt.Key_9;
                            const isDigitText = keyText.length === 1 && keyText >= '0' && keyText <= '9';

                            if (isDigitKey && isDigitText) {
                              if (timerDisplayItem.inputBuffer.length >= 6) {
                                event.accepted = true;
                                return;
                              }
                              timerDisplayItem.inputBuffer += keyText;
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
              timerDisplayItem.inputBuffer = "";
            } else {
              applyTimeFromBuffer();
              timerDisplayItem.isEditing = false;
              timerDisplayItem.inputBuffer = "";
            }
          }

          MouseArea {
            anchors.fill: parent
            enabled: !isRunning && !isStopwatchMode && totalSeconds === 0
            cursorShape: enabled ? Qt.IBeamCursor : Qt.ArrowCursor
            onClicked: {
              if (!isRunning && !isStopwatchMode && totalSeconds === 0) {
                timerInput.forceActiveFocus();
              }
            }
          }
        }

        Rectangle {
          id: editingUnderline
          anchors.top: timerInput.bottom
          anchors.topMargin: 2
          height: 3
          radius: 1.5
          color: Color.mPrimary
          visible: timerDisplayItem.isEditing && totalSeconds === 0

          // Calculate which digit position we're at (0-5 for HHMMSS)
          // We fill from right to left: empty buffer = position 5, "1" = position 5, "12" = position 4, etc.
          property int currentDigitPos: {
            const bufLen = timerDisplayItem.inputBuffer.length;
            if (bufLen === 0)
              return 5;
            return Math.max(0, 6 - bufLen);
          }

          // Map digit position to character position in "HH:MM:SS" (skip colons)
          property real digitWidth: timerInput.implicitWidth / 8
          property real xOffset: {
            const pos = currentDigitPos;
            let charPos = pos;
            if (pos >= 2)
              charPos++;
            if (pos >= 4)
              charPos++;
            return (charPos * digitWidth) - (timerInput.implicitWidth / 2);
          }

          x: parent.width / 2 + xOffset
          width: digitWidth * 0.8

          Behavior on x {
            NumberAnimation {
              duration: 150
              easing.type: Easing.OutQuad
            }
          }

          SequentialAnimation on opacity {
            running: editingUnderline.visible
            loops: Animation.Infinite
            NumberAnimation {
              from: 1.0
              to: 0.3
              duration: 600
            }
            NumberAnimation {
              from: 0.3
              to: 1.0
              duration: 600
            }
          }
        }
      }
    }

    RowLayout {
      id: buttonRow
      Layout.fillWidth: true
      spacing: Style.marginS

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        implicitHeight: startButton.implicitHeight
        color: "transparent"

        NButton {
          id: startButton
          anchors.fill: parent
          text: isRunning ? I18n.tr("calendar.timer.pause") : (totalSeconds > 0 ? I18n.tr("calendar.timer.resume") : I18n.tr("calendar.timer.start"))
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
        color: "transparent"

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

    NTabBar {
      id: modeTabBar
      Layout.fillWidth: true
      Layout.preferredHeight: startButton.implicitHeight
      implicitHeight: startButton.implicitHeight
      visible: totalSeconds === 0
      currentIndex: isStopwatchMode ? 1 : 0
      margins: 0
      distributeEvenly: true
      onCurrentIndexChanged: {
        const newMode = currentIndex === 1;
        if (newMode !== isStopwatchMode) {
          if (isRunning) {
            pauseTimer();
          }
          SoundService.stopSound("alarm-beep.wav");
          Time.timerSoundPlaying = false;
          Time.timerStopwatchMode = newMode;
          if (newMode) {
            Time.timerElapsedSeconds = 0;
          } else {
            Time.timerRemainingSeconds = 0;
          }
        }
      }
      spacing: Style.marginS

      Component.onCompleted: {
        // Remove margins from internal RowLayout to match button row spacing
        Qt.callLater(() => {
                       if (modeTabBar.children && modeTabBar.children.length > 0) {
                         for (var i = 0; i < modeTabBar.children.length; i++) {
                           var child = modeTabBar.children[i];
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

  readonly property bool isRunning: Time.timerRunning
  property bool isStopwatchMode: Time.timerStopwatchMode
  readonly property int remainingSeconds: Time.timerRemainingSeconds
  readonly property int totalSeconds: Time.timerTotalSeconds
  readonly property int elapsedSeconds: Time.timerElapsedSeconds
  readonly property bool soundPlaying: Time.timerSoundPlaying

  function formatTime(seconds, totalTimeSeconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;

    if (!totalTimeSeconds || totalTimeSeconds === 0) {
      return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }

    if (totalTimeSeconds < 3600) {
      return `${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }
    return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }

  function formatTimeFromDigits(digits) {
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

    seconds = Math.min(59, seconds);
    minutes = Math.min(59, minutes);
    hours = Math.min(99, hours);

    return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }

  function parseDigitsToTime(digits) {
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
    timerDisplayItem.isEditing = false;
    timerDisplayItem.inputBuffer = "";
    timerInput.focus = false;
  }
}
