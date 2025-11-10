import QtQuick
import Quickshell
import qs.Services.UI
import qs.Commons

Item {
  id: root

  required property string widgetId
  required property var widgetScreen
  required property var widgetProps

  property string section: widgetProps && widgetProps.section || ""
  property int sectionIndex: widgetProps && widgetProps.sectionWidgetIndex || 0

  // Don't reserve space unless the loaded widget is really visible
  implicitWidth: getImplicitSize(loader.item, "implicitWidth")
  implicitHeight: getImplicitSize(loader.item, "implicitHeight")

  function getImplicitSize(item, prop) {
    return (item && item.visible) ? item[prop] : 0
  }

  Loader {
    id: loader
    anchors.fill: parent
    asynchronous: false
    sourceComponent: ControlCenterWidgetRegistry.getWidget(widgetId)

    onLoaded: {
      if (!item)
        return

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

      // Call custom onLoaded if it exists
      if (item.hasOwnProperty("onLoaded")) {
        item.onLoaded()
      }
    }

    Component.onDestruction: {
      // Explicitly clear references
      widgetProps = null
    }
  }

  // Error handling
  Component.onCompleted: {
    if (!ControlCenterWidgetRegistry.hasWidget(widgetId)) {
      Logger.w("ControlCenterWidgetLoader", "Widget not found in registry:", widgetId)
    }
  }
}
