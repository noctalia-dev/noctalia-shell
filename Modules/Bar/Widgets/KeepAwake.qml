import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Power
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

  readonly property bool isBarVertical: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"

  implicitWidth: pill.width
  implicitHeight: pill.height

  BarPill {
    id: pill

    screen: root.screen
    text: IdleInhibitorService.timeout == null ? "" : Time.formatVagueHumanReadableDuration(IdleInhibitorService.timeout)
    oppositeDirection: BarService.getPillDirection(root)
    icon: IdleInhibitorService.isInhibited ? "keep-awake-on" : "keep-awake-off"
    tooltipText: IdleInhibitorService.isInhibited ? I18n.tr("tooltips.keep-awake") : I18n.tr("tooltips.keep-awake")
    onClicked: IdleInhibitorService.manualToggle()
    forceOpen: IdleInhibitorService.timeout !== null
    forceClose: IdleInhibitorService.timeout == null
    onWheel: function (delta) {
      var sign = delta > 0 ? 1 : -1;
      // the offset makes scrolling down feel symmetrical to scrolling up
      var timeout = IdleInhibitorService.timeout - (delta < 0 ? 60 : 0);
      if (timeout == null || timeout < 600) {
        delta = 60; // <= 10m, increment at 1m interval
      } else if (timeout >= 600 && timeout < 1800) {
        delta = 300; // >= 10m, increment at 5m interval
      } else if (timeout >= 1800 && timeout < 3600) {
        delta = 600; // >= 30m, increment at 10m interval
      } else if (timeout >= 3600) {
        delta = 1800; // > 1h, increment at 30m interval
      }

      IdleInhibitorService.changeTimeout(delta * sign);
    }
  }
}
