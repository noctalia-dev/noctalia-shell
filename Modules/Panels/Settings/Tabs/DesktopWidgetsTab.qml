import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginL

  // Available widgets model - declared early so Repeater delegates can access it
  property alias availableWidgetsModel: availableWidgets
  ListModel {
    id: availableWidgets
  }

  // Listen for plugin widget registration/unregistration
  Connections {
    target: DesktopWidgetRegistry
    function onPluginWidgetRegistryUpdated() {
      updateAvailableWidgetsModel();
    }
  }

  NHeader {
    label: I18n.tr("settings.desktop-widgets.general.section.label")
    description: I18n.tr("settings.desktop-widgets.general.section.description")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.enabled.label")
    description: I18n.tr("settings.desktop-widgets.enabled.description")
    checked: Settings.data.desktopWidgets.enabled
    isSettings: true
    defaultValue: Settings.getDefaultValue("desktopWidgets.enabled")
    onToggled: checked => Settings.data.desktopWidgets.enabled = checked
  }

  NButton {
    visible: Settings.data.desktopWidgets.enabled
    Layout.fillWidth: true
    text: DesktopWidgetRegistry.editMode ? I18n.tr("settings.desktop-widgets.edit-mode.exit-button") : I18n.tr("settings.desktop-widgets.edit-mode.button.label")
    icon: "edit"
    onClicked: {
      DesktopWidgetRegistry.editMode = !DesktopWidgetRegistry.editMode;
      if (DesktopWidgetRegistry.editMode && Settings.data.ui.settingsPanelMode !== "window") {
        var item = root.parent;
        while (item) {
          if (item.closeRequested !== undefined) {
            item.closeRequested();
            break;
          }
          item = item.parent;
        }
      }
    }
  }

  NDivider {
    visible: Settings.data.desktopWidgets.enabled
    Layout.fillWidth: true
  }

  // Helper to get screen names array
  function getScreenNames() {
    var names = [];
    for (var i = 0; i < Quickshell.screens.length; i++) {
      names.push(Quickshell.screens[i].name);
    }
    return names;
  }

  // Helper to get screen labels map (just screen names, NSectionEditor adds "Move to" prefix)
  function getScreenLabels() {
    var labels = {};
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var screen = Quickshell.screens[i];
      labels[screen.name] = screen.name;
    }
    return labels;
  }

  // Helper to get screen icons map
  function getScreenIcons() {
    var icons = {};
    for (var i = 0; i < Quickshell.screens.length; i++) {
      icons[Quickshell.screens[i].name] = "device-desktop";
    }
    return icons;
  }

  // One NSectionEditor per monitor
  Repeater {
    model: Settings.data.desktopWidgets.enabled ? Quickshell.screens : []

    NSectionEditor {
      required property var modelData

      Layout.fillWidth: true
      sectionName: modelData.name
      sectionSubtitle: {
        var compositorScale = CompositorService.getDisplayScale(modelData.name);
        // Format scale to 2 decimal places to prevent overly long text
        var formattedScale = compositorScale.toFixed(2);
        return "(" + modelData.width + "x" + modelData.height + " @ " + formattedScale + "x)";
      }

      sectionId: modelData.name
      settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml")
      widgetRegistry: DesktopWidgetRegistry
      widgetModel: getWidgetsForMonitor(modelData.name)
      availableWidgets: root.availableWidgetsModel
      availableSections: root.getScreenNames()
      sectionLabels: root.getScreenLabels()
      sectionIcons: root.getScreenIcons()
      draggable: false // Desktop widgets are positioned by X,Y, not list order
      maxWidgets: -1
      onAddWidget: (widgetId, section) => _addWidgetToMonitor(modelData.name, widgetId)
      onRemoveWidget: (section, index) => _removeWidgetFromMonitor(modelData.name, index)
      onMoveWidget: (fromSection, index, toSection) => _moveWidgetToMonitor(fromSection, index, toSection)
      onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettingsForMonitor(modelData.name, index, settings)
      onOpenPluginSettingsRequested: manifest => pluginSettingsDialog.openPluginSettings(manifest)
    }
  }

  // Shared Plugin Settings Popup
  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: false
  }

  Component.onCompleted: {
    // Use Qt.callLater to ensure DesktopWidgetRegistry is ready
    Qt.callLater(updateAvailableWidgetsModel);
  }

  function updateAvailableWidgetsModel() {
    availableWidgets.clear();
    try {
      if (typeof DesktopWidgetRegistry === "undefined" || !DesktopWidgetRegistry) {
        Logger.e("DesktopWidgetsTab", "DesktopWidgetRegistry is not available");
        // Retry after a short delay
        Qt.callLater(function () {
          if (typeof DesktopWidgetRegistry !== "undefined" && DesktopWidgetRegistry) {
            updateAvailableWidgetsModel();
          }
        });
        return;
      }
      var widgetIds = DesktopWidgetRegistry.getAvailableWidgets();
      Logger.d("DesktopWidgetsTab", "Found widgets:", widgetIds, "count:", widgetIds ? widgetIds.length : 0);
      if (!widgetIds || widgetIds.length === 0) {
        Logger.w("DesktopWidgetsTab", "No widgets found in registry");
        return;
      }
      for (var i = 0; i < widgetIds.length; i++) {
        var widgetId = widgetIds[i];
        var displayName = widgetId;

        // Get plugin name for plugin widgets
        var isPlugin = false;
        if (DesktopWidgetRegistry.isPluginWidget(widgetId)) {
          isPlugin = true;
          var pluginId = widgetId.replace("plugin:", "");
          var manifest = PluginRegistry.getPluginManifest(pluginId);
          if (manifest && manifest.name) {
            displayName = manifest.name;
          }
        }

        // Add plugin badge first (with custom color)
        const badges = [];
        if (isPlugin) {
          badges.push({
                        "icon": "plugin",
                        "color": Color.mSecondary
                      });
        }

        availableWidgets.append({
                                  "key": widgetId,
                                  "name": displayName,
                                  "badges": badges
                                });
      }
      Logger.d("DesktopWidgetsTab", "Available widgets model count:", availableWidgets.count);
    } catch (e) {
      Logger.e("DesktopWidgetsTab", "Error updating available widgets:", e, e.stack);
    }
  }

  // Get widgets for a specific monitor
  function getWidgetsForMonitor(monitorName) {
    var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
    for (var i = 0; i < monitorWidgets.length; i++) {
      if (monitorWidgets[i].name === monitorName) {
        return monitorWidgets[i].widgets || [];
      }
    }
    return [];
  }

  // Set widgets for a specific monitor
  function setWidgetsForMonitor(monitorName, widgets) {
    var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
    var newMonitorWidgets = monitorWidgets.slice();
    var found = false;
    for (var i = 0; i < newMonitorWidgets.length; i++) {
      if (newMonitorWidgets[i].name === monitorName) {
        newMonitorWidgets[i] = {
          "name": monitorName,
          "widgets": widgets
        };
        found = true;
        break;
      }
    }
    if (!found) {
      newMonitorWidgets.push({
                               "name": monitorName,
                               "widgets": widgets
                             });
    }
    Settings.data.desktopWidgets.monitorWidgets = newMonitorWidgets;
  }

  function _addWidgetToMonitor(monitorName, widgetId) {
    var newWidget = {
      "id": widgetId
    };
    if (DesktopWidgetRegistry.widgetHasUserSettings(widgetId)) {
      var metadata = DesktopWidgetRegistry.widgetMetadata[widgetId];
      if (metadata) {
        Object.keys(metadata).forEach(function (key) {
          if (key !== "allowUserSettings") {
            newWidget[key] = metadata[key];
          }
        });
      }
    }
    // Set default positions
    if (widgetId === "Clock") {
      newWidget.x = 50;
      newWidget.y = 50;
    } else if (widgetId === "MediaPlayer") {
      newWidget.x = 100;
      newWidget.y = 200;
    } else if (widgetId === "Weather") {
      newWidget.x = 100;
      newWidget.y = 300;
    } else {
      // Default position for plugin widgets
      newWidget.x = 150;
      newWidget.y = 150;
    }
    var widgets = getWidgetsForMonitor(monitorName).slice();
    widgets.push(newWidget);
    setWidgetsForMonitor(monitorName, widgets);
  }

  function _removeWidgetFromMonitor(monitorName, index) {
    var widgets = getWidgetsForMonitor(monitorName);
    if (index >= 0 && index < widgets.length) {
      var newArray = widgets.slice();
      newArray.splice(index, 1);
      setWidgetsForMonitor(monitorName, newArray);
    }
  }

  function _updateWidgetSettingsForMonitor(monitorName, index, settings) {
    var widgets = getWidgetsForMonitor(monitorName);
    if (index >= 0 && index < widgets.length) {
      var newArray = widgets.slice();
      newArray[index] = Object.assign({}, newArray[index], settings);
      setWidgetsForMonitor(monitorName, newArray);
    }
  }

  function _moveWidgetToMonitor(fromMonitor, index, toMonitor) {
    Logger.i("DesktopWidgetsTab", "Moving widget from", fromMonitor, "index", index, "to", toMonitor);
    var sourceWidgets = getWidgetsForMonitor(fromMonitor);
    if (index < 0 || index >= sourceWidgets.length) {
      Logger.e("DesktopWidgetsTab", "Invalid index", index, "for monitor", fromMonitor);
      return;
    }

    // Get the widget to move
    var newSourceWidgets = sourceWidgets.slice();
    var widget = Object.assign({}, newSourceWidgets.splice(index, 1)[0]);

    // Reset position and scale to ensure widget is accessible on new screen
    widget.x = 100;
    widget.y = 100;
    widget.scale = 1.0;

    // Add to destination monitor
    var destWidgets = getWidgetsForMonitor(toMonitor).slice();
    destWidgets.push(widget);

    // Update both monitors
    setWidgetsForMonitor(fromMonitor, newSourceWidgets);
    setWidgetsForMonitor(toMonitor, destWidgets);
  }
}
