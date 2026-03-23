import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Services.Keyboard
import qs.Services.Media
import qs.Services.UI
import qs.Widgets

Loader {
  id: root
  active: false

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

  Timer {
    id: unloadAfterUnlockTimer
    interval: 250
    repeat: false
    onTriggered: root.active = false
  }

  function scheduleUnloadAfterUnlock() {
    unloadAfterUnlockTimer.start();
  }

  sourceComponent: Component {
    Item {
      id: lockContainer

      property var pendingPasteEditor: null

      function textCodePoints(text) {
        return Array.from(text || "");
      }

      function textLength(text) {
        return textCodePoints(text).length;
      }

      function clampPosition(position, text) {
        if (text === undefined)
          text = lockContext.currentText;
        return Math.max(0, Math.min(position, textLength(text)));
      }

      function isWordChar(character) {
        return /[0-9A-Za-z_]/.test(character);
      }

      function previousWordBoundary(text, position) {
        const chars = textCodePoints(text);
        let index = Math.max(0, Math.min(position, chars.length));

        while (index > 0 && /\s/.test(chars[index - 1])) {
          index--;
        }

        while (index > 0 && isWordChar(chars[index - 1])) {
          index--;
        }

        while (index > 0 && !/\s/.test(chars[index - 1]) && !isWordChar(chars[index - 1])) {
          index--;
        }

        return index;
      }

      function nextWordBoundary(text, position) {
        const chars = textCodePoints(text);
        let index = Math.max(0, Math.min(position, chars.length));

        while (index < chars.length && /\s/.test(chars[index])) {
          index++;
        }

        while (index < chars.length && isWordChar(chars[index])) {
          index++;
        }

        while (index < chars.length && !/\s/.test(chars[index]) && !isWordChar(chars[index])) {
          index++;
        }

        return index;
      }

      function clampEditorState(editor) {
        const length = textLength(lockContext.currentText);
        editor.cursorPosition = Math.max(0, Math.min(editor.cursorPosition, length));
        editor.selectionAnchor = Math.max(0, Math.min(editor.selectionAnchor, length));
      }

      function moveCursor(editor, position, extendSelection) {
        if (extendSelection === undefined)
          extendSelection = false;
        const clamped = clampPosition(position);
        if (!extendSelection) {
          editor.selectionAnchor = clamped;
        } else if (!editor.hasSelection) {
          editor.selectionAnchor = editor.cursorPosition;
        }
        editor.cursorPosition = clamped;
      }

      function replaceRange(text, start, end, replacement) {
        const chars = textCodePoints(text);
        chars.splice(start, end - start, ...textCodePoints(replacement));
        return chars.join("");
      }

      function replaceSelection(editor, replacement) {
        const start = editor.selectionStart;
        const end = editor.selectionEnd;
        lockContext.currentText = replaceRange(lockContext.currentText, start, end, replacement);
        const nextCursor = start + textLength(replacement);
        editor.cursorPosition = nextCursor;
        editor.selectionAnchor = nextCursor;
      }

      function deleteBackward(editor, byWord) {
        if (byWord === undefined)
          byWord = false;
        if (editor.hasSelection) {
          replaceSelection(editor, "");
          return;
        }

        if (editor.cursorPosition <= 0)
          return;

        const start = byWord ? previousWordBoundary(lockContext.currentText, editor.cursorPosition) : editor.cursorPosition - 1;
        lockContext.currentText = replaceRange(lockContext.currentText, start, editor.cursorPosition, "");
        editor.cursorPosition = start;
        editor.selectionAnchor = start;
      }

      function deleteForward(editor, byWord) {
        if (byWord === undefined)
          byWord = false;
        if (editor.hasSelection) {
          replaceSelection(editor, "");
          return;
        }

        const length = textLength(lockContext.currentText);
        if (editor.cursorPosition >= length)
          return;

        const end = byWord ? nextWordBoundary(lockContext.currentText, editor.cursorPosition) : editor.cursorPosition + 1;
        lockContext.currentText = replaceRange(lockContext.currentText, editor.cursorPosition, end, "");
        editor.selectionAnchor = editor.cursorPosition;
      }

      function insertText(editor, text) {
        if (!text)
          return;
        replaceSelection(editor, text);
      }

      function selectAll(editor) {
        editor.selectionAnchor = 0;
        editor.cursorPosition = textLength(lockContext.currentText);
      }

      function pasteClipboardText(editor) {
        if (pasteClipboardProc.running)
          return;
        pendingPasteEditor = editor;
        pasteClipboardProc.command = ["wl-paste", "--no-newline"];
        pasteClipboardProc.running = true;
      }

      function handlePasteExit(exitCode, exitStatus, stdoutText, stderrText) {
        const editor = pendingPasteEditor;
        pendingPasteEditor = null;

        if (exitCode === 0) {
          if (editor) {
            insertText(editor, String(stdoutText));
          }
          return;
        }

        const errorDetails = stderrText ? ` stderr: ${stderrText}` : "";
        Logger.w("LockScreen", `Clipboard paste failed with exit code ${exitCode}, exit status ${exitStatus}.${errorDetails}`);
      }

      function handlePasswordKey(editor, event, allowCancelTimer) {
        if (allowCancelTimer === undefined)
          allowCancelTimer = false;
        if (lockContext.unlockInProgress)
          return;

        const modifiers = event.modifiers;
        const shiftPressed = (modifiers & Qt.ShiftModifier) !== 0;
        const ctrlPressed = (modifiers & Qt.ControlModifier) !== 0;
        const altPressed = (modifiers & Qt.AltModifier) !== 0;
        const metaPressed = (modifiers & Qt.MetaModifier) !== 0;

        if (Keybinds.checkKey(event, 'enter', Settings)) {
          lockContext.tryUnlock();
          event.accepted = true;
          return;
        }

        if (allowCancelTimer && Keybinds.checkKey(event, 'escape', Settings) && panelComponent.timerActive) {
          panelComponent.cancelTimer();
          event.accepted = true;
          return;
        }

        if (ctrlPressed && !altPressed && !metaPressed && event.key === Qt.Key_A) {
          selectAll(editor);
          event.accepted = true;
          return;
        }

        if (!altPressed && !metaPressed && ((ctrlPressed && event.key === Qt.Key_V) || (shiftPressed && event.key === Qt.Key_Insert))) {
          pasteClipboardText(editor);
          event.accepted = true;
          return;
        }

        if (event.key === Qt.Key_Left) {
          if (editor.hasSelection && !shiftPressed && !ctrlPressed) {
            moveCursor(editor, editor.selectionStart);
          } else {
            moveCursor(editor, ctrlPressed ? previousWordBoundary(lockContext.currentText, editor.cursorPosition) : editor.cursorPosition - 1, shiftPressed);
          }
          event.accepted = true;
          return;
        }

        if (event.key === Qt.Key_Right) {
          if (editor.hasSelection && !shiftPressed && !ctrlPressed) {
            moveCursor(editor, editor.selectionEnd);
          } else {
            moveCursor(editor, ctrlPressed ? nextWordBoundary(lockContext.currentText, editor.cursorPosition) : editor.cursorPosition + 1, shiftPressed);
          }
          event.accepted = true;
          return;
        }

        if (event.key === Qt.Key_Home) {
          moveCursor(editor, 0, shiftPressed);
          event.accepted = true;
          return;
        }

        if (event.key === Qt.Key_End) {
          moveCursor(editor, textLength(lockContext.currentText), shiftPressed);
          event.accepted = true;
          return;
        }

        if (event.key === Qt.Key_Backspace) {
          deleteBackward(editor, ctrlPressed);
          event.accepted = true;
          return;
        }

        if (event.key === Qt.Key_Delete) {
          deleteForward(editor, ctrlPressed);
          event.accepted = true;
          return;
        }

        if (!ctrlPressed && !altPressed && !metaPressed && event.text && !/[\u0000-\u001f\u007f]/.test(event.text)) {
          insertText(editor, event.text);
          event.accepted = true;
        }
      }

      Process {
        id: pasteClipboardProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
                    lockContainer.handlePasteExit(exitCode, exitStatus, stdout.text, String(stderr.text || "").trim());
                  }
      }

      LockContext {
        id: lockContext
        onUnlocked: {
          lockSession.locked = false;
          root.scheduleUnloadAfterUnlock();
          lockContext.currentText = "";
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
        locked: root.active

        WlSessionLockSurface {
          id: lockSurface

          Loader {
            anchors.fill: parent
            active: true
            sourceComponent: (!lockContainer.anyConfiguredMonitorConnected || Settings.data.general.lockScreenMonitors.includes(lockSurface.screen ? lockSurface.screen.name : "")) ? fullLockScreenComponent : blackScreenComponent
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
              }

              Item {
                anchors.fill: parent

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

                // Hidden editor that receives raw key events without opening an IME text-input path.
                FocusScope {
                  id: passwordInput
                  width: 0
                  height: 0
                  visible: false
                  enabled: !lockContext.unlockInProgress
                  readonly property string text: lockContext.currentText
                  property int cursorPosition: lockContainer.textLength(lockContext.currentText)
                  property int selectionAnchor: cursorPosition
                  readonly property int selectionStart: Math.min(cursorPosition, selectionAnchor)
                  readonly property int selectionEnd: Math.max(cursorPosition, selectionAnchor)
                  readonly property bool hasSelection: cursorPosition !== selectionAnchor

                  Connections {
                    target: lockContext
                    function onCurrentTextChanged() {
                      lockContainer.clampEditorState(passwordInput);
                    }
                  }

                  Keys.onPressed: function (event) {
                    lockContainer.handlePasswordKey(passwordInput, event, true);
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

              FocusScope {
                id: blackScreenPasswordInput
                width: 0
                height: 0
                visible: false
                enabled: !lockContext.unlockInProgress
                readonly property string text: lockContext.currentText
                property int cursorPosition: lockContainer.textLength(lockContext.currentText)
                property int selectionAnchor: cursorPosition
                readonly property int selectionStart: Math.min(cursorPosition, selectionAnchor)
                readonly property int selectionEnd: Math.max(cursorPosition, selectionAnchor)
                readonly property bool hasSelection: cursorPosition !== selectionAnchor

                Connections {
                  target: lockContext
                  function onCurrentTextChanged() {
                    lockContainer.clampEditorState(blackScreenPasswordInput);
                  }
                }

                Keys.onPressed: function (event) {
                  lockContainer.handlePasswordKey(blackScreenPasswordInput, event);
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
