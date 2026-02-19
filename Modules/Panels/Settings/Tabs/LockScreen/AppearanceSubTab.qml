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
    label: I18n.tr("panels.lock-screen.password-chars-label")
    description: I18n.tr("panels.lock-screen.password-chars-description")
    checked: Settings.data.general.passwordChars
    onToggled: checked => Settings.data.general.passwordChars = checked
    defaultValue: Settings.getDefaultValue("general.passwordChars")
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.compact-lockscreen-label")
    description: I18n.tr("panels.lock-screen.compact-lockscreen-description")
    checked: Settings.data.general.compactLockScreen
    onToggled: checked => Settings.data.general.compactLockScreen = checked
    defaultValue: Settings.getDefaultValue("general.compactLockScreen")
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.lock-screen-animations-label")
    description: I18n.tr("panels.lock-screen.lock-screen-animations-description")
    checked: Settings.data.general.lockScreenAnimations
    onToggled: checked => Settings.data.general.lockScreenAnimations = checked
    defaultValue: Settings.getDefaultValue("general.lockScreenAnimations")
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("panels.lock-screen.lock-screen-blur-strength-label")
    description: I18n.tr("panels.lock-screen.lock-screen-blur-strength-description")
    from: 0.0
    to: 1.0
    stepSize: 0.01
    showReset: true
    value: Settings.data.general.lockScreenBlur
    onMoved: value => Settings.data.general.lockScreenBlur = value
    text: ((Settings.data.general.lockScreenBlur) * 100).toFixed(0) + "%"
    defaultValue: Settings.getDefaultValue("general.lockScreenBlur")
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("panels.lock-screen.lock-screen-tint-strength-label")
    description: I18n.tr("panels.lock-screen.lock-screen-tint-strength-description")
    from: 0.0
    to: 1.0
    stepSize: 0.01
    showReset: true
    value: Settings.data.general.lockScreenTint
    onMoved: value => Settings.data.general.lockScreenTint = value
    text: ((Settings.data.general.lockScreenTint) * 100).toFixed(0) + "%"
    defaultValue: Settings.getDefaultValue("general.lockScreenTint")
  }
}
