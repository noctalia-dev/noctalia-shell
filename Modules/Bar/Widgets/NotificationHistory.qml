import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.System
import qs.Services.UI
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }
  readonly property bool showUnreadBadge: widgetSettings.showUnreadBadge !== undefined ? widgetSettings.showUnreadBadge : widgetMetadata.showUnreadBadge
  readonly property bool hideWhenZero: widgetSettings.hideWhenZero !== undefined ? widgetSettings.hideWhenZero : widgetMetadata.hideWhenZero
  readonly property bool hideWhenZeroUnread: widgetSettings.hideWhenZeroUnread !== undefined ? widgetSettings.hideWhenZeroUnread : widgetMetadata.hideWhenZeroUnread
  readonly property string unreadBadgeColor: widgetSettings.unreadBadgeColor !== undefined ? widgetSettings.unreadBadgeColor : widgetMetadata.unreadBadgeColor
  readonly property string iconColorKey: widgetSettings.iconColor !== undefined ? widgetSettings.iconColor : widgetMetadata.iconColor

  readonly property color badgeColor: Color.resolveColorKey(unreadBadgeColor)

  function computeUnreadCount() {
    var since = NotificationService.lastSeenTs;
    var count = 0;
    var model = NotificationService.historyList;
    for (var i = 0; i < model.count; i++) {
      var item = model.get(i);
      var ts = item.timestamp instanceof Date ? item.timestamp.getTime() : item.timestamp;
      if (ts > since)
        count++;
    }
    return count;
  }

  readonly property int count: computeUnreadCount()

  baseSize: Style.getCapsuleHeightForScreen(screen?.name)
  applyUiScale: false
  customRadius: Style.radiusL
  icon: NotificationService.doNotDisturb ? "bell-off" : "bell"
  tooltipText: NotificationService.doNotDisturb ? I18n.tr("tooltips.open-notification-history-enable-dnd") : I18n.tr("tooltips.open-notification-history-enable-dnd")
  tooltipDirection: BarService.getTooltipDirection(screen?.name)
  colorBg: Style.capsuleColor
  colorFg: Color.resolveColorKey(iconColorKey)
  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth
  visible: !((hideWhenZero && NotificationService.historyList.count === 0) || (hideWhenZeroUnread && count === 0))
  opacity: !((hideWhenZero && NotificationService.historyList.count === 0) || (hideWhenZeroUnread && count === 0)) ? 1.0 : 0.0

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": NotificationService.doNotDisturb ? I18n.tr("actions.disable-dnd") : I18n.tr("actions.enable-dnd"),
        "action": "toggle-dnd",
        "icon": NotificationService.doNotDisturb ? "bell" : "bell-off"
      },
      {
        "label": I18n.tr("actions.clear-history"),
        "action": "clear-history",
        "icon": "trash"
      },
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "toggle-dnd") {
                     NotificationService.doNotDisturb = !NotificationService.doNotDisturb;
                   } else if (action === "clear-history") {
                     NotificationService.clearHistory();
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  onClicked: {
    var panel = PanelService.getPanel("notificationHistoryPanel", screen);
    panel?.toggle(this);
  }

  onRightClicked: {
    PanelService.showContextMenu(contextMenu, root, screen);
  }

  Loader {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenterOffset: parent.baseSize / 4
    anchors.verticalCenterOffset: -parent.baseSize / 4
    z: 2
    active: showUnreadBadge
    sourceComponent: Rectangle {
      id: badge
      height: 7
      width: height
      radius: Style.radiusXS
      color: root.hovering ? Color.mOnHover : (root.badgeColor || Color.mError)
      border.color: Color.mSurface
      border.width: Style.borderS
      visible: count > 0
    }
  }
}
