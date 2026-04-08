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

  // Store registration key at registration time so unregistration always uses the correct key,
  // even if binding properties (section, sectionIndex) have changed by destruction time
  property string _regScreen: ""
  property string _regSection: ""
  property string _regWidgetId: ""
  property int _regIndex: -1

  function _unregister() {
    if (_regScreen !== "") {
      BarService.unregisterWidget(_regScreen, _regSection, _regWidgetId, _regIndex);
      _regScreen = "";
    }
  }

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
      if (BarWidgetRegistry.hasWidget(root.widgetId)) {
        root.reloadCounter++;
        // Plugin widgets use setSource, so also trigger reload directly
        if (root._isPlugin && loader.active)
          root._loadWidget();
        Logger.d("BarWidgetLoader", "Plugin widget registry updated, reloading:", root.widgetId);
      }
    }
  }

  readonly property bool _isPlugin: BarWidgetRegistry.isPluginWidget(widgetId)

  // Build initial properties that must be available during Component.onCompleted.
  // This prevents registration-key mismatches in widgets that build IDs from
  // screen.name, section, or sectionWidgetIndex.
  // All standard bar widget props are passed for both core and plugin widgets.
  // Plugins that don't define some of these properties will get harmless warnings
  // but still load correctly — and plugins that DO define them (e.g. for unique
  // SpectrumService keys with multiple instances) get correct values from the start.
  function _initialProps() {
    return {
      "screen": widgetScreen,
      "widgetId": widgetProps.widgetId || "",
      "section": widgetProps.section || "",
      "sectionWidgetIndex": widgetProps.sectionWidgetIndex || 0,
      "sectionWidgetsCount": widgetProps.sectionWidgetsCount || 0
    };
  }

  // Core widget URLs: file names match widget IDs exactly
  readonly property string _barWidgetsDir: Quickshell.shellDir + "/Modules/Bar/Widgets/"

  function _loadWidget() {
    if (!BarWidgetRegistry.hasWidget(root.widgetId))
      return;

    var props = _initialProps();

    if (_isPlugin) {
      var comp = BarWidgetRegistry.getWidget(root.widgetId);
      if (!comp)
        return;
      var pluginId = root.widgetId.replace("plugin:", "");
      var api = PluginService.getPluginAPI(pluginId);
      if (api)
        props.pluginApi = api;
      loader.setSource(comp.url, props);
    } else {
      loader.setSource(_barWidgetsDir + root.widgetId + ".qml", props);
    }
  }

  Loader {
    id: loader
    anchors.fill: parent
    asynchronous: true
    active: root.checkWidgetExists() && (root.reloadCounter >= 0)

    // All widgets use setSource() so that screen and widget properties
    // are set as initial properties, available during Component.onCompleted.
    Component.onCompleted: root._loadWidget()

    onActiveChanged: {
      if (active)
        root._loadWidget();
    }

    // Unregister when the loaded item is destroyed (Loader deactivated or sourceComponent changed)
    onItemChanged: {
      if (!item) {
        root._unregister();
      }
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

      // Apply remaining widget properties (screen is already set as initial prop)
      for (var prop in widgetProps) {
        if (item.hasOwnProperty(prop)) {
          item[prop] = widgetProps[prop];
        }
      }

      // Unregister any previous registration before registering the new instance
      root._unregister();

      // Register and store the key for reliable unregistration
      BarService.registerWidget(widgetScreen.name, section, widgetId, sectionIndex, item);
      root._regScreen = widgetScreen.name;
      root._regSection = section;
      root._regWidgetId = widgetId;
      root._regIndex = sectionIndex;

      // Call custom onLoaded if it exists
      if (item.hasOwnProperty("onLoaded")) {
        item.onLoaded();
      }
    }

    Component.onDestruction: {
      root._unregister();
    }
  }

  // Error handling
  Component.onCompleted: {
    if (!BarWidgetRegistry.hasWidget(widgetId)) {
      Logger.w("BarWidgetLoader", "Widget not found in registry:", widgetId);
    }
  }
}
