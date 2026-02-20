import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../../../Helpers/QtObj2JS.js" as QtObj2JS
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

// Monitor Widgets Configuration (inline)
NBox {
  id: root

  required property var screen
  readonly property string screenName: screen?.name || ""
  // determine bar orientation
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"

  color: Color.mSurfaceVariant
  Layout.fillWidth: true
  implicitHeight: content.implicitHeight + Style.marginL * 2

  // Helper to get widgets for this screen (ensures override exists)
  function _getWidgetsContainer() {
    if (!Settings.hasScreenOverride(screenName, "widgets")) {
      var currentWidgets = Settings.getBarWidgetsForScreen(screenName);
      var widgetsCopy = QtObj2JS.qtObjectToPlainObject(currentWidgets);
      Settings.setScreenOverride(screenName, "widgets", widgetsCopy);
    }
    var entry = Settings.getScreenOverrideEntry(screenName);
    return entry ? entry.widgets : Settings.data.bar.widgets;
  }

  // Persist widget changes by reassigning the override (triggers change detection)
  function _saveWidgets(widgets) {
    Settings.setScreenOverride(screenName, "widgets", widgets);
  }

  // Widget manipulation functions
  function _addWidgetToSection(widgetId, section) {
    var newWidget = {
      "id": widgetId
    };
    if (BarWidgetRegistry.widgetHasUserSettings(widgetId)) {
      var metadata = BarWidgetRegistry.widgetMetadata[widgetId];
      if (metadata) {
        Object.keys(metadata).forEach(function (key) {
          newWidget[key] = metadata[key];
        });
      }
    }
    var widgets = _getWidgetsContainer();
    widgets[section].push(newWidget);
    _saveWidgets(widgets);
    BarService.widgetsRevision++;
  }

  function _removeWidgetFromSection(section, index) {
    var widgets = _getWidgetsContainer();
    if (index >= 0 && index < widgets[section].length) {
      var newArray = widgets[section].slice();
      var removedWidgets = newArray.splice(index, 1);
      widgets[section] = newArray;
      _saveWidgets(widgets);
      BarService.widgetsRevision++;

      if (removedWidgets[0].id === "ControlCenter" && BarService.lookupWidget("ControlCenter") === undefined) {
        ToastService.showWarning(I18n.tr("toast.missing-control-center.label"), I18n.tr("toast.missing-control-center.description"), 12000);
      }
    }
  }

  function _reorderWidgetInSection(section, fromIndex, toIndex) {
    var widgets = _getWidgetsContainer();
    if (fromIndex >= 0 && fromIndex < widgets[section].length && toIndex >= 0 && toIndex < widgets[section].length) {
      var newArray = widgets[section].slice();
      var item = newArray[fromIndex];
      newArray.splice(fromIndex, 1);
      newArray.splice(toIndex, 0, item);
      widgets[section] = newArray;
      _saveWidgets(widgets);
      BarService.widgetsRevision++;
    }
  }

  // Note: _updateWidgetSettingsInSection does NOT increment revision
  // because it only changes settings, not widget structure
  function _updateWidgetSettingsInSection(section, index, settings) {
    var widgets = _getWidgetsContainer();
    widgets[section][index] = settings;
    _saveWidgets(widgets);
  }

  function _moveWidgetBetweenSections(fromSection, index, toSection) {
    var widgets = _getWidgetsContainer();
    if (index >= 0 && index < widgets[fromSection].length) {
      var widget = widgets[fromSection][index];
      var sourceArray = widgets[fromSection].slice();
      sourceArray.splice(index, 1);
      widgets[fromSection] = sourceArray;
      var targetArray = widgets[toSection].slice();
      targetArray.push(widget);
      widgets[toSection] = targetArray;
      _saveWidgets(widgets);
      BarService.widgetsRevision++;
    }
  }

  // Available widgets ListModel
  function updateAvailableWidgetsModel() {
    availableWidgetsModel.clear();
    var widgetIds = BarWidgetRegistry.getAvailableWidgets();
    if (!widgetIds)
      return;
    for (var i = 0; i < widgetIds.length; i++) {
      var id = widgetIds[i];
      var displayName = id;
      const badges = [];
      if (BarWidgetRegistry.isPluginWidget(id)) {
        var pluginId = id.replace("plugin:", "");
        var manifest = PluginRegistry.getPluginManifest(pluginId);
        if (manifest && manifest.name) {
          displayName = manifest.name;
        } else {
          displayName = pluginId;
        }
        badges.push({
                      "icon": "plugin",
                      "color": Color.mSecondary
                    });
      }
      if (BarWidgetRegistry.isCpuIntensive(id)) {
        badges.push({
                      "icon": "cpu-intensive",
                      "color": Color.mSecondary
                    });
      }
      availableWidgetsModel.append({
                                     "key": id,
                                     "name": displayName,
                                     "badges": badges
                                   });
    }
  }

  Component.onCompleted: updateAvailableWidgetsModel()

  ListModel {
    id: availableWidgetsModel
  }

  // Get effective widgets for this screen
  readonly property var effectiveWidgets: Settings.getBarWidgetsForScreen(screenName)

  ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM

    NText {
      text: I18n.tr("panels.bar.widgets-desc")
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    // Left Section
    NSectionEditor {
      sectionName: root.barIsVertical ? I18n.tr("positions.top") : I18n.tr("positions.left")
      sectionId: "left"
      barIsVertical: root.barIsVertical
      screen: root.screen
      settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
      widgetRegistry: BarWidgetRegistry
      widgetModel: root.effectiveWidgets.left
      availableWidgets: availableWidgetsModel
      onAddWidget: (widgetId, section) => root._addWidgetToSection(widgetId, section)
      onRemoveWidget: (section, index) => root._removeWidgetFromSection(section, index)
      onReorderWidget: (section, fromIndex, toIndex) => root._reorderWidgetInSection(section, fromIndex, toIndex)
      onUpdateWidgetSettings: (section, index, settings) => root._updateWidgetSettingsInSection(section, index, settings)
      onMoveWidget: (fromSection, index, toSection) => root._moveWidgetBetweenSections(fromSection, index, toSection)
      onOpenPluginSettingsRequested: manifest => pluginSettingsDialog.openPluginSettings(manifest)
    }

    // Center Section
    NSectionEditor {
      sectionName: I18n.tr("positions.center")
      sectionId: "center"
      barIsVertical: root.barIsVertical
      screen: root.screen
      settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
      widgetRegistry: BarWidgetRegistry
      widgetModel: root.effectiveWidgets.center
      availableWidgets: availableWidgetsModel
      onAddWidget: (widgetId, section) => root._addWidgetToSection(widgetId, section)
      onRemoveWidget: (section, index) => root._removeWidgetFromSection(section, index)
      onReorderWidget: (section, fromIndex, toIndex) => root._reorderWidgetInSection(section, fromIndex, toIndex)
      onUpdateWidgetSettings: (section, index, settings) => root._updateWidgetSettingsInSection(section, index, settings)
      onMoveWidget: (fromSection, index, toSection) => root._moveWidgetBetweenSections(fromSection, index, toSection)
      onOpenPluginSettingsRequested: manifest => pluginSettingsDialog.openPluginSettings(manifest)
    }

    // Right Section
    NSectionEditor {
      sectionName: root.barIsVertical ? I18n.tr("positions.bottom") : I18n.tr("positions.right")
      sectionId: "right"
      barIsVertical: root.barIsVertical
      screen: root.screen
      settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
      widgetRegistry: BarWidgetRegistry
      widgetModel: root.effectiveWidgets.right
      availableWidgets: availableWidgetsModel
      onAddWidget: (widgetId, section) => root._addWidgetToSection(widgetId, section)
      onRemoveWidget: (section, index) => root._removeWidgetFromSection(section, index)
      onReorderWidget: (section, fromIndex, toIndex) => root._reorderWidgetInSection(section, fromIndex, toIndex)
      onUpdateWidgetSettings: (section, index, settings) => root._updateWidgetSettingsInSection(section, index, settings)
      onMoveWidget: (fromSection, index, toSection) => root._moveWidgetBetweenSections(fromSection, index, toSection)
      onOpenPluginSettingsRequested: manifest => pluginSettingsDialog.openPluginSettings(manifest)
    }
  }

  // Plugin settings dialog
  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: false
  }
}
