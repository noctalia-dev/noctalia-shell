import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Widgets

DraggableDesktopWidget {
  id: root
  defaultX: 300
  defaultY: 300
  showBackground: (widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : false

  property string eventName: widgetData.eventName || ""
  property int durationMinutes: (widgetData && widgetData.durationMinutes) ? widgetData.durationMinutes : 0
  property string countdownMode: (widgetData && widgetData.countdownMode) ? widgetData.countdownMode : 'duration'

  // 改进：更安全的日期解析，确保用户本地时区处理
  property date targetDate: {
    if (widgetData && widgetData.targetDate) {
      // Parse the date string as a local time representation
      // If it's in YYYY-MM-DDTHH:mm:ss format, create the date directly in local time
      var d = new Date(widgetData.targetDate);
      if (!isNaN(d.getTime())) return d;
      console.warn("Invalid targetDate:", widgetData.targetDate);
    }
    return new Date(); // fallback
  }

  property string currentPlanKey: widgetData.currentPlanKey || ""

  property bool configured: (countdownMode === 'duration' && durationMinutes > 0) ||
                           (countdownMode === 'datetime' && targetDate && !isNaN(targetDate.getTime()))

  property bool isRunning: false
  property bool isPaused: false
  property date targetDateTime: new Date()
  property int remainingSecondsOnPause: 0

  // datetime 模式下：初始剩余秒数（切换计划时重置）
  property int initialRemainingSeconds: 0

  property int totalSeconds: countdownMode === 'duration' ? durationMinutes * 60 : Math.max(0, initialRemainingSeconds)

  property int remainingTotalSeconds: 0

  readonly property real circleMaxValue: totalSeconds > 0 ? totalSeconds : 1
  readonly property real circleValue: Math.max(0, remainingTotalSeconds)

  readonly property bool active: (countdownMode === "duration" && isRunning && !isPaused) ||
                                (countdownMode === "datetime" && remainingTotalSeconds > 0)

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
             (countdownMode === "datetime" && configured)
    onTriggered: calculateRemaining()
  }

  function calculateRemaining() {
    var now = new Date();
    var diff;

    if (countdownMode === 'duration') {
      if (!isRunning) {
        root.remainingTotalSeconds = root.totalSeconds;
        return;
      }
      diff = targetDateTime.getTime() - now.getTime();
    } else if (countdownMode === 'datetime') {
      diff = root.targetDate.getTime() - now.getTime();
    } else {
      return;
    }

    var seconds = Math.floor(diff / 1000);

    // datetime 模式：不超过 0（不显示负数）
    if (countdownMode === 'datetime') {
      root.remainingTotalSeconds = Math.max(0, seconds);
    } else {
      root.remainingTotalSeconds = seconds;
    }

    // duration 模式时间到 → 自动停止
    if (countdownMode === 'duration' && seconds <= 0) {
      resetTimer();
    }
  }

  function startTimer() {
    if (countdownMode !== 'duration') return;

    if (isPaused) {
      targetDateTime = new Date(Date.now() + remainingSecondsOnPause * 1000);
    } else {
      targetDateTime = new Date(Date.now() + totalSeconds * 1000);
    }
    isPaused = false;
    isRunning = true;
  }

  function pauseTimer() {
    if (!isRunning) return;
    remainingSecondsOnPause = remainingTotalSeconds;
    isRunning = false;
    isPaused = true;
  }

  function resetTimer() {
    isRunning = false;
    isPaused = false;
    remainingSecondsOnPause = 0;

    if (countdownMode === "datetime") {
      // 只重新计算剩余时间
      initialRemainingSeconds = 0; // 触发下次计算
      calculateRemaining();
    } else {
      // duration 模式恢复初始值
      calculateRemaining();
    }
  }

  Component.onCompleted: {
    // 首次加载时计算一次
    if (countdownMode === 'datetime') {
      initialRemainingSeconds = 0; // 强制下次 binding 重新计算
    }
    calculateRemaining();
    canvas.requestPaint();
  }

  Connections {
    target: root
    function onWidgetDataChanged() {
      // 查找当前计划
      var planToApply = null;
      if (root.currentPlanKey) {
        var plans = Settings.data.desktopWidgets.countdownPlans || [];
        for (var i = 0; i < plans.length; i++) {
          if (plans[i].key === root.currentPlanKey || i.toString() === root.currentPlanKey) {
            planToApply = plans[i];
            break;
          }
        }
      }

      // 应用计划后（原逻辑保留）
      if (planToApply) {
        root.eventName = planToApply.name;
        root.countdownMode = planToApply.mode;
        if (planToApply.mode === 'duration') {
          root.durationMinutes = planToApply.durationMinutes || 0;
        } else if (planToApply.mode === 'datetime' && planToApply.targetDate) {
          // Parse the date string ensuring local timezone interpretation
          root.targetDate = new Date(planToApply.targetDate);
        }
      } else {
        // fallback 逻辑同原
        root.eventName = root.widgetData.eventName || "";
        root.countdownMode = (root.widgetData && root.widgetData.countdownMode) ? root.widgetData.countdownMode : 'duration';
        root.durationMinutes = (root.widgetData && root.widgetData.durationMinutes !== undefined) ? root.widgetData.durationMinutes : 0;
        if (root.widgetData && root.widgetData.targetDate) {
          // Parse the date string ensuring local timezone interpretation
          root.targetDate = new Date(root.widgetData.targetDate);
        }
      }

      // 关键修复：每次 widgetData 改变后，重置 datetime 初始值
      root.initialRemainingSeconds = 0;

      if (root.countdownMode === "duration") {
        root.resetTimer();
      } else {
        // datetime 模式：重新计算剩余时间
        root.calculateRemaining();
      }

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

        // 背景圆环
        ctx.strokeStyle = Qt.alpha(root.textColor, 0.05);
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, 2 * Math.PI);
        ctx.stroke();

        // 进度圆环（仅在 active 时绘制）
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
          if (secs <= 0) {
            return "00:00";
          } else if (root.countdownMode === 'datetime' && secs > 86400) {
            return `${displayDays}d ${displayHours}h`;
          } else if (secs > 3600) {
            return `${displayHours}h ${displayMinutes}m`;
          } else {
            return `${displayMinutes.toString().padStart(2, '0')}:${displaySeconds.toString().padStart(2, '0')}`;
          }
        }

        color: secs <= 0 && root.countdownMode === 'datetime' ? Qt.lighter(textColor, 1.5) : textColor
        pointSize: Style.fontSizeXXL * root.widgetScale
        font.weight: Style.fontWeightBold
        Layout.alignment: Qt.AlignHCenter
      }

      // 按钮部分保持不变...
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
              model.push({ name: plans[i].name, key: i.toString() });
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

              NButton {
                  Layout.fillWidth: true
                  Layout.topMargin: Style.marginM
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
