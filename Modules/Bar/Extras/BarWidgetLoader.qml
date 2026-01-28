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

  // Extract section info from widgetProps
  readonly property string section: widgetProps ? (widgetProps.section || "") : ""
  readonly property int sectionIndex: widgetProps ? (widgetProps.sectionWidgetIndex || 0) : 0

  // Bar orientation and height for extended click areas
  readonly property string barPosition: Settings.getBarPositionForScreen(widgetScreen?.name)
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"
  readonly property real barHeight: Style.getBarHeightForScreen(widgetScreen?.name)

  // Request full bar dimension from layout to extend click areas above/below widgets
  // For horizontal bars: full bar height, widget's content width
  // For vertical bars: full bar width, widget's content height
  implicitWidth: isVerticalBar ? barHeight : getImplicitSize(loader.item, "implicitWidth")
  implicitHeight: isVerticalBar ? getImplicitSize(loader.item, "implicitHeight") : barHeight

  // Remove layout space left by hidden widgets
  visible: loader.item ? ((loader.item.opacity > 0.0) || (loader.item.hasOwnProperty("hideMode") && loader.item.hideMode === "transparent")) : false

  function getImplicitSize(item, prop) {
    return (item && item.visible) ? Math.round(item[prop]) : 0;
  }

  // Only load if widget exists in registry
  function checkWidgetExists(): bool {
    return root.widgetId !== "" && BarWidgetRegistry.hasWidget(root.widgetId);
  }

  // Force reload counter - incremented when plugin widget registry changes
  property int reloadCounter: 0

  // Listen for plugin widget registry changes to force reload
  Connections {
    target: BarWidgetRegistry
    enabled: BarWidgetRegistry.isPluginWidget(root.widgetId)

    function onPluginWidgetRegistryUpdated() {
      // Force the loader to reload by toggling active
      if (BarWidgetRegistry.hasWidget(root.widgetId)) {
        root.reloadCounter++;
        Logger.d("BarWidgetLoader", "Plugin widget registry updated, reloading:", root.widgetId);
      }
    }
  }

  Loader {
    id: loader
    anchors.fill: parent
    asynchronous: false
    // Include reloadCounter in the binding to force re-evaluation
    active: root.checkWidgetExists() && (root.reloadCounter >= 0)
    sourceComponent: {
      // Depend on reloadCounter to force re-fetch of component
      var _ = root.reloadCounter;
      return root.checkWidgetExists() ? BarWidgetRegistry.getWidget(root.widgetId) : null;
    }

    onLoaded: {
      if (!item)
        return;

      Logger.d("BarWidgetLoader", "Loading widget", widgetId, "on screen:", widgetScreen.name);

      // Extend widget to fill full bar dimension for extended click areas
      // For horizontal bars: widget fills bar height (content width preserved)
      // For vertical bars: widget fills bar width (content height preserved)
      if (root.isVerticalBar) {
        item.width = Qt.binding(function () {
          return root.barHeight;
        });
      } else {
        item.height = Qt.binding(function () {
          return root.barHeight;
        });
      }

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

      // Inject plugin API for plugin widgets
      // The API is fully populated (settings/translations already loaded) by PluginService
      if (BarWidgetRegistry.isPluginWidget(widgetId)) {
        var pluginId = widgetId.replace("plugin:", "");
        var api = PluginService.getPluginAPI(pluginId);
        if (api && item.hasOwnProperty("pluginApi")) {
          item.pluginApi = api;
          Logger.d("BarWidgetLoader", "Injected plugin API for", widgetId);
        }
      }

      // Register this widget instance with BarService
      BarService.registerWidget(widgetScreen.name, section, widgetId, sectionIndex, item);

      // Call custom onLoaded if it exists
      if (item.hasOwnProperty("onLoaded")) {
        item.onLoaded();
      }
    }

    Component.onDestruction: {
      // Unregister when destroyed
      if (widgetScreen && section) {
        BarService.unregisterWidget(widgetScreen.name, section, widgetId, sectionIndex);
      }
    }
  }

  // Error handling
  Component.onCompleted: {
    if (!BarWidgetRegistry.hasWidget(widgetId)) {
      Logger.w("BarWidgetLoader", "Widget not found in registry:", widgetId);
    }
  }
}
