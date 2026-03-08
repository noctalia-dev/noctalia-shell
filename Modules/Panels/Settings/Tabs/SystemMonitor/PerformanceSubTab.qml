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
    Layout.fillWidth: true
    label: I18n.tr("panels.system.noctalia-performance-disable-wallpaper-label")
    description: I18n.tr("panels.system.noctalia-performance-disable-wallpaper-description")
    checked: !Settings.data.noctaliaPerformance.disableWallpaper
    defaultValue: !Settings.getDefaultValue("noctaliaPerformance.disableWallpaper")
    onToggled: checked => Settings.data.noctaliaPerformance.disableWallpaper = !checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.system.noctalia-performance-disable-desktop-widgets-label")
    description: I18n.tr("panels.system.noctalia-performance-disable-desktop-widgets-description")
    checked: !Settings.data.noctaliaPerformance.disableDesktopWidgets
    defaultValue: !Settings.getDefaultValue("noctaliaPerformance.disableDesktopWidgets")
    onToggled: checked => Settings.data.noctaliaPerformance.disableDesktopWidgets = !checked
  }
}
