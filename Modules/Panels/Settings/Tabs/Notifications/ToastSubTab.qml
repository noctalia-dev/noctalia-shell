import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NHeader {
    label: I18n.tr("settings.notifications.toast.section.label")
    description: I18n.tr("settings.notifications.toast.section.description")
  }

  NToggle {
    label: I18n.tr("settings.notifications.toast.keyboard.label")
    description: I18n.tr("settings.notifications.toast.keyboard.description")
    checked: Settings.data.notifications.enableKeyboardLayoutToast
    onToggled: checked => Settings.data.notifications.enableKeyboardLayoutToast = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("notifications.enableKeyboardLayoutToast")
  }
}
