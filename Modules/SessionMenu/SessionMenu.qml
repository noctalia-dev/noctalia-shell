import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  preferredWidth: 440
  preferredHeight: 485
  panelAnchorHorizontalCenter: true
  panelAnchorVerticalCenter: true
  panelKeyboardFocus: true

  // Timer properties
  property int timerDuration: 9000 // 9 seconds
  property string pendingAction: ""
  property bool timerActive: false
  property int timeRemaining: 0

  // Navigation properties
  property int selectedIndex: 0
  property bool hibernationAvailable: false
  readonly property var powerOptions: [{
      "action": "lock",
      "icon": "lock",
      "title": I18n.tr("session-menu.lock"),
      "subtitle": I18n.tr("session-menu.lock-subtitle")
    }, {
      "action": "suspend",
      "icon": "suspend",
      "title": I18n.tr("session-menu.suspend"),
      "subtitle": "Put the system to sleep"
    }, {
      "action": "hibernate",
      "icon": "moon",
      "title": "Hibernate",
      "subtitle": hibernationAvailable ? "Hibernate the system" : "Currently unavailable"
    }, {
      "action": "reboot",
      "icon": "reboot",
      "title": I18n.tr("session-menu.reboot"),
      "subtitle": "Restart the system"
    }, {
      "action": "logout",
      "icon": "logout",
      "title": I18n.tr("session-menu.logout"),
      "subtitle": I18n.tr("session-menu.end-subtitle")
    }, {
      "action": "shutdown",
      "icon": "shutdown",
      "title": I18n.tr("session-menu.shutdown"),
      "subtitle": "Turn off the system",
      "isShutdown": true
    }]

  // Lifecycle handlers
  onOpened: {
    selectedIndex = 0
    checkHibernation()
  }

  onClosed: {
    cancelTimer()
    selectedIndex = 0
  }

  // Timer management
  function startTimer(action) {
    if (timerActive && pendingAction === action) {
      // Second click - execute immediately
      executeAction(action)
      return
    }

    pendingAction = action
    timeRemaining = timerDuration
    timerActive = true
    countdownTimer.start()
  }

  function cancelTimer() {
    timerActive = false
    pendingAction = ""
    timeRemaining = 0
    countdownTimer.stop()
  }

  function executeAction(action) {
    // Stop timer but don't reset other properties yet
    countdownTimer.stop()

    switch (action) {
    case "lock":
      // Access lockScreen directly like IPCManager does
      if (!lockScreen.active) {
        lockScreen.active = true
      }
      break
    case "suspend":
      CompositorService.suspend()
      break
    case "hibernate":
      if (hibernationAvailable) {
        CompositorService.hibernate()
      }
      break
    case "reboot":
      CompositorService.reboot()
      break
    case "logout":
      CompositorService.logout()
      break
    case "shutdown":
      CompositorService.shutdown()
      break
    }

    // Reset timer state and close panel
    cancelTimer()
    root.close()
  }

  // Navigation functions
  function selectNext() {
    if (powerOptions.length > 0) {
      selectedIndex = Math.min(selectedIndex + 1, powerOptions.length - 1)
    }
  }

  function selectPrevious() {
    if (powerOptions.length > 0) {
      selectedIndex = Math.max(selectedIndex - 1, 0)
    }
  }

  function selectFirst() {
    selectedIndex = 0
  }

  function selectLast() {
    if (powerOptions.length > 0) {
      selectedIndex = powerOptions.length - 1
    } else {
      selectedIndex = 0
    }
  }

  function activate() {
    if (powerOptions.length > 0 && powerOptions[selectedIndex]) {
      const option = powerOptions[selectedIndex]
      startTimer(option.action)
    }
  }

  // Countdown timer
  Timer {
    id: countdownTimer
    interval: 100
    repeat: true
    onTriggered: {
      timeRemaining -= interval
      if (timeRemaining <= 0) {
        executeAction(pendingAction)
      }
    }
  }

  // Hibernation check logic
  function checkHibernation() {
    var proc = Process.create()
    proc.command = "bash"
    proc.arguments = ["-c", "grep -q 'resume=' /proc/cmdline && { swapon --show | grep -q '^'; }"]
    proc.onFinished.connect(function() {
      hibernationAvailable = (proc.exitCode === 0)
    })
    proc.start()
  }

  panelContent: Rectangle {
    id: ui
    color: Color.transparent

    // Keyboard shortcuts
    Shortcut {
      sequence: "Ctrl+K"
      onActivated: ui.selectPrevious()
      enabled: root.opened
    }

    Shortcut {
      sequence: "Ctrl+J"
      onActivated: ui.selectNext()
      enabled: root.opened
    }

    Shortcut {
      sequence: "Up"
      onActivated: ui.selectPrevious()
      enabled: root.opened
    }

    Shortcut {
      sequence: "Down"
      onActivated: ui.selectNext()
      enabled: root.opened
    }

    Shortcut {
      sequence: "Home"
      onActivated: ui.selectFirst()
      enabled: root.opened
    }

    Shortcut {
      sequence: "End"
      onActivated: ui.selectLast()
      enabled: root.opened
    }

    Shortcut {
      sequence: "Return"
      onActivated: ui.activate()
      enabled: root.opened
    }

    Shortcut {
      sequence: "Enter"
      onActivated: ui.activate()
      enabled: root.opened
    }

    Shortcut {
      sequence: "Escape"
      onActivated: {
        if (timerActive) {
          cancelTimer()
        } else {
          cancelTimer()
          root.close()
        }
      }
      context: Qt.WidgetShortcut
      enabled: root.opened
    }

    // Navigation functions
    function selectNext() {
      root.selectNext()
    }

    function selectPrevious() {
      root.selectPrevious()
    }

    function selectFirst() {
      root.selectFirst()
    }

    function selectLast() {
      root.selectLast()
    }

    function activate() {
      root.activate()
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.topMargin: Style.marginL * scaling
      anchors.leftMargin: Style.marginL * scaling
      anchors.rightMargin: Style.marginL * scaling
      anchors.bottomMargin: Style.marginM * scaling
      spacing: Style.marginS * scaling

      // Header with title and close button
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.baseWidgetSize * 0.8 * scaling

        NText {
          text: timerActive ? I18n.tr("session-menu.action-in-seconds", {
                                        "action": pendingAction.charAt(0).toUpperCase() + pendingAction.slice(1),
                                        "seconds": Math.ceil(timeRemaining / 1000)
                                      }) : I18n.tr("session-menu.title")
          font.weight: Style.fontWeightBold
          font.pointSize: Style.fontSizeL * scaling
          color: timerActive ? Color.mPrimary : Color.mOnSurface
          Layout.alignment: Qt.AlignVCenter
          verticalAlignment: Text.AlignVCenter
        }

        Item {
          Layout.fillWidth: true
        }

        NIconButton {
          icon: timerActive ? "stop" : "close"
          tooltipText: timerActive ? I18n.tr("tooltips.cancel-timer") : I18n.tr("tooltips.close")
          Layout.alignment: Qt.AlignVCenter
          colorBg: timerActive ? Qt.alpha(Color.mError, 0.08) : Color.transparent
          colorFg: timerActive ? Color.mError : Color.mOnSurface
          onClicked: {
            if (timerActive) {
              cancelTimer()
            } else {
              cancelTimer()
              root.close()
            }
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      // Power options
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        Repeater {
          model: powerOptions
          delegate: PowerButton {
            Layout.fillWidth: true
            icon: modelData.icon
            title: modelData.title
            subtitle: modelData.subtitle
            isShutdown: modelData.isShutdown || false
            isSelected: index === selectedIndex
            onClicked: {
              selectedIndex = index
              startTimer(modelData.action)
            }
            pending: timerActive && pendingAction === modelData.action
          }
        }
      }
    }
  }

  // Custom power button component
  component PowerButton: Rectangle {
    id: buttonRoot

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool pending: false
    property bool isShutdown: false
    property bool isSelected: false

    signal clicked

    height: Style.baseWidgetSize * 1.6 * scaling
    radius: Style.radiusS * scaling
    color: {
      if (pending) {
        return Qt.alpha(Color.mPrimary, 0.08)
      }
      if (isSelected || mouseArea.containsMouse) {
        return Color.mTertiary
      }
      return Color.transparent
    }

    border.width: pending ? Math.max(Style.borderM * scaling) : 0
    border.color: pending ? Color.mPrimary : Color.mOutline

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }

    Item {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling

      // Icon on the left
      NIcon {
        id: iconElement
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        icon: buttonRoot.icon
        color: {
          if (buttonRoot.pending)
            return Color.mPrimary
          if (buttonRoot.isShutdown && !buttonRoot.isSelected && !mouseArea.containsMouse)
            return Color.mError
          if (buttonRoot.isSelected || mouseArea.containsMouse)
            return Color.mOnTertiary
          return Color.mOnSurface
        }
        font.pointSize: Style.fontSizeXXXL * scaling
        width: Style.baseWidgetSize * 0.6 * scaling
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }
      }

      // Text content in the middle
      ColumnLayout {
        anchors.left: iconElement.right
        anchors.right: pendingIndicator.visible ? pendingIndicator.left : parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.marginXL * scaling
        anchors.rightMargin: pendingIndicator.visible ? Style.marginM * scaling : 0
        spacing: 0

        NText {
          text: buttonRoot.title
          font.weight: Style.fontWeightMedium
          font.pointSize: Style.fontSizeM * scaling
          color: {
            if (buttonRoot.pending)
              return Color.mPrimary
            if (buttonRoot.isShutdown && !buttonRoot.isSelected && !mouseArea.containsMouse)
              return Color.mError
            if (buttonRoot.isSelected || mouseArea.containsMouse)
              return Color.mOnTertiary
            return Color.mOnSurface
          }

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }

        NText {
          text: {
            if (buttonRoot.pending) {
              return I18n.tr("session-menu.click-again")
            }
            return buttonRoot.subtitle
          }
          font.pointSize: Style.fontSizeXS * scaling
          color: {
            if (buttonRoot.pending)
              return Color.mPrimary
            if (buttonRoot.isShutdown && !buttonRoot.isSelected && !mouseArea.containsMouse)
              return Color.mError
            if (buttonRoot.isSelected || mouseArea.containsMouse)
              return Color.mOnTertiary
            return Color.mOnSurfaceVariant
          }
          opacity: Style.opacityHeavy
          wrapMode: Text.NoWrap
          elide: Text.ElideRight
        }
      }

      // Pending indicator on the right
      Rectangle {
        id: pendingIndicator
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 24 * scaling
        height: 24 * scaling
        radius: width * 0.5
        color: Color.mPrimary
        visible: buttonRoot.pending

        NText {
          anchors.centerIn: parent
          text: Math.ceil(timeRemaining / 1000)
          font.pointSize: Style.fontSizeS * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnPrimary
        }
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      onClicked: buttonRoot.clicked()
    }
  }
}
