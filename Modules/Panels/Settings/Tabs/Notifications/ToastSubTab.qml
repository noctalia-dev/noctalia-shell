import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NCheckbox {
    Layout.fillWidth: true
    label: I18n.tr("panels.notifications.media-toast-label")
    description: I18n.tr("panels.notifications.media-toast-description")
    checked: Settings.data.notifications.enableMediaToast
    onToggled: checked => Settings.data.notifications.enableMediaToast = checked
  }

  NDivider {
    Layout.fillWidth: true
  }

  NCheckbox {
    Layout.fillWidth: true
    label: I18n.tr("panels.notifications.toast-keyboard-label")
    description: I18n.tr("panels.notifications.toast-keyboard-description")
    checked: Settings.data.notifications.enableKeyboardLayoutToast
    onToggled: checked => Settings.data.notifications.enableKeyboardLayoutToast = checked
  }
}
