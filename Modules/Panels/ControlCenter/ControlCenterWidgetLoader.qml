import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI

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
    return (item && item.visible) ? item[prop] : 0;
  }

  Loader {
    id: loader
    anchors.fill: parent
    asynchronous: false
    sourceComponent: ControlCenterWidgetRegistry.getWidget(widgetId)

    onLoaded: {
      if (!item)
        return;

      // Apply properties to loaded widget
      for (var prop in widgetProps) {
        if (item.hasOwnProperty(prop)) {
          item[prop] = widgetProps[prop];
        }
      }

      // Set screen property
      if (item.hasOwnProperty("screen")) {
        item.screen = widgetScreen;
      }

      // Pass pluginApi for plugin widgets
      if (ControlCenterWidgetRegistry.isPluginWidget(widgetId) && item.hasOwnProperty("pluginApi")) {
        var pluginId = widgetId.substring(7); // Remove "plugin:" prefix
        item.pluginApi = PluginService.getPluginAPI(pluginId);
      }

      // Call custom onLoaded if it exists
      if (item.hasOwnProperty("onLoaded")) {
        item.onLoaded();
      }
    }

    Component.onDestruction: {
      // Explicitly clear references
      widgetProps = null;
    }
  }

  // Error handling
  Component.onCompleted: {
    if (!ControlCenterWidgetRegistry.hasWidget(widgetId)) {
      Logger.w("ControlCenterWidgetLoader", "Widget not found in registry:", widgetId);
      // Retry briefly in case the registry initializes after this component
      retryTimer.start();
    }
  }

  // Retry mechanism to cope with early evaluation before registry is ready
  Timer {
    id: retryTimer
    interval: 150
    repeat: true
    running: false
    property int attempts: 0
    onTriggered: {
      attempts += 1;
      if (ControlCenterWidgetRegistry.hasWidget(widgetId)) {
        loader.sourceComponent = ControlCenterWidgetRegistry.getWidget(widgetId);
        stop();
        attempts = 0;
        return;
      }
      if (attempts >= 20) { // ~3s max
        stop();
        attempts = 0;
        Logger.w("ControlCenterWidgetLoader", "Giving up waiting for widget:", widgetId);
      }
    }
  }
}
