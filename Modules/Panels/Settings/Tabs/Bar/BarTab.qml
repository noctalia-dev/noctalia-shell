import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: 0

  // Helper functions to update arrays immutably
  function addMonitor(list, name) {
    const arr = (list || []).slice();
    if (!arr.includes(name))
      arr.push(name);
    return arr;
  }
  function removeMonitor(list, name) {
    return (list || []).filter(function (n) {
      return n !== name;
    });
  }

  // Signal functions for widgets sub-tab
  function _addWidgetToSection(widgetId, section) {
    var newWidget = {
      "id": widgetId
    };
    if (BarWidgetRegistry.widgetHasUserSettings(widgetId)) {
      var metadata = BarWidgetRegistry.widgetMetadata[widgetId];
      if (metadata) {
        Object.keys(metadata).forEach(function (key) {
          if (key !== "allowUserSettings") {
            newWidget[key] = metadata[key];
          }
        });
      }
    }
    Settings.data.bar.widgets[section].push(newWidget);
  }

  function _removeWidgetFromSection(section, index) {
    if (index >= 0 && index < Settings.data.bar.widgets[section].length) {
      var newArray = Settings.data.bar.widgets[section].slice();
      var removedWidgets = newArray.splice(index, 1);
      Settings.data.bar.widgets[section] = newArray;

      if (removedWidgets[0].id === "ControlCenter" && BarService.lookupWidget("ControlCenter") === undefined) {
        ToastService.showWarning(I18n.tr("toast.missing-control-center.label"), I18n.tr("toast.missing-control-center.description"), 12000);
      }
    }
  }

  function _reorderWidgetInSection(section, fromIndex, toIndex) {
    if (fromIndex >= 0 && fromIndex < Settings.data.bar.widgets[section].length && toIndex >= 0 && toIndex < Settings.data.bar.widgets[section].length) {
      var newArray = Settings.data.bar.widgets[section].slice();
      var item = newArray[fromIndex];
      newArray.splice(fromIndex, 1);
      newArray.splice(toIndex, 0, item);
      Settings.data.bar.widgets[section] = newArray;
    }
  }

  function _updateWidgetSettingsInSection(section, index, settings) {
    Settings.data.bar.widgets[section][index] = settings;
  }

  function _moveWidgetBetweenSections(fromSection, index, toSection) {
    if (index >= 0 && index < Settings.data.bar.widgets[fromSection].length) {
      var widget = Settings.data.bar.widgets[fromSection][index];
      var sourceArray = Settings.data.bar.widgets[fromSection].slice();
      sourceArray.splice(index, 1);
      Settings.data.bar.widgets[fromSection] = sourceArray;
      var targetArray = Settings.data.bar.widgets[toSection].slice();
      targetArray.push(widget);
      Settings.data.bar.widgets[toSection] = targetArray;
    }
  }

  function getWidgetLocations(widgetId) {
    if (!BarService)
      return [];
    const instances = BarService.getAllRegisteredWidgets();
    const locations = {};
    for (var i = 0; i < instances.length; i++) {
      if (instances[i].widgetId === widgetId) {
        const section = instances[i].section;
        if (section === "left")
          locations["arrow-bar-to-left"] = true;
        else if (section === "center")
          locations["layout-columns"] = true;
        else if (section === "right")
          locations["arrow-bar-to-right"] = true;
      }
    }
    return Object.keys(locations);
  }

  function createBadges(isPlugin, locations) {
    const badges = [];
    if (isPlugin) {
      badges.push({
                    "icon": "plugin",
                    "color": Color.mSecondary
                  });
    }
    locations.forEach(function (location) {
      badges.push({
                    "icon": location,
                    "color": Color.mOnSurfaceVariant
                  });
    });
    return badges;
  }

  function updateAvailableWidgetsModel() {
    availableWidgets.clear();
    const widgets = BarWidgetRegistry.getAvailableWidgets();
    widgets.forEach(entry => {
                      const isPlugin = BarWidgetRegistry.isPluginWidget(entry);
                      let displayName = entry;
                      if (isPlugin) {
                        const pluginId = entry.replace("plugin:", "");
                        const manifest = PluginRegistry.getPluginManifest(pluginId);
                        if (manifest && manifest.name) {
                          displayName = manifest.name;
                        } else {
                          displayName = pluginId;
                        }
                      }
                      availableWidgets.append({
                                                "key": entry,
                                                "name": displayName,
                                                "badges": createBadges(isPlugin, getWidgetLocations(entry))
                                              });
                    });
  }

  ListModel {
    id: availableWidgets
  }

  Component.onCompleted: {
    updateAvailableWidgetsModel();
  }

  Connections {
    target: BarService
    function onActiveWidgetsChanged() {
      updateAvailableWidgetsModel();
    }
  }

  Connections {
    target: BarWidgetRegistry
    function onPluginWidgetRegistryUpdated() {
      updateAvailableWidgetsModel();
    }
  }

  NTabBar {
    id: subTabBar
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginM
    distributeEvenly: true
    currentIndex: tabView.currentIndex

    NTabButton {
      text: I18n.tr("common.appearance")
      tabIndex: 0
      checked: subTabBar.currentIndex === 0
    }
    NTabButton {
      text: I18n.tr("common.widgets")
      tabIndex: 1
      checked: subTabBar.currentIndex === 1
    }
    NTabButton {
      text: I18n.tr("common.monitors")
      tabIndex: 2
      checked: subTabBar.currentIndex === 2
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.marginL
  }

  NTabView {
    id: tabView
    currentIndex: subTabBar.currentIndex

    AppearanceSubTab {}
    WidgetsSubTab {
      availableWidgets: availableWidgets
      addWidgetToSection: root._addWidgetToSection
      removeWidgetFromSection: root._removeWidgetFromSection
      reorderWidgetInSection: root._reorderWidgetInSection
      updateWidgetSettingsInSection: root._updateWidgetSettingsInSection
      moveWidgetBetweenSections: root._moveWidgetBetweenSections
      onOpenPluginSettings: manifest => pluginSettingsDialog.openPluginSettings(manifest)
    }
    MonitorsSubTab {
      addMonitor: root.addMonitor
      removeMonitor: root.removeMonitor
    }
  }

  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: false
  }
}
