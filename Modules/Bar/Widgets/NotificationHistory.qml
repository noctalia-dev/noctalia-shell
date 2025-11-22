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

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }
  readonly property bool showUnreadBadge: (widgetSettings.showUnreadBadge !== undefined) ? widgetSettings.showUnreadBadge : widgetMetadata.showUnreadBadge
  readonly property bool hideWhenZero: (widgetSettings.hideWhenZero !== undefined) ? widgetSettings.hideWhenZero : widgetMetadata.hideWhenZero

  implicitWidth: pill.width
  implicitHeight: pill.height

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

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": NotificationService.doNotDisturb ? I18n.tr("context-menu.disable-dnd") : I18n.tr("context-menu.enable-dnd"),
        "action": "toggle-dnd",
        "icon": NotificationService.doNotDisturb ? "bell" : "bell-off"
      },
      {
        "label": I18n.tr("context-menu.clear-history"),
        "action": "clear-history",
        "icon": "trash"
      },
      {
        "label": I18n.tr("context-menu.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   if (action === "toggle-dnd") {
                     NotificationService.doNotDisturb = !NotificationService.doNotDisturb;
                   } else if (action === "clear-history") {
                     NotificationService.clearHistory();
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  BarPill {
    id: pill

    property string currentNotif
    Connections {
      target: NotificationService.activeList
      function onCountChanged() {
        // keep current text a bit longer for the animation
        if (NotificationService.activeList.count > 0) {
          var notif = NotificationService.activeList.get(0)
          var summary = notif.summary.trim()
          var body = notif.body.trim()
          pill.currentNotif =  `${summary}: ${body}`.replace(/\n/g, " ")
        }
      }
    }

    Component.onCompleted: {
      function dismiss(notificationId) {
        if (Settings.data.notifications?.location == "bar") {
          NotificationService.dismissActiveNotification(notificationId)
        }
      }
      NotificationService.animateAndRemove.connect(dismiss);
    }


    screen: root.screen
    density: Settings.data.bar.density
    oppositeDirection: BarService.getPillDirection(root)
    icon: NotificationService.doNotDisturb ? "bell-off" : "bell"
    tooltipText: NotificationService.doNotDisturb ? I18n.tr("tooltips.open-notification-history-disable-dnd") : I18n.tr("tooltips.open-notification-history-enable-dnd")

    text: currentNotif
    forceOpen: Settings.data.notifications?.location == "bar" && NotificationService.activeList.count > 0
    // prevent open via mouse over
    forceClose: NotificationService.activeList.count == 0

    onClicked: {
      var panel = PanelService.getPanel("notificationHistoryPanel", screen);
      panel?.toggle(this);
    }

    onRightClicked: {
      var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
      if (popupMenuWindow) {
        const pos = BarService.getContextMenuPosition(root, contextMenu.implicitWidth, contextMenu.implicitHeight);
        contextMenu.openAtItem(root, pos.x, pos.y);
        popupMenuWindow.showContextMenu(contextMenu);
      }
    }


    Loader {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: 2
      anchors.topMargin: 1
      z: 2
      active: showUnreadBadge && (!hideWhenZero || computeUnreadCount() > 0)
      sourceComponent: Rectangle {
        id: badge
        readonly property int count: computeUnreadCount()
        height: 8
        width: height
        radius: height / 2
        color: Color.mError
        border.color: Color.mSurface
        border.width: Style.borderS
        visible: count > 0 || !hideWhenZero
      }
    }
  }
}
