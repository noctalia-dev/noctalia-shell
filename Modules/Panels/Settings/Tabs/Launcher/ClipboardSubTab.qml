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
    label: I18n.tr("panels.launcher.settings-clipboard-history-label")
    description: I18n.tr("panels.launcher.settings-clipboard-history-description")
    checked: Settings.data.appLauncher.enableClipboardHistory
    onToggled: checked => Settings.data.appLauncher.enableClipboardHistory = checked
    defaultValue: Settings.getDefaultValue("appLauncher.enableClipboardHistory")
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-clip-preview-label")
    description: I18n.tr("panels.launcher.settings-clip-preview-description")
    checked: Settings.data.appLauncher.enableClipPreview
    onToggled: checked => Settings.data.appLauncher.enableClipPreview = checked
    defaultValue: Settings.getDefaultValue("appLauncher.enableClipPreview")
    enabled: Settings.data.appLauncher.enableClipboardHistory
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-clip-wrap-text-label")
    description: I18n.tr("panels.launcher.settings-clip-wrap-text-description")
    checked: Settings.data.appLauncher.clipboardWrapText
    onToggled: checked => Settings.data.appLauncher.clipboardWrapText = checked
    defaultValue: Settings.getDefaultValue("appLauncher.clipboardWrapText")
    enabled: Settings.data.appLauncher.enableClipboardHistory
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-auto-paste-label")
    description: I18n.tr("panels.launcher.settings-auto-paste-description")
    checked: Settings.data.appLauncher.autoPasteClipboard
    onToggled: checked => Settings.data.appLauncher.autoPasteClipboard = checked
    defaultValue: Settings.getDefaultValue("appLauncher.autoPasteClipboard")
    enabled: Settings.data.appLauncher.enableClipboardHistory && ProgramCheckerService.wtypeAvailable
  }

  NDivider {
    Layout.fillWidth: true
    visible: Settings.data.appLauncher.enableClipboardHistory
  }

  NTextInput {
    label: I18n.tr("panels.launcher.settings-clipboard-watch-text-label")
    description: I18n.tr("panels.launcher.settings-clipboard-watch-text-description")
    Layout.fillWidth: true
    text: Settings.data.appLauncher.clipboardWatchTextCommand
    onEditingFinished: Settings.data.appLauncher.clipboardWatchTextCommand = text
    enabled: Settings.data.appLauncher.enableClipboardHistory
    visible: Settings.data.appLauncher.enableClipboardHistory
  }

  NTextInput {
    label: I18n.tr("panels.launcher.settings-clipboard-watch-image-label")
    description: I18n.tr("panels.launcher.settings-clipboard-watch-image-description")
    Layout.fillWidth: true
    text: Settings.data.appLauncher.clipboardWatchImageCommand
    onEditingFinished: Settings.data.appLauncher.clipboardWatchImageCommand = text
    enabled: Settings.data.appLauncher.enableClipboardHistory
    visible: Settings.data.appLauncher.enableClipboardHistory
  }
}
