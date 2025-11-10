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

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
