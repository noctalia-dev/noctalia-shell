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

  NHeader {
    label: I18n.tr("settings.bar.appearance.section.label")
    description: I18n.tr("settings.bar.appearance.section.description")
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.position.label")
    description: I18n.tr("settings.bar.appearance.position.description")
    model: [
      {
        "key": "top",
        "name": I18n.tr("options.bar.position.top")
      },
      {
        "key": "bottom",
        "name": I18n.tr("options.bar.position.bottom")
      },
      {
        "key": "left",
        "name": I18n.tr("options.bar.position.left")
      },
      {
        "key": "right",
        "name": I18n.tr("options.bar.position.right")
      }
    ]
    currentKey: Settings.data.bar.position
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.position")
    onSelected: key => Settings.data.bar.position = key
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.density.label")
    description: I18n.tr("settings.bar.appearance.density.description")
    model: [
      {
        "key": "mini",
        "name": I18n.tr("options.bar.density.mini")
      },
      {
        "key": "compact",
        "name": I18n.tr("options.bar.density.compact")
      },
      {
        "key": "default",
        "name": I18n.tr("options.bar.density.default")
      },
      {
        "key": "comfortable",
        "name": I18n.tr("options.bar.density.comfortable")
      },
      {
        "key": "spacious",
        "name": I18n.tr("options.bar.density.spacious")
      }
    ]
    currentKey: Settings.data.bar.density
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.density")
    onSelected: key => Settings.data.bar.density = key
  }

  // Use Separate Bar Opacity Toggle
  NToggle {
    label: I18n.tr("settings.bar.appearance.use-separate-opacity.label")
    description: I18n.tr("settings.bar.appearance.use-separate-opacity.description")
    checked: Settings.data.bar.useSeparateOpacity
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.useSeparateOpacity")
    onToggled: checked => Settings.data.bar.useSeparateOpacity = checked
  }

  // Bar Background Opacity (only visible when separate opacity is enabled)
  NValueSlider {
    Layout.fillWidth: true
    visible: Settings.data.bar.useSeparateOpacity
    label: I18n.tr("settings.bar.appearance.background-opacity.label")
    description: I18n.tr("settings.bar.appearance.background-opacity.description")
    from: 0
    to: 1
    stepSize: 0.01
    value: Settings.data.bar.backgroundOpacity
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.backgroundOpacity")
    onMoved: value => Settings.data.bar.backgroundOpacity = value
    text: Math.floor(Settings.data.bar.backgroundOpacity * 100) + "%"
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.show-outline.label")
    description: I18n.tr("settings.bar.appearance.show-outline.description")
    checked: Settings.data.bar.showOutline
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.showOutline")
    onToggled: checked => Settings.data.bar.showOutline = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.show-capsule.label")
    description: I18n.tr("settings.bar.appearance.show-capsule.description")
    checked: Settings.data.bar.showCapsule
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.showCapsule")
    onToggled: checked => Settings.data.bar.showCapsule = checked
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginXXS
    visible: Settings.data.bar.showCapsule

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("settings.bar.appearance.capsule-opacity.label")
      description: I18n.tr("settings.bar.appearance.capsule-opacity.description")
      from: 0
      to: 1
      stepSize: 0.01
      value: Settings.data.bar.capsuleOpacity
      isSettings: true
      defaultValue: Settings.getDefaultValue("bar.capsuleOpacity")
      onMoved: value => Settings.data.bar.capsuleOpacity = value
      text: Math.floor(Settings.data.bar.capsuleOpacity * 100) + "%"
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.floating.label")
    description: I18n.tr("settings.bar.appearance.floating.description")
    checked: Settings.data.bar.floating
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.floating")
    onToggled: checked => {
                 Settings.data.bar.floating = checked;
               }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.outer-corners.label")
    description: I18n.tr("settings.bar.appearance.outer-corners.description")
    checked: Settings.data.bar.outerCorners
    visible: !Settings.data.bar.floating
    isSettings: true
    defaultValue: Settings.getDefaultValue("bar.outerCorners")
    onToggled: checked => Settings.data.bar.outerCorners = checked
  }

  // Floating bar options - only show when floating is enabled
  ColumnLayout {
    visible: Settings.data.bar.floating
    spacing: Style.marginS
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("settings.bar.appearance.margins.label")
      description: I18n.tr("settings.bar.appearance.margins.description")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginL

      ColumnLayout {
        spacing: Style.marginXXS

        NValueSlider {
          Layout.fillWidth: true
          label: I18n.tr("settings.bar.appearance.margins.vertical")
          from: 0
          to: 1
          stepSize: 0.01
          value: Settings.data.bar.marginVertical
          isSettings: true
          defaultValue: Settings.getDefaultValue("bar.marginVertical")
          onMoved: value => Settings.data.bar.marginVertical = value
          text: Math.round(Settings.data.bar.marginVertical * 100) + "%"
        }
      }

      ColumnLayout {
        spacing: Style.marginXXS

        NValueSlider {
          Layout.fillWidth: true
          label: I18n.tr("settings.bar.appearance.margins.horizontal")
          from: 0
          to: 1
          stepSize: 0.01
          value: Settings.data.bar.marginHorizontal
          isSettings: true
          defaultValue: Settings.getDefaultValue("bar.marginHorizontal")
          onMoved: value => Settings.data.bar.marginHorizontal = value
          text: Math.ceil(Settings.data.bar.marginHorizontal * 100) + "%"
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Widgets Management Section
  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.bar.widgets.section.label")
    }

    NLabel {
      description: I18n.tr("settings.bar.widgets.section.description")
    }

    // Bar Sections
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.topMargin: Style.marginM
      spacing: Style.marginM

      // Left Section
      NSectionEditor {
        sectionName: "Left"
        sectionId: "left"
        settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
        widgetRegistry: BarWidgetRegistry
        widgetModel: Settings.data.bar.widgets.left
        availableWidgets: availableWidgets
        onAddWidget: (widgetId, section) => _addWidgetToSection(widgetId, section)
        onRemoveWidget: (section, index) => _removeWidgetFromSection(section, index)
        onReorderWidget: (section, fromIndex, toIndex) => _reorderWidgetInSection(section, fromIndex, toIndex)
        onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettingsInSection(section, index, settings)
        onMoveWidget: (fromSection, index, toSection) => _moveWidgetBetweenSections(fromSection, index, toSection)
        onOpenPluginSettingsRequested: manifest => pluginSettingsDialog.openPluginSettings(manifest)
      }

      // Center Section
      NSectionEditor {
        sectionName: "Center"
        sectionId: "center"
        settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
        widgetRegistry: BarWidgetRegistry
        widgetModel: Settings.data.bar.widgets.center
        availableWidgets: availableWidgets
        onAddWidget: (widgetId, section) => _addWidgetToSection(widgetId, section)
        onRemoveWidget: (section, index) => _removeWidgetFromSection(section, index)
        onReorderWidget: (section, fromIndex, toIndex) => _reorderWidgetInSection(section, fromIndex, toIndex)
        onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettingsInSection(section, index, settings)
        onMoveWidget: (fromSection, index, toSection) => _moveWidgetBetweenSections(fromSection, index, toSection)
        onOpenPluginSettingsRequested: manifest => pluginSettingsDialog.openPluginSettings(manifest)
      }

      // Right Section
      NSectionEditor {
        sectionName: "Right"
        sectionId: "right"
        settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml")
        widgetRegistry: BarWidgetRegistry
        widgetModel: Settings.data.bar.widgets.right
        availableWidgets: availableWidgets
        onAddWidget: (widgetId, section) => _addWidgetToSection(widgetId, section)
        onRemoveWidget: (section, index) => _removeWidgetFromSection(section, index)
        onReorderWidget: (section, fromIndex, toIndex) => _reorderWidgetInSection(section, fromIndex, toIndex)
        onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettingsInSection(section, index, settings)
        onMoveWidget: (fromSection, index, toSection) => _moveWidgetBetweenSections(fromSection, index, toSection)
        onOpenPluginSettingsRequested: manifest => pluginSettingsDialog.openPluginSettings(manifest)
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Monitor Configuration
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.bar.monitors.section.label")
      description: I18n.tr("settings.bar.monitors.section.description")
    }

    Repeater {
      model: Quickshell.screens || []
      delegate: NCheckbox {
        Layout.fillWidth: true
        label: modelData.name || "Unknown"
        description: {
          const compositorScale = CompositorService.getDisplayScale(modelData.name);
          I18n.tr("system.monitor-description", {
                    "model": modelData.model,
                    "width": modelData.width * compositorScale,
                    "height": modelData.height * compositorScale,
                    "scale": compositorScale
                  });
        }
        checked: (Settings.data.bar.monitors || []).indexOf(modelData.name) !== -1
        onToggled: checked => {
                     if (checked) {
                       Settings.data.bar.monitors = addMonitor(Settings.data.bar.monitors, modelData.name);
                     } else {
                       Settings.data.bar.monitors = removeMonitor(Settings.data.bar.monitors, modelData.name);
                     }
                   }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Signal functions
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

      // Check that we still have a control center
      if (removedWidgets[0].id === "ControlCenter" && BarService.lookupWidget("ControlCenter") === undefined) {
        ToastService.showWarning(I18n.tr("toast.missing-control-center.label"), I18n.tr("toast.missing-control-center.description"), 12000);
      }
    }
  }

  function _reorderWidgetInSection(section, fromIndex, toIndex) {
    if (fromIndex >= 0 && fromIndex < Settings.data.bar.widgets[section].length && toIndex >= 0 && toIndex < Settings.data.bar.widgets[section].length) {

      // Create a new array to avoid modifying the original
      var newArray = Settings.data.bar.widgets[section].slice();
      var item = newArray[fromIndex];
      newArray.splice(fromIndex, 1);
      newArray.splice(toIndex, 0, item);

      Settings.data.bar.widgets[section] = newArray;
      //Logger.i("BarTab", "Widget reordered. New array:", JSON.stringify(newArray))
    }
  }

  function _updateWidgetSettingsInSection(section, index, settings) {
    // Update the widget settings in the Settings data
    Settings.data.bar.widgets[section][index] = settings;
    //Logger.i("BarTab", `Updated widget settings for ${settings.id} in ${section} section`)
  }

  function _moveWidgetBetweenSections(fromSection, index, toSection) {
    // Get the widget from the source section
    if (index >= 0 && index < Settings.data.bar.widgets[fromSection].length) {
      var widget = Settings.data.bar.widgets[fromSection][index];

      // Remove from source section
      var sourceArray = Settings.data.bar.widgets[fromSection].slice();
      sourceArray.splice(index, 1);
      Settings.data.bar.widgets[fromSection] = sourceArray;

      // Add to target section
      var targetArray = Settings.data.bar.widgets[toSection].slice();
      targetArray.push(widget);
      Settings.data.bar.widgets[toSection] = targetArray;

      //Logger.i("BarTab", `Moved widget ${widget.id} from ${fromSection} to ${toSection}`)
    }
  }

  // Data model functions
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

    // Add plugin badge first (with custom color)
    if (isPlugin) {
      badges.push({
                    "icon": "plugin",
                    "color": Color.mSecondary
                  });
    }

    // Add location badges (with default styling)
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

                      // For plugin widgets, strip the "plugin:" prefix and try to get the actual plugin name
                      if (isPlugin) {
                        const pluginId = entry.replace("plugin:", "");
                        const manifest = PluginRegistry.getPluginManifest(pluginId);
                        if (manifest && manifest.name) {
                          displayName = manifest.name;
                        } else {
                          // Fallback: just strip the prefix
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

  // Base list model for all combo boxes
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

  // Shared Plugin Settings Popup
  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: false
  }
}
