import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property bool valueShowUnreadBadge: widgetData.showUnreadBadge !== undefined ? widgetData.showUnreadBadge : widgetMetadata.showUnreadBadge
  property bool valueHideWhenZero: widgetData.hideWhenZero !== undefined ? widgetData.hideWhenZero : widgetMetadata.hideWhenZero
  property bool valueHideWhenZeroUnread: widgetData.hideWhenZeroUnread !== undefined ? widgetData.hideWhenZeroUnread : widgetMetadata.hideWhenZeroUnread

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showUnreadBadge = valueShowUnreadBadge;
    settings.hideWhenZero = valueHideWhenZero;
    settings.hideWhenZeroUnread = valueHideWhenZeroUnread;
    return settings;
  }

  NToggle {
    label: I18n.tr("bar.notification-history.show-unread-badge-label")
    description: I18n.tr("bar.notification-history.show-unread-badge-description")
    checked: valueShowUnreadBadge
    onToggled: checked => valueShowUnreadBadge = checked
  }

  NToggle {
    label: I18n.tr("bar.notification-history.hide-widget-when-zero-label")
    description: I18n.tr("bar.notification-history.hide-widget-when-zero-description")
    checked: valueHideWhenZero
    onToggled: checked => valueHideWhenZero = checked
    visible: !valueHideWhenZeroUnread
  }

  NToggle {
    label: I18n.tr("bar.notification-history.hide-widget-when-zero-unread-label")
    description: I18n.tr("bar.notification-history.hide-widget-when-zero-unread-description")
    checked: valueHideWhenZeroUnread
    onToggled: checked => valueHideWhenZeroUnread = checked
  }
}
