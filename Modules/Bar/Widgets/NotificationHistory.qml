import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  property real scaling: 1.0

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }
  readonly property bool showUnreadBadge: (widgetSettings.showUnreadBadge !== undefined) ? widgetSettings.showUnreadBadge : widgetMetadata.showUnreadBadge
  readonly property bool hideWhenZero: (widgetSettings.hideWhenZero !== undefined) ? widgetSettings.hideWhenZero : widgetMetadata.hideWhenZero

  function lastSeenTs() {
    return Settings.data.notifications?.lastSeenTs || 0
  }

  function computeUnreadCount() {
    var since = lastSeenTs()
    var count = 0
    var model = NotificationService.historyList
    for (var i = 0; i < model.count; i++) {
      var item = model.get(i)
      var ts = item.timestamp instanceof Date ? item.timestamp.getTime() : item.timestamp
      if (ts > since)
        count++
    }
    return count
  }

  baseSize: Style.capsuleHeight
  compact: (Settings.data.bar.density === "compact")
  icon: Settings.data.notifications.doNotDisturb ? "bell-off" : "bell"
  tooltipText: Settings.data.notifications.doNotDisturb ? I18n.tr("tooltips.open-notification-history-disable-dnd") : I18n.tr("tooltips.open-notification-history-enable-dnd")
  tooltipDirection: BarService.getTooltipDirection()
  colorBg: (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent)
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  onClicked: {
    var panel = PanelService.getPanel("notificationHistoryPanel")
    panel?.toggle(this)
  }

  onRightClicked: Settings.data.notifications.doNotDisturb = !Settings.data.notifications.doNotDisturb

  Loader {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: 2 * scaling
    anchors.topMargin: 1 * scaling
    z: 2
    active: showUnreadBadge && (!hideWhenZero || computeUnreadCount() > 0)
    sourceComponent: Rectangle {
      id: badge
      readonly property int count: computeUnreadCount()
      height: 8 * scaling
      width: height
      radius: height / 2
      color: Color.mError
      border.color: Color.mSurface
      border.width: 1
      visible: count > 0 || !hideWhenZero
    }
  }
}
