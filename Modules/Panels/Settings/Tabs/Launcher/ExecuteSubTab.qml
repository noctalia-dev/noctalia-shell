import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NTextInput {
    label: I18n.tr("panels.launcher.settings-terminal-command-label")
    description: I18n.tr("panels.launcher.settings-terminal-command-description")
    Layout.fillWidth: true
    text: Settings.data.appLauncher.terminalCommand
    onTextChanged: {
      Settings.data.appLauncher.terminalCommand = text;
    }
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-custom-launch-prefix-enabled-label")
    description: I18n.tr("panels.launcher.settings-custom-launch-prefix-enabled-description")
    checked: Settings.data.appLauncher.customLaunchPrefixEnabled
    onToggled: checked => Settings.data.appLauncher.customLaunchPrefixEnabled = checked
    defaultValue: Settings.getDefaultValue("appLauncher.customLaunchPrefixEnabled")
  }

  NTextInput {
    label: I18n.tr("panels.launcher.settings-custom-launch-prefix-label")
    description: I18n.tr("panels.launcher.settings-custom-launch-prefix-description")
    Layout.fillWidth: true
    text: Settings.data.appLauncher.customLaunchPrefix
    enabled: Settings.data.appLauncher.customLaunchPrefixEnabled
    visible: Settings.data.appLauncher.customLaunchPrefixEnabled
    onTextChanged: Settings.data.appLauncher.customLaunchPrefix = text
  }

  NTextInput {
    label: I18n.tr("panels.launcher.settings-annotation-tool-label")
    description: I18n.tr("panels.launcher.settings-annotation-tool-description")
    Layout.fillWidth: true
    text: Settings.data.appLauncher.screenshotAnnotationTool
    placeholderText: I18n.tr("panels.launcher.settings-annotation-tool-placeholder")
    onTextChanged: Settings.data.appLauncher.screenshotAnnotationTool = text
  }
}
