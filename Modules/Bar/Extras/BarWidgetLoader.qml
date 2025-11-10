import QtQuick
import Quickshell
import qs.Services.UI
import qs.Commons

Item {
  id: root

  required property string widgetId
  required property var widgetScreen
  required property var widgetProps

  property string barDensity: "default"
  readonly property real scaling: barDensity === "mini" ? 0.8 : (barDensity === "compact" ? 0.9 : 1.0)

  // Extract section info from widgetProps
  readonly property string section: widgetProps.section || ""
  readonly property int sectionIndex: widgetProps.sectionWidgetIndex || 0

  // Don't reserve space unless the loaded widget is really visible
  implicitWidth: getImplicitSize(loader.item, "implicitWidth")
  implicitHeight: getImplicitSize(loader.item, "implicitHeight")

  function getImplicitSize(item, prop) {
    return (item && item.visible) ? Math.round(item[prop]) : 0
  }

  Loader {
    id: loader
    anchors.fill: parent
    asynchronous: false
    sourceComponent: BarWidgetRegistry.getWidget(widgetId)

    onLoaded: {
      if (!item)
        return

      Logger.d("BarWidgetLoader", "Loading widget", widgetId, "on screen:", widgetScreen.name)

      // Apply properties to loaded widget
      for (var prop in widgetProps) {
        if (item.hasOwnProperty(prop)) {
          item[prop] = widgetProps[prop]
        }
      }

      // Set screen property
      if (item.hasOwnProperty("screen")) {
        item.screen = widgetScreen
      }

      // Set scaling property
      if (item.hasOwnProperty("scaling")) {
        item.scaling = Qt.binding(function () {
          return root.scaling
        })
      }

      // Register this widget instance with BarService
      BarService.registerWidget(widgetScreen.name, section, widgetId, sectionIndex, item)

      // Call custom onLoaded if it exists
      if (item.hasOwnProperty("onLoaded")) {
        item.onLoaded()
      }
    }

    Component.onDestruction: {
      // Unregister when destroyed
      if (widgetScreen && section) {
        BarService.unregisterWidget(widgetScreen.name, section, widgetId, sectionIndex)
      }
    }
  }

  // Error handling
  Component.onCompleted: {
    if (!BarWidgetRegistry.hasWidget(widgetId)) {
      Logger.w("BarWidgetLoader", "Widget not found in registry:", widgetId)
    }
  }
}
