import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Services.Keyboard
import qs.Widgets
import qs.Modules.Bar.Extras

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
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property string displayMode: (widgetSettings.displayMode !== undefined) ? widgetSettings.displayMode : widgetMetadata.displayMode

  // Use the shared service for keyboard layout
  property string currentLayout: KeyboardLayoutService.currentLayout

  implicitWidth: pill.width
  implicitHeight: pill.height

  BarPill {
    id: pill

    anchors.verticalCenter: parent.verticalCenter
    density: Settings.data.bar.density
    oppositeDirection: BarService.getPillDirection(root)
    icon: "keyboard"
    autoHide: false // Important to be false so we can hover as long as we want
    text: currentLayout.toUpperCase()
    tooltipText: I18n.tr("tooltips.keyboard-layout", {
                           "layout": currentLayout.toUpperCase()
                         })
    forceOpen: root.displayMode === "forceOpen"
    forceClose: root.displayMode === "alwaysHide"
    onClicked: {

      // You could open keyboard settings here if needed.
    }
  }
}
