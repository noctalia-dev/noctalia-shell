import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  NToggle {
    label: I18n.tr("settings.lock-screen.lock-on-suspend.label")
    description: I18n.tr("settings.lock-screen.lock-on-suspend.description")
    checked: Settings.data.general.lockOnSuspend
    onToggled: checked => Settings.data.general.lockOnSuspend = checked
  }

  NToggle {
    label: I18n.tr("settings.lock-screen.compact-lockscreen.label")
    description: I18n.tr("settings.lock-screen.compact-lockscreen.description")
    checked: Settings.data.general.compactLockScreen
    onToggled: checked => Settings.data.general.compactLockScreen = checked
  }

  NToggle {
    label: I18n.tr("settings.lock-screen.show-logout.label")
    description: I18n.tr("settings.lock-screen.show-logout.description")
    checked: Settings.data.general.showLogoutOnLockScreen
    onToggled: checked => Settings.data.general.showLogoutOnLockScreen = checked
  }

  NToggle {
    label: I18n.tr("settings.lock-screen.show-suspend.label")
    description: I18n.tr("settings.lock-screen.show-suspend.description")
    checked: Settings.data.general.showSuspendOnLockScreen
    onToggled: checked => Settings.data.general.showSuspendOnLockScreen = checked
  }

  NToggle {
    label: I18n.tr("settings.lock-screen.show-hibernate.label")
    description: I18n.tr("settings.lock-screen.show-hibernate.description")
    checked: Settings.data.general.showHibernateOnLockScreen
    onToggled: checked => Settings.data.general.showHibernateOnLockScreen = checked
  }
  
  NToggle {
    label: I18n.tr("settings.lock-screen.show-reboot.label")
    description: I18n.tr("settings.lock-screen.show-reboot.description")
    checked: Settings.data.general.showRebootOnLockScreen
    onToggled: checked => Settings.data.general.showRebootOnLockScreen = checked
  }

  NToggle {
    label: I18n.tr("settings.lock-screen.show-shutdown.label")
    description: I18n.tr("settings.lock-screen.show-shutdown.description")
    checked: Settings.data.general.showShutdownOnLockScreen
    onToggled: checked => Settings.data.general.showShutdownOnLockScreen = checked
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
