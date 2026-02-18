import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.bar.behavior-workspace-scroll-label")
    description: I18n.tr("panels.bar.behavior-workspace-scroll-description")
    checked: Settings.data.bar.enableWorkspaceScroll
    defaultValue: Settings.getDefaultValue("bar.enableWorkspaceScroll")
    onToggled: checked => Settings.data.bar.enableWorkspaceScroll = checked
  }
}