import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL

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
}
