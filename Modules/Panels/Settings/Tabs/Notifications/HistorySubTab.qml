import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NToggle {
    label: I18n.tr("panels.notifications.history-low-urgency-label")
    description: I18n.tr("panels.notifications.history-low-urgency-description")
    checked: Settings.data.notifications?.saveToHistory?.low !== false
    onToggled: checked => Settings.data.notifications.saveToHistory.low = checked
    defaultValue: Settings.getDefaultValue("notifications.saveToHistory.low")
  }

  NToggle {
    label: I18n.tr("panels.notifications.history-normal-urgency-label")
    description: I18n.tr("panels.notifications.history-normal-urgency-description")
    checked: Settings.data.notifications?.saveToHistory?.normal !== false
    onToggled: checked => Settings.data.notifications.saveToHistory.normal = checked
    defaultValue: Settings.getDefaultValue("notifications.saveToHistory.normal")
  }

  NToggle {
    label: I18n.tr("panels.notifications.history-critical-urgency-label")
    description: I18n.tr("panels.notifications.history-critical-urgency-description")
    checked: Settings.data.notifications?.saveToHistory?.critical !== false
    onToggled: checked => Settings.data.notifications.saveToHistory.critical = checked
    defaultValue: Settings.getDefaultValue("notifications.saveToHistory.critical")
  }
}
