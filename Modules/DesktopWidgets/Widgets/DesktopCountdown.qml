import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Widgets
import qs.Services.UI

DraggableDesktopWidget {
  id: root
  defaultX: 300
  defaultY: 300
  showBackground: (widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : false

  property string eventName: widgetData.eventName || ""
  property int durationMinutes: (widgetData && widgetData.durationMinutes) ? widgetData.durationMinutes : 0
  property int durationSeconds: (widgetData && widgetData.durationSeconds) ? widgetData.durationSeconds : 0
  property int totalDurationSeconds: {
    if (widgetData && widgetData.totalDurationSeconds !== undefined) {
      return widgetData.totalDurationSeconds;
    } else {
      // Calculate from minutes and seconds for backward compatibility
      return (durationMinutes * 60) + (durationSeconds || 0);
    }
  }
  property string countdownMode: (widgetData && widgetData.countdownMode) ? widgetData.countdownMode : 'duration'

  // Parse date string with better error handling and timezone awareness
  function parseDate(dateString) {
    if (!dateString) {
      return null;
    }

    // Check if dateString is already a Date object
    if (dateString instanceof Date) {
      return isNaN(dateString.getTime()) ? null : dateString;
    }

    // Try to parse the date string
    var date = new Date(dateString);

    // Check if the date is valid
    if (isNaN(date.getTime())) {
      Logger.w("DesktopCountdown", "Invalid date string provided:", dateString);
      return null;
    }

    // If it's a valid date, return it
    return date;
  }

  property date targetDate: {
    var parsedDate = parseDate(widgetData && widgetData.targetDate ? widgetData.targetDate : null);
    return parsedDate ? parsedDate : new Date(); // fallback to current time
  }

  property string currentPlanKey: widgetData.currentPlanKey || ""

  property bool configured: {
    if (countdownMode === 'duration') {
      // For duration mode, calculate total duration seconds if not provided
      var effectiveTotalSeconds = totalDurationSeconds;
      if (effectiveTotalSeconds <= 0) {
        // Fallback for backward compatibility: calculate from durationMinutes and durationSeconds
        effectiveTotalSeconds = (durationMinutes * 60) + durationSeconds;
      }
      return effectiveTotalSeconds > 0;
    } else if (countdownMode === 'datetime') {
      return targetDate && !isNaN(targetDate.getTime());
    }
    return false;
  }

  // State management constants
  readonly property int stateIdle: 0
  readonly property int stateRunning: 1
  readonly property int statePaused: 2
  readonly property int stateCompleted: 3

  property int countdownState: root.stateIdle
  property bool durationCompletedNotified: false
  property date targetDateTime: new Date()
  property int remainingSecondsOnPause: 0
  property int initialRemainingSeconds: 0
  property int totalSeconds: {
    if (countdownMode === 'duration') {
      // Use the same calculation as configured property for consistency
      var effectiveTotalSeconds = totalDurationSeconds;
      if (effectiveTotalSeconds <= 0) {
        // Fallback for backward compatibility: calculate from durationMinutes and durationSeconds
        effectiveTotalSeconds = (durationMinutes * 60) + (durationSeconds || 0);
      }
      return effectiveTotalSeconds;
    } else {
      return Math.max(0, initialRemainingSeconds);
    }
  }

  // Computed properties for UI
  readonly property bool isRunning: countdownState === root.stateRunning
  readonly property bool isPaused: countdownState === root.statePaused
  readonly property bool isCompleted: countdownState === root.stateCompleted
  property int remainingTotalSeconds: 0
  readonly property real circleMaxValue: {
    if (countdownMode === 'duration') {
      return totalSeconds > 0 ? totalSeconds : 1;
    } else if (countdownMode === 'datetime') {
      // For datetime mode, calculate the original total seconds from when the countdown started
      if (initialRemainingSeconds > 0) {
        return initialRemainingSeconds;
      } else {
        // If not initialized, calculate from current time to target date
        var now = new Date();
        var initialSecs = getTimeDifferenceInSeconds(now, root.targetDate);
        return Math.max(1, initialSecs); // At least 1 to avoid division by zero
      }
    }
    return 1;
  }
  readonly property real circleValue: Math.max(0, remainingTotalSeconds)
  readonly property bool active: (countdownMode === "duration" && isRunning && !isPaused) ||
                                (countdownMode === "datetime" && configured && remainingTotalSeconds > 0)

  implicitWidth: 200 * Style.uiScaleRatio
  implicitHeight: 200 * Style.uiScaleRatio
  width: implicitWidth * root.widgetScale
  height: implicitHeight * root.widgetScale

  property color textColor: Color.mOnSurface
  property color labelColor: Color.mOnSurfaceVariant
  property color progressColor: Color.mPrimary
  property real progressWidth: Style.marginS * root.widgetScale

  Timer {
    id: updateTimer
    interval: 1000
    repeat: true
    running: (countdownMode === "duration" && isRunning && !isPaused) ||
             (countdownMode === "datetime" && configured && !isCompleted)
    onTriggered: calculateRemaining()
  }

  // Calculate the time difference in seconds between two dates
  function getTimeDifferenceInSeconds(fromDate, toDate) {
    var diff = toDate.getTime() - fromDate.getTime();
    return Math.floor(diff / 1000);
  }

  // Function to remove the expired datetime plan
  function removeExpiredDateTimePlan() {
    if (root.currentPlanKey && root.countdownMode === "datetime") {
      var planKey = root.currentPlanKey;
      var plans = Settings.data.desktopWidgets.countdownPlans || [];

      // Find and remove the expired plan
      for (var i = 0; i < plans.length; i++) {
        if (plans[i].key === planKey || i.toString() === planKey) {
          plans.splice(i, 1);
          Settings.data.desktopWidgets.countdownPlans = plans;

          // Send toast notification about plan completion
          try {
            if (typeof ToastService !== 'undefined' && typeof ToastService.showNotice === 'function') {
              ToastService.showNotice(
                I18n.tr("notifications.countdown-completed.title"),
                I18n.tr("notifications.countdown-completed.body", { name: root.eventName }),
                "alarm"
              );
            } else {
              Logger.i("DesktopCountdown", "ToastService not available, countdown completed:", root.eventName);
            }
          } catch (e) {
            Logger.w("DesktopCountdown", "Could not send toast notification:", e);
            // Fallback to Logger if ToastService is not available
            Logger.i("DesktopCountdown", "Countdown completed:", root.eventName);
          }

          break;
        }
      }
    }
  }

  function calculateRemaining() {
    var now = new Date();
    var seconds;

    if (countdownMode === 'duration') {
      if (countdownState === root.stateCompleted) {
        // Already completed, don't update
        return;
      }

      if (countdownState === root.stateIdle) {
        // For duration mode, if idle, keep the initial value
        root.remainingTotalSeconds = root.totalSeconds;
        return;
      }

      seconds = getTimeDifferenceInSeconds(now, targetDateTime);
    } else if (countdownMode === 'datetime') {
      seconds = getTimeDifferenceInSeconds(now, root.targetDate);
    } else {
      return;
    }

    if (countdownMode === 'datetime') {
      root.remainingTotalSeconds = Math.max(0, seconds);
      // For datetime mode, when time is up, we can optionally trigger an event or change appearance
      if (seconds <= 0) {
        // Time has reached or passed the target date
        // Remove this plan from the settings since it's no longer useful
        removeExpiredDateTimePlan();
      }
    } else {
      // For duration mode
      if (seconds <= 0) {
        // Switch to completed state
        root.countdownState = root.stateCompleted;
        root.remainingTotalSeconds = 0;
        // Send toast notification for duration mode completion, but only once
        if (!root.durationCompletedNotified) {
          try {
            if (typeof ToastService !== 'undefined' && typeof ToastService.showNotice === 'function') {
              ToastService.showNotice(
                I18n.tr("notifications.countdown-completed.title"),
                I18n.tr("notifications.countdown-completed.body", { name: root.eventName }),
                "alarm"
              );
            } else {
              Logger.i("DesktopCountdown", "ToastService not available, duration countdown completed:", root.eventName);
            }
          } catch (e) {
            Logger.w("DesktopCountdown", "Could not send toast notification for duration mode:", e);
            // Fallback to Logger if ToastService is not available
            Logger.i("DesktopCountdown", "Duration countdown completed:", root.eventName);
          }
          root.durationCompletedNotified = true;
        }
      } else {
        root.remainingTotalSeconds = seconds;
      }
    }
  }

  function startTimer() {
    if (countdownMode !== 'duration') return;

    if (isPaused) {
      targetDateTime = new Date(Date.now() + remainingSecondsOnPause * 1000);
    } else {
      targetDateTime = new Date(Date.now() + totalSeconds * 1000);
    }
    countdownState = root.stateRunning;
    durationCompletedNotified = false; // Reset the notification flag when timer starts
  }

  function pauseTimer() {
    if (!isRunning) return;
    remainingSecondsOnPause = remainingTotalSeconds;
    countdownState = root.statePaused;
  }

  function resetTimer() {
    countdownState = root.stateIdle;
    remainingSecondsOnPause = 0;
    durationCompletedNotified = false; // Reset the notification flag

    if (countdownMode === "datetime") {
      // Calculate initial remaining seconds for datetime mode
      var now = new Date();
      initialRemainingSeconds = getTimeDifferenceInSeconds(now, root.targetDate);
      calculateRemaining();
    } else {
      calculateRemaining();
    }
  }

  Component.onCompleted: {
    if (countdownMode === 'datetime') {
      // Calculate initial remaining seconds for datetime mode
      var now = new Date();
      initialRemainingSeconds = getTimeDifferenceInSeconds(now, root.targetDate);
    }
    // Initialize state based on mode
    countdownState = root.stateIdle;
    calculateRemaining();
    canvas.requestPaint();
  }

  Connections {
    target: root
    function onWidgetDataChanged() {
      var planToApply = null;
      if (root.currentPlanKey) {
        var plans = Settings.data.desktopWidgets.countdownPlans || [];
        for (var i = 0; i < plans.length; i++) {
          // Check if this plan matches the currentPlanKey
          if (plans[i].key === root.currentPlanKey || i.toString() === root.currentPlanKey) {
            planToApply = plans[i];
            break;
          }
        }
      }

      if (planToApply) {
        root.eventName = planToApply.name;
        root.countdownMode = planToApply.mode;
        if (planToApply.mode === 'duration') {
          root.durationMinutes = planToApply.durationMinutes || 0;
          root.durationSeconds = planToApply.durationSeconds || 0;
          root.totalDurationSeconds = planToApply.totalDurationSeconds || (root.durationMinutes * 60 + root.durationSeconds);
        } else if (planToApply.mode === 'datetime' && planToApply.targetDate) {
          var parsedDate = parseDate(planToApply.targetDate);
          if (parsedDate) {
            root.targetDate = parsedDate;
          } else {
            Logger.w("DesktopCountdown", "Failed to parse target date from plan:", planToApply.targetDate);
          }
        }
      } else {
        // If no specific plan is selected, use direct widget data
        root.eventName = root.widgetData.eventName || "";
        root.countdownMode = (root.widgetData && root.widgetData.countdownMode) ? root.widgetData.countdownMode : 'duration';
        root.durationMinutes = (root.widgetData && root.widgetData.durationMinutes !== undefined) ? root.widgetData.durationMinutes : 0;
        root.durationSeconds = (root.widgetData && root.widgetData.durationSeconds !== undefined) ? root.widgetData.durationSeconds : 0;
        root.totalDurationSeconds = (root.widgetData && root.widgetData.totalDurationSeconds !== undefined) ? root.widgetData.totalDurationSeconds : (root.durationMinutes * 60 + root.durationSeconds);
        if (root.widgetData && root.widgetData.targetDate) {
          var parsedDate = parseDate(root.widgetData.targetDate);
          if (parsedDate) {
            root.targetDate = parsedDate;
          } else {
            Logger.w("DesktopCountdown", "Failed to parse target date from widgetData:", root.widgetData.targetDate);
          }
        }
      }

      // Ensure proper initialization based on mode
      if (root.countdownMode === "datetime") {
        // Calculate initial remaining seconds for datetime mode
        var now = new Date();
        root.initialRemainingSeconds = getTimeDifferenceInSeconds(now, root.targetDate);
      } else {
        // For duration mode, initialRemainingSeconds is not used
        root.initialRemainingSeconds = 0;
      }

      // Reset state when widget data changes
      root.countdownState = root.stateIdle;
      root.durationCompletedNotified = false;

      // Update the countdown calculation
      root.calculateRemaining();

      canvas.requestPaint();
    }
  }

  Item {
    id: mainView
    anchors.fill: parent

    Canvas {
      id: canvas
      anchors.fill: parent
      renderStrategy: Canvas.Cooperative
      renderTarget: Canvas.FramebufferObject

      onPaint: {
        var ctx = getContext("2d");
        const w = width, h = height;
        const cx = w / 2, cy = h / 2;
        const r = Math.min(w, h) / 2 - (root.progressWidth / 2);

        ctx.reset();
        ctx.lineWidth = root.progressWidth;
        ctx.lineCap = "round";

        ctx.strokeStyle = Qt.alpha(root.textColor, 0.05);
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, 2 * Math.PI);
        ctx.stroke();

        if (root.active && root.circleMaxValue > 0) {
          const ratio = root.circleValue / root.circleMaxValue;
          const startAngle = -Math.PI / 2;
          const endAngle = startAngle - (2 * Math.PI * ratio);

          ctx.strokeStyle = root.progressColor;
          ctx.beginPath();
          ctx.arc(cx, cy, r, startAngle, endAngle, true);
          ctx.stroke();
        }
      }

      Component.onCompleted: requestPaint()

      Connections {
        target: root
        function onRemainingTotalSecondsChanged() { canvas.requestPaint() }
        function onTotalSecondsChanged() { canvas.requestPaint() }
      }
    }

    ColumnLayout {
      anchors.centerIn: parent
      spacing: Style.marginS * root.widgetScale

      NText {
        visible: !root.configured
        Layout.alignment: Qt.AlignHCenter
        text: I18n.tr("settings.desktop-widgets.countdown.widgets.setup-prompt")
        color: labelColor
        pointSize: Style.fontSizeS * root.widgetScale
        font.weight: Style.fontWeightMedium
      }

      NText {
        visible: root.configured && eventName !== ""
        text: eventName
        color: labelColor
        pointSize: Style.fontSizeS * root.widgetScale
        font.weight: Style.fontWeightMedium
        Layout.alignment: Qt.AlignHCenter
      }

      NText {
        visible: root.configured
        readonly property int secs: root.remainingTotalSeconds
        readonly property int displayDays: Math.floor(secs / 86400)
        readonly property int displayHours: Math.floor((secs % 86400) / 3600)
        readonly property int displayMinutes: Math.floor((secs % 3600) / 60)
        readonly property int displaySeconds: secs % 60

        text: {
          if (root.isCompleted) {
            // Show "Time's up!" when countdown is completed in any mode
            return I18n.tr("settings.desktop-widgets.countdown.widgets.time-up");
          } else if (root.countdownMode === 'datetime' && root.remainingTotalSeconds <= 0) {
            // For datetime mode when time is up, show a special message
            return I18n.tr("settings.desktop-widgets.countdown.widgets.time-up");
          } else if (root.countdownMode === 'duration' && root.remainingTotalSeconds <= 0) {
            // For duration mode when time is up, show a special message
            return I18n.tr("settings.desktop-widgets.countdown.widgets.time-up");
          } else if (secs <= 0) {
            return "00:00";
          } else if (root.countdownMode === 'datetime' && secs > 86400) {
            return `${displayDays}d ${displayHours}h`;
          } else if (secs > 3600) {
            return `${displayHours}h ${displayMinutes}m`;
          } else {
            return `${displayMinutes.toString().padStart(2, '0')}:${displaySeconds.toString().padStart(2, '0')}`;
          }
        }

        color: {
          if (root.isCompleted ||
              ((root.countdownMode === 'datetime' || root.countdownMode === 'duration') && root.remainingTotalSeconds <= 0)) {
            // Use a different color when countdown is finished (both modes)
            return Qt.darker(progressColor, 1.5);
          } else {
            return textColor;
          }
        }
        pointSize: Style.fontSizeXXL * root.widgetScale
        font.weight: Style.fontWeightBold
        Layout.alignment: Qt.AlignHCenter
      }

      RowLayout {
        visible: root.configured
        Layout.alignment: Qt.AlignHCenter
        spacing: Style.marginS * root.widgetScale

        NIconButton {
          visible: root.countdownMode === "duration"
          baseSize: 32 * root.widgetScale
          icon: isRunning && !isPaused ? "media-pause" : "media-play"
          tooltipText: isRunning && !isPaused ? I18n.tr("settings.desktop-widgets.countdown.widgets.pause-tooltip") : I18n.tr("settings.desktop-widgets.countdown.widgets.start-tooltip")
          onClicked: isRunning && !isPaused ? pauseTimer() : startTimer()
        }

        NIconButton {
          baseSize: 32 * root.widgetScale
          icon: "refresh"
          visible: isRunning || isPaused
          tooltipText: I18n.tr("settings.desktop-widgets.countdown.widgets.reset-tooltip")
          onClicked: resetTimer()
        }

        NIconButton {
          baseSize: 32 * root.widgetScale
          icon: "edit"
          tooltipText: I18n.tr("settings.desktop-widgets.countdown.widgets.edit-tooltip")
          onClicked: planSelectionDialog.open()
        }
      }

      // Always show edit button when not configured to allow plan selection
      NIconButton {
        visible: !root.configured
        baseSize: 32 * root.widgetScale
        icon: "edit"
        tooltipText: I18n.tr("settings.desktop-widgets.countdown.widgets.edit-tooltip")
        onClicked: planSelectionDialog.open()
        Layout.alignment: Qt.AlignHCenter
      }
    }
  }

  Item {
      id: planSelectionDialog
      anchors.fill: parent
      visible: false
      z: 10

      property int selectedPlanIndex: -1
      property var planModel: {
          var plans = Settings.data.desktopWidgets.countdownPlans || [];
          var model = [];
          for (var i = 0; i < plans.length; i++) {
              if (plans[i] && typeof plans[i] === "object") {
                  model.push({
                      name: plans[i].name || "Untitled Plan",
                      key: i.toString()
                  });
              }
          }
          return model;
      }

      function open() {
          planSelectionDialog.selectedPlanIndex = -1;
          planComboBox.model = planSelectionDialog.planModel;


          if (root.currentPlanKey) {
              for (var i = 0; i < planSelectionDialog.planModel.length; i++) {
                  if (planSelectionDialog.planModel[i].key === root.currentPlanKey) {
                      planSelectionDialog.selectedPlanIndex = parseInt(planSelectionDialog.planModel[i].key);
                      planComboBox.currentKey = i.toString();
                      break;
                  }
              }
          }

          visible = true;
          Qt.callLater(function() { planComboBox.forceActiveFocus(); });
      }

      function close() {
          visible = false;
      }

      MouseArea {
          anchors.fill: parent
          onClicked: planSelectionDialog.close()
      }

      Rectangle {
          id: dialogContent
          width: 320 * Style.uiScaleRatio
          height: content.implicitHeight + (Style.marginL * 2)
          anchors.centerIn: parent
          color: Color.mSurface
          border.color: Color.mOutline
          radius: Style.radiusL
          focus: true
          Keys.onEscapePressed: planSelectionDialog.close()

          ColumnLayout {
              id: content
              anchors.fill: parent
              anchors.margins: Style.marginL
              spacing: Style.marginS

              NText {
                  text: I18n.tr("settings.desktop-widgets.countdown.widgets.select-preset-title")
                  pointSize: Style.fontSizeL
                  font.weight: Style.fontWeightBold
                  Layout.alignment: Qt.AlignHCenter
              }

              NComboBox {
                  id: planComboBox
                  Layout.fillWidth: true
                  label: I18n.tr("settings.desktop-widgets.countdown.widgets.preset-label")
                  model: planSelectionDialog.planModel
                  onSelected: function(key) {
                      planSelectionDialog.selectedPlanIndex = parseInt(key);
                  }
              }

              RowLayout {
                  Layout.fillWidth: true
                  Layout.topMargin: Style.marginM
                  spacing: Style.marginS

                  NButton {
                      Layout.fillWidth: true
                      text: I18n.tr("settings.desktop-widgets.countdown.widgets.cancel-button")
                      onClicked: planSelectionDialog.close()
                  }

                  NButton {
                      Layout.fillWidth: true
                      text: I18n.tr("settings.desktop-widgets.countdown.widgets.select-button")
                      enabled: planSelectionDialog.selectedPlanIndex > -1
                      onClicked: {
                          if (planSelectionDialog.selectedPlanIndex > -1) {
                              var selectedPlan = Settings.data.desktopWidgets.countdownPlans[planSelectionDialog.selectedPlanIndex];
                              var newWidgetData = {
                                  eventName: selectedPlan.name,
                                  countdownMode: selectedPlan.mode,
                                  durationMinutes: selectedPlan.durationMinutes,
                                  targetDate: selectedPlan.targetDate,
                                  currentPlanKey: planSelectionDialog.selectedPlanIndex.toString()
                              };
                              root.updateWidgetData(newWidgetData);
                              planSelectionDialog.close();
                          }
                      }
                  }
              }
          }
      }
  }
}
