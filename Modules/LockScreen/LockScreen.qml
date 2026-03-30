import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Services.Keyboard
import qs.Services.Media
import qs.Services.Power
import qs.Services.UI
import qs.Widgets

Loader {
  id: root

  // Starts the lock screen when activated
  active: false

  // Only controls the state of the session lock
  // Decoupled because we need to capture the screen first
  property bool locked: false

  // Track if the visualizer should be shown (lockscreen active + media playing + non-compact mode)
  readonly property bool needsSpectrum: root.active && !Settings.data.general.compactLockScreen && Settings.data.audio.visualizerType !== "" && Settings.data.audio.visualizerType !== "none"

  onActiveChanged: {
    if (root.active && root.needsSpectrum) {
      SpectrumService.registerComponent("lockscreen");
    } else {
      SpectrumService.unregisterComponent("lockscreen");
    }

    if (root.active) {
      LockKeysService.registerComponent("lockscreen");
    } else {
      LockKeysService.unregisterComponent("lockscreen");
    }

    // Trigger locksreen when loader is active
    if (root.active)
      startLockScreen();
  }

  onNeedsSpectrumChanged: {
    if (root.needsSpectrum) {
      SpectrumService.registerComponent("lockscreen");
    } else {
      SpectrumService.unregisterComponent("lockscreen");
    }
  }

  Component.onCompleted: {
    // Register with panel service
    PanelService.lockScreen = this;
  }

  Component.onDestruction: {
    SpectrumService.unregisterComponent("lockscreen");
    LockKeysService.unregisterComponent("lockscreen");
  }

  // Dictionary of screen name to ItemGrabResult of screen captures
  property var screenCaptures: ({})

  // Wait until all screens are captured before locking
  onScreenCapturesChanged: {
    let captureCount = Object.keys(screenCaptures).length;
    if (captureCount > 0 && captureCount === Quickshell.screens.length) {
      root.locked = true;
    }
  }

  // When lock is requested, clear previous captures and activate SCVs
  function startLockScreen() {
    screenCaptures = {};
    screenCopies.active = true;
  }

  Timer {
    id: unloadAfterUnlockTimer
    interval: 250
    repeat: false
    onTriggered: root.active = false
  }

  function unlockAndUnload() {
    locked = false;
    screenCopies.active = false;
    unloadAfterUnlockTimer.start();
  }

  // Image grabber for each connected screen
  Loader {
    id: screenCopies
    active: false

    sourceComponent: Instantiator {
      model: Quickshell.screens

      delegate: PanelWindow {
        anchors {
          top: true
          left: true
          right: true
          bottom: true
        }
        exclusionMode: ExclusionMode.Ignore
        screen: modelData
        color: "transparent"

        ScreencopyView {
          anchors.fill: parent
          captureSource: screen

          // Only grab an image when content is ready
          onHasContentChanged: {
            if (hasContent) {
              grabToImage(function (result) {
                // Store a ref to the result to avoid GC
                root.screenCaptures[screen.name] = result;
                // Manually call changed to trigger mutation signal
                root.screenCapturesChanged();
              });
            }
          }
        }
      }
    }
  }

  sourceComponent: Component {
    Item {
      id: lockContainer

      readonly property bool canTransition: Settings.data.general.lockScreenAnimations && !PowerProfileService.noctaliaPerformanceMode

      property real transitionProgress: canTransition ? 0.0 : 1.0

      NumberAnimation {
        id: lockEnter
        target: lockContainer
        property: "transitionProgress"
        to: 1.0
        duration: Style.animationNormal
        easing.type: Easing.OutCubic
        running: root.locked && canTransition
      }

      function unlockScreen() {
        root.unlockAndUnload();
        lockContext.currentText = "";
      }

      NumberAnimation {
        id: lockExit
        target: lockContainer
        property: "transitionProgress"
        to: 0.0
        duration: Style.animationNormal
        easing.type: Easing.InCubic
        onFinished: unlockScreen()
      }

      LockContext {
        id: lockContext
        onUnlocked: {
          if (canTransition) {
            lockEnter.stop();
            lockExit.start();
            return;
          }
          unlockScreen();
        }
        onFailed: {
          lockContext.currentText = "";
        }
      }

      // Whether any monitor from the user's lockScreenMonitors list is currently connected.
      readonly property bool anyConfiguredMonitorConnected: {
        const configured = Settings.data.general.lockScreenMonitors;
        if (!configured || configured.length === 0)
          return false;
        return (Quickshell.screens || []).some(s => configured.includes(s.name));
      }

      WlSessionLock {
        id: lockSession
        locked: root.locked

        WlSessionLockSurface {
          id: lockSurface
          color: "black"

          Loader {
            anchors.fill: parent
            active: true
            sourceComponent: (!lockContainer.anyConfiguredMonitorConnected || Settings.data.general.lockScreenMonitors.includes(lockSurface.screen?.name)) ? fullLockScreenComponent : blackScreenComponent
          }

          Component {
            id: fullLockScreenComponent

            Item {
              Item {
                id: batteryIndicator

                property bool isReady: BatteryService.batteryReady
                property real percent: BatteryService.batteryPercentage
                property bool charging: BatteryService.batteryCharging
                property bool pluggedIn: BatteryService.batteryPluggedIn
                property bool batteryVisible: isReady
                property string icon: BatteryService.batteryIcon
              }

              Item {
                id: keyboardLayout
                property string currentLayout: KeyboardLayoutService.currentLayout
              }

              // Background with wallpaper, gradient, and screen corners
              LockScreenBackground {
                id: backgroundComponent
                screen: lockSurface.screen
                screenGrab: lockSurface.screen ? (root.screenCaptures[lockSurface.screen.name] || null) : null
                transitionProgress: lockContainer.transitionProgress
              }

              Item {
                anchors.fill: parent
                opacity: lockContainer.transitionProgress

                // Mouse area to trigger focus on cursor movement (workaround for Hyprland focus issues)
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton
                  onEntered: {
                    // Avoid repeatedly forcing focus on every mouse move.
                    // This can churn text-input surface state during monitor/suspend transitions.
                    if (passwordInput && !passwordInput.activeFocus) {
                      passwordInput.forceActiveFocus();
                    }
                  }
                }

                // Header with avatar, welcome, time, date
                LockScreenHeader {
                  id: headerComponent
                }

                // Info notification
                Rectangle {
                  width: infoRowLayout.implicitWidth + Style.marginXL * 1.5
                  height: 50
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: (Settings.data.general.compactLockScreen ? 280 : 360) * Style.uiScaleRatio
                  radius: Style.radiusL
                  color: Color.mTertiary
                  visible: lockContext.showInfo && lockContext.infoMessage && !panelComponent.timerActive
                  opacity: visible ? 1.0 : 0.0

                  RowLayout {
                    id: infoRowLayout
                    anchors.centerIn: parent
                    spacing: Style.marginM

                    NIcon {
                      icon: "circle-key"
                      pointSize: Style.fontSizeXL
                      color: Color.mOnTertiary
                    }

                    NText {
                      text: lockContext.infoMessage
                      color: Color.mOnTertiary
                      pointSize: Style.fontSizeL
                      horizontalAlignment: Text.AlignHCenter
                    }
                  }

                  Behavior on opacity {
                    NumberAnimation {
                      duration: Style.animationNormal
                      easing.type: Easing.OutCubic
                    }
                  }
                }

                // Error notification
                Rectangle {
                  width: errorRowLayout.implicitWidth + Style.marginXL * 1.5
                  height: 50
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: (Settings.data.general.compactLockScreen ? 280 : 360) * Style.uiScaleRatio
                  radius: Style.radiusL
                  color: Color.mError
                  visible: lockContext.showFailure && lockContext.errorMessage && !panelComponent.timerActive
                  opacity: visible ? 1.0 : 0.0

                  RowLayout {
                    id: errorRowLayout
                    anchors.centerIn: parent
                    spacing: Style.marginM

                    NIcon {
                      icon: "alert-circle"
                      pointSize: Style.fontSizeXL
                      color: Color.mOnError
                    }

                    NText {
                      text: lockContext.errorMessage || "Authentication failed"
                      color: Color.mOnError
                      pointSize: Style.fontSizeL
                      horizontalAlignment: Text.AlignHCenter
                    }
                  }

                  Behavior on opacity {
                    NumberAnimation {
                      duration: Style.animationNormal
                      easing.type: Easing.OutCubic
                    }
                  }
                }

                // Countdown notification
                Rectangle {
                  width: countdownRowLayout.implicitWidth + Style.marginXL * 1.5
                  height: 50
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: (Settings.data.general.compactLockScreen ? 280 : 360) * Style.uiScaleRatio
                  radius: Style.radiusL
                  color: Color.mSurface
                  visible: panelComponent.timerActive
                  opacity: visible ? 1.0 : 0.0

                  RowLayout {
                    id: countdownRowLayout
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginM

                    NIcon {
                      icon: "clock"
                      pointSize: Style.fontSizeXL
                      color: Color.mPrimary
                    }

                    NText {
                      text: I18n.tr("session-menu.action-in-seconds", {
                                      "action": I18n.tr("common." + panelComponent.pendingAction),
                                      "seconds": Math.ceil(panelComponent.timeRemaining / 1000)
                                    })
                      color: Color.mOnSurface
                      pointSize: Style.fontSizeL
                      horizontalAlignment: Text.AlignHCenter
                      font.weight: Style.fontWeightBold
                    }

                    Item {
                      Layout.fillWidth: true
                    }

                    NIconButton {
                      icon: "x"
                      tooltipText: I18n.tr("session-menu.cancel-timer")
                      baseSize: 32
                      colorBg: Qt.alpha(Color.mPrimary, 0.1)
                      colorFg: Color.mPrimary
                      colorBgHover: Color.mPrimary
                      onClicked: panelComponent.cancelTimer()
                    }
                  }

                  Behavior on opacity {
                    NumberAnimation {
                      duration: Style.animationNormal
                      easing.type: Easing.OutCubic
                    }
                  }
                }

                // Hidden input that receives actual text
                TextInput {
                  id: passwordInput
                  width: 0
                  height: 0
                  visible: false
                  enabled: !lockContext.unlockInProgress
                  echoMode: TextInput.Password
                  passwordMaskDelay: 0

                  // Bidirectional sync — avoids a declarative binding which breaks on input
                  onTextChanged: {
                    if (lockContext.currentText !== text)
                      lockContext.currentText = text;
                  }
                  Connections {
                    target: lockContext
                    function onCurrentTextChanged() {
                      if (passwordInput.text !== lockContext.currentText)
                        passwordInput.text = lockContext.currentText;
                    }
                  }

                  Keys.onPressed: function (event) {
                    if (Keybinds.checkKey(event, 'enter', Settings)) {
                      lockContext.tryUnlock();
                      event.accepted = true;
                    }
                    if (Keybinds.checkKey(event, 'escape', Settings) && panelComponent.timerActive) {
                      panelComponent.cancelTimer();
                      event.accepted = true;
                    }
                  }

                  Component.onCompleted: forceActiveFocus()
                }

                // Main panel with password, weather, media, session controls
                LockScreenPanel {
                  id: panelComponent
                  lockControl: lockContext
                  batteryIndicator: batteryIndicator
                  keyboardLayout: keyboardLayout
                  passwordInput: passwordInput
                }
              }
            }
          }

          Component {
            id: blackScreenComponent

            // Black surface for disabled monitors — still captures keyboard for password entry
            Rectangle {
              anchors.fill: parent
              color: "black"

              TextInput {
                id: blackScreenPasswordInput
                width: 0
                height: 0
                visible: false
                enabled: !lockContext.unlockInProgress
                echoMode: TextInput.Password
                passwordMaskDelay: 0

                // Bidirectional sync — avoids a declarative binding which breaks on input
                onTextChanged: {
                  if (lockContext.currentText !== text)
                    lockContext.currentText = text;
                }
                Connections {
                  target: lockContext
                  function onCurrentTextChanged() {
                    if (blackScreenPasswordInput.text !== lockContext.currentText)
                      blackScreenPasswordInput.text = lockContext.currentText;
                  }
                }

                Keys.onPressed: function (event) {
                  if (Keybinds.checkKey(event, 'enter', Settings)) {
                    lockContext.tryUnlock();
                    event.accepted = true;
                  }
                }

                Component.onCompleted: forceActiveFocus()
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onPositionChanged: blackScreenPasswordInput.forceActiveFocus()
              }
            }
          }
        }
      }
    }
  }
}
