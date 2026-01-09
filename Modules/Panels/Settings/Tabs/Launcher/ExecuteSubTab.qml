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

  NToggle {
    label: I18n.tr("panels.launcher.settings-use-app2unit-label")
    description: I18n.tr("panels.launcher.settings-use-app2unit-description")
    checked: Settings.data.appLauncher.useApp2Unit && ProgramCheckerService.app2unitAvailable
    enabled: ProgramCheckerService.app2unitAvailable && !Settings.data.appLauncher.customLaunchPrefixEnabled
    opacity: ProgramCheckerService.app2unitAvailable ? 1.0 : 0.6
    onToggled: checked => {
                 if (ProgramCheckerService.app2unitAvailable) {
                   Settings.data.appLauncher.useApp2Unit = checked;
                   if (checked) {
                     Settings.data.appLauncher.customLaunchPrefixEnabled = false;
                   }
                 }
               }
    defaultValue: Settings.getDefaultValue("appLauncher.useApp2Unit")
  }

  NTextInput {
    label: I18n.tr("panels.launcher.settings-terminal-command-label")
    description: I18n.tr("panels.launcher.settings-terminal-command-description")
    Layout.fillWidth: true
    text: Settings.data.appLauncher.terminalCommand
    onEditingFinished: {
      Settings.data.appLauncher.terminalCommand = text;
    }
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-custom-launch-prefix-enabled-label")
    description: I18n.tr("panels.launcher.settings-custom-launch-prefix-enabled-description")
    checked: Settings.data.appLauncher.customLaunchPrefixEnabled
    enabled: !Settings.data.appLauncher.useApp2Unit
    onToggled: checked => {
                 Settings.data.appLauncher.customLaunchPrefixEnabled = checked;
                 if (checked) {
                   Settings.data.appLauncher.useApp2Unit = false;
                 }
               }
    defaultValue: Settings.getDefaultValue("appLauncher.customLaunchPrefixEnabled")
  }

  NTextInput {
    label: I18n.tr("panels.launcher.settings-custom-launch-prefix-label")
    description: I18n.tr("panels.launcher.settings-custom-launch-prefix-description")
    Layout.fillWidth: true
    text: Settings.data.appLauncher.customLaunchPrefix
    enabled: Settings.data.appLauncher.customLaunchPrefixEnabled
    visible: Settings.data.appLauncher.customLaunchPrefixEnabled
    onEditingFinished: Settings.data.appLauncher.customLaunchPrefix = text
  }

  NTextInput {
    label: I18n.tr("panels.launcher.settings-annotation-tool-label")
    description: I18n.tr("panels.launcher.settings-annotation-tool-description")
    Layout.fillWidth: true
    text: Settings.data.appLauncher.screenshotAnnotationTool
    placeholderText: I18n.tr("panels.launcher.settings-annotation-tool-placeholder")
    onEditingFinished: Settings.data.appLauncher.screenshotAnnotationTool = text
  }
}
