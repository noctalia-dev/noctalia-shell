import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property bool valueShowUnreadBadge: widgetData.showUnreadBadge !== undefined ? widgetData.showUnreadBadge : widgetMetadata.showUnreadBadge
  property bool valueHideWhenZero: widgetData.hideWhenZero !== undefined ? widgetData.hideWhenZero : widgetMetadata.hideWhenZero
  property bool valueHideWhenZeroUnread: widgetData.hideWhenZeroUnread !== undefined ? widgetData.hideWhenZeroUnread : widgetMetadata.hideWhenZeroUnread
  property string valueUnreadBadgeColor: widgetData.unreadBadgeColor !== undefined ? widgetData.unreadBadgeColor : widgetMetadata.unreadBadgeColor
  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : widgetMetadata.iconColor

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showUnreadBadge = valueShowUnreadBadge;
    settings.hideWhenZero = valueHideWhenZero;
    settings.hideWhenZeroUnread = valueHideWhenZeroUnread;
    settings.unreadBadgeColor = valueUnreadBadgeColor;
    settings.iconColor = valueIconColor;
    settingsChanged(settings);
  }

  NToggle {
    label: I18n.tr("bar.notification-history.show-unread-badge-label")
    description: I18n.tr("bar.notification-history.show-unread-badge-description")
    checked: valueShowUnreadBadge
    onToggled: checked => {
                 valueShowUnreadBadge = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.showUnreadBadge
  }

  NColorChoice {
    label: I18n.tr("common.select-icon-color")
    currentKey: valueIconColor
    onSelected: key => {
                  valueIconColor = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.iconColor
  }

  NColorChoice {
    label: I18n.tr("bar.notification-history.unread-badge-color-label")
    description: I18n.tr("bar.notification-history.unread-badge-color-description")
    currentKey: valueUnreadBadgeColor
    onSelected: key => {
                  valueUnreadBadgeColor = key;
                  saveSettings();
                }
    visible: valueShowUnreadBadge
    defaultValue: widgetMetadata.unreadBadgeColor
  }

  NToggle {
    label: I18n.tr("bar.notification-history.hide-widget-when-zero-label")
    description: I18n.tr("bar.notification-history.hide-widget-when-zero-description")
    checked: valueHideWhenZero
    onToggled: checked => {
                 valueHideWhenZero = checked;
                 saveSettings();
               }
    enabled: !valueHideWhenZeroUnread
    defaultValue: widgetMetadata.hideWhenZero
  }

  NToggle {
    label: I18n.tr("bar.notification-history.hide-widget-when-zero-unread-label")
    description: I18n.tr("bar.notification-history.hide-widget-when-zero-unread-description")
    checked: valueHideWhenZeroUnread
    onToggled: checked => {
                 valueHideWhenZeroUnread = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.hideWhenZeroUnread
  }
}
