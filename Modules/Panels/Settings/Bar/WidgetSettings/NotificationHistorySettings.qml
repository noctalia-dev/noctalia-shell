import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property bool valueShowUnreadBadge: widgetData.showUnreadBadge !== undefined ? widgetData.showUnreadBadge : widgetMetadata.showUnreadBadge
  property bool valueHideWhenZero: widgetData.hideWhenZero !== undefined ? widgetData.hideWhenZero : widgetMetadata.hideWhenZero

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.showUnreadBadge = valueShowUnreadBadge
    settings.hideWhenZero = valueHideWhenZero
    return settings
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.notification-history.show-unread-badge.label")
    description: I18n.tr("bar.widget-settings.notification-history.show-unread-badge.description")
    checked: valueShowUnreadBadge
    onToggled: checked => valueShowUnreadBadge = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.notification-history.hide-badge-when-zero.label")
    description: I18n.tr("bar.widget-settings.notification-history.hide-badge-when-zero.description")
    checked: valueHideWhenZero
    onToggled: checked => valueHideWhenZero = checked
  }
}
