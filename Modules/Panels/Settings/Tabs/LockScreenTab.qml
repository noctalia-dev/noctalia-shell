import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  function insertToken(token) {
    if (formatInput.inputItem) {
      var input = formatInput.inputItem;
      var cursorPos = input.cursorPosition;
      var currentText = input.text;
      var newText = currentText.substring(0, cursorPos) + token + currentText.substring(cursorPos);
      input.text = newText + " ";
      input.cursorPosition = cursorPos + token.length + 1;
      input.forceActiveFocus();
    }
  }

  NComboBox {
    label: I18n.tr("panels.lock-screen.clock-style-label")
    description: I18n.tr("panels.lock-screen.clock-style-description")
    model: [
      {
        "key": "analog",
        "name": I18n.tr("panels.lock-screen.clock-style-analog")
      },
      {
        "key": "digital",
        "name": I18n.tr("panels.lock-screen.clock-style-digital")
      },
      {
        "key": "custom",
        "name": I18n.tr("panels.lock-screen.clock-style-custom")
      }
    ]
    currentKey: Settings.data.general.clockStyle
    onSelected: key => Settings.data.general.clockStyle = key
    defaultValue: Settings.getDefaultValue("general.clockStyle")
    z: 10
  }

  NComboBox {
    visible: Settings.data.general.clockStyle === "digital"
    label: I18n.tr("panels.lock-screen.clock-progress-style-label")
    description: I18n.tr("panels.lock-screen.clock-progress-style-description")
    model: [
      {
        "key": "solid",
        "name": I18n.tr("panels.lock-screen.clock-progress-style-solid")
      },
      {
        "key": "dashed",
        "name": I18n.tr("panels.lock-screen.clock-progress-style-dashed")
      }
    ]
    currentKey: Settings.data.general.clockProgressStyle
    onSelected: key => Settings.data.general.clockProgressStyle = key
    defaultValue: Settings.getDefaultValue("general.clockProgressStyle")
    z: 9
  }

  NTextInput {
    id: formatInput
    label: I18n.tr("panels.lock-screen.clock-format-label")
    description: I18n.tr("panels.lock-screen.clock-format-description")
    text: Settings.data.general.clockFormat
    onTextChanged: Settings.data.general.clockFormat = text
    visible: Settings.data.general.clockStyle === "custom"
    defaultValue: Settings.getDefaultValue("general.clockFormat")
  }

  NDateTimeTokens {
    Layout.fillWidth: true
    Layout.preferredHeight: 300
    visible: Settings.data.general.clockStyle === "custom"
    onTokenClicked: token => root.insertToken(token)
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.lock-on-suspend-label")
    description: I18n.tr("panels.lock-screen.lock-on-suspend-description")
    checked: Settings.data.general.lockOnSuspend
    onToggled: checked => Settings.data.general.lockOnSuspend = checked
    defaultValue: Settings.getDefaultValue("general.lockOnSuspend")
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.compact-lockscreen-label")
    description: I18n.tr("panels.lock-screen.compact-lockscreen-description")
    checked: Settings.data.general.compactLockScreen
    onToggled: checked => Settings.data.general.compactLockScreen = checked
    defaultValue: Settings.getDefaultValue("general.compactLockScreen")
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.auto-start-auth-label")
    description: I18n.tr("panels.lock-screen.auto-start-auth-description")
    checked: Settings.data.general.autoStartAuth
    onToggled: checked => Settings.data.general.autoStartAuth = checked
    defaultValue: Settings.getDefaultValue("general.autoStartAuth")
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.allow-password-with-fprintd-label")
    description: I18n.tr("panels.lock-screen.allow-password-with-fprintd-description")
    checked: Settings.data.general.allowPasswordWithFprintd
    onToggled: checked => Settings.data.general.allowPasswordWithFprintd = checked
    defaultValue: Settings.getDefaultValue("general.allowPasswordWithFprintd")
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.show-session-buttons-label")
    description: I18n.tr("panels.lock-screen.show-session-buttons-description")
    checked: Settings.data.general.showSessionButtonsOnLockScreen
    onToggled: checked => Settings.data.general.showSessionButtonsOnLockScreen = checked
    defaultValue: Settings.getDefaultValue("general.showSessionButtonsOnLockScreen")
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.show-hibernate-label")
    description: I18n.tr("panels.lock-screen.show-hibernate-description")
    checked: Settings.data.general.showHibernateOnLockScreen
    onToggled: checked => Settings.data.general.showHibernateOnLockScreen = checked
    visible: Settings.data.general.showSessionButtonsOnLockScreen
    defaultValue: Settings.getDefaultValue("general.showSessionButtonsOnLockScreen")
  }

  NToggle {
    label: I18n.tr("panels.session-menu.enable-countdown-label")
    description: I18n.tr("panels.session-menu.enable-countdown-description")
    checked: Settings.data.general.enableLockScreenCountdown
    onToggled: checked => Settings.data.general.enableLockScreenCountdown = checked
    visible: Settings.data.general.showSessionButtonsOnLockScreen
    defaultValue: Settings.getDefaultValue("general.enableLockScreenCountdown")
  }

  NValueSlider {
    visible: Settings.data.general.showSessionButtonsOnLockScreen && Settings.data.general.enableLockScreenCountdown
    Layout.fillWidth: true
    label: I18n.tr("panels.session-menu.countdown-duration-label")
    description: I18n.tr("panels.session-menu.countdown-duration-description")
    from: 1000
    to: 30000
    stepSize: 1000
    value: Settings.data.general.lockScreenCountdownDuration
    onMoved: value => Settings.data.general.lockScreenCountdownDuration = value
    text: Math.round(Settings.data.general.lockScreenCountdownDuration / 1000) + "s"
    defaultValue: Settings.getDefaultValue("general.lockScreenCountdownDuration")
  }
}
