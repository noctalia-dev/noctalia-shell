import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Extras

ColumnLayout {
  id: root
  spacing: Style.marginL * scaling

  // Helper functions to update arrays immutably
  function addMonitor(list, name) {
    const arr = (list || []).slice()
    if (!arr.includes(name))
      arr.push(name)
    return arr
  }
  function removeMonitor(list, name) {
    return (list || []).filter(function (n) {
      return n !== name
    })
  }

  // Handler for drag start - disables panel background clicks
  function handleDragStart() {
    var panel = PanelService.getPanel("settingsPanel")
    if (panel && panel.disableBackgroundClick) {
      panel.disableBackgroundClick()
    }
  }

  // Handler for drag end - re-enables panel background clicks
  function handleDragEnd() {
    var panel = PanelService.getPanel("settingsPanel")
    if (panel && panel.enableBackgroundClick) {
      panel.enableBackgroundClick()
    }
  }

  NHeader {
    label: I18n.tr("settings.bar.appearance.section.label")
    description: I18n.tr("settings.bar.appearance.section.description")
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.position.label")
    description: I18n.tr("settings.bar.appearance.position.description")
    model: [{
        "key": "top",
        "name": I18n.tr("options.bar.position.top")
      }, {
        "key": "bottom",
        "name": I18n.tr("options.bar.position.bottom")
      }, {
        "key": "left",
        "name": I18n.tr("options.bar.position.left")
      }, {
        "key": "right",
        "name": I18n.tr("options.bar.position.right")
      }]
    currentKey: Settings.data.bar.position
    onSelected: key => Settings.data.bar.position = key
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.density.label")
    description: I18n.tr("settings.bar.appearance.density.description")
    model: [{
        "key": "compact",
        "name": I18n.tr("options.bar.density.compact")
      }, {
        "key": "default",
        "name": I18n.tr("options.bar.density.default")
      }, {
        "key": "comfortable",
        "name": I18n.tr("options.bar.density.comfortable")
      }]
    currentKey: Settings.data.bar.density
    onSelected: key => Settings.data.bar.density = key
  }

  ColumnLayout {
    spacing: Style.marginXXS * scaling
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("settings.bar.appearance.background-opacity.label")
      description: I18n.tr("settings.bar.appearance.background-opacity.description")
    }

    NValueSlider {
      Layout.fillWidth: true
      from: 0
      to: 1
      stepSize: 0.01
      value: Settings.data.bar.backgroundOpacity
      onMoved: value => Settings.data.bar.backgroundOpacity = value
      text: Math.floor(Settings.data.bar.backgroundOpacity * 100) + "%"
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.show-capsule.label")
    description: I18n.tr("settings.bar.appearance.show-capsule.description")
    checked: Settings.data.bar.showCapsule
    onToggled: checked => Settings.data.bar.showCapsule = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.bar.appearance.floating.label")
    description: I18n.tr("settings.bar.appearance.floating.description")
    checked: Settings.data.bar.floating
    onToggled: checked => Settings.data.bar.floating = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: "Auto Hide" 
    description: "Automatically hide the bar when not in use." 
    checked: Settings.data.bar.autoHide
    onToggled: checked => Settings.data.bar.autoHide = checked
  }

  // Floating bar options - only show when floating is enabled
  ColumnLayout {
    visible: Settings.data.bar.floating
    spacing: Style.marginS * scaling
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("settings.bar.appearance.margins.label")
      description: I18n.tr("settings.bar.appearance.margins.description")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginL * scaling

      ColumnLayout {
        spacing: Style.marginXXS * scaling

        NText {
          text: I18n.tr("settings.bar.appearance.margins.vertical")
          pointSize: Style.fontSizeXS * scaling
          color: Color.mOnSurfaceVariant
        }

        NValueSlider {
          Layout.fillWidth: true
          from: 0
          to: 1
          stepSize: 0.01
          value: Settings.data.bar.marginVertical
          onMoved: value => Settings.data.bar.marginVertical = value
          text: Math.round(Settings.data.bar.marginVertical * 100) + "%"
        }
      }

      ColumnLayout {
        spacing: Style.marginXXS * scaling

        NText {
          text: I18n.tr("settings.bar.appearance.margins.horizontal")
          pointSize: Style.fontSizeXS * scaling
          color: Color.mOnSurfaceVariant
        }

        NValueSlider {
          Layout.fillWidth: true
          from: 0
          to: 1
          stepSize: 0.01
          value: Settings.data.bar.marginHorizontal
          onMoved: value => Settings.data.bar.marginHorizontal = value
          text: Math.round(Settings.data.bar.marginHorizontal * 100) + "%"
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Widgets Management Section
  ColumnLayout {
    spacing: Style.marginXXS * scaling
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.bar.widgets.section.label")
      description: I18n.tr("settings.bar.widgets.section.description")
    }

    // Bar Sections
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.topMargin: Style.marginM * scaling
      spacing: Style.marginM * scaling

      // Left Section
      SectionEditor {
        sectionName: "Left"
        sectionId: "left"
        settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Settings/Bar/BarWidgetSettingsDialog.qml")
        widgetRegistry: BarWidgetRegistry
        widgetModel: Settings.data.bar.widgets.left
        availableWidgets: availableWidgets
        onAddWidget: (widgetId, section) => _addWidgetToSection(widgetId, section)
        onRemoveWidget: (section, index) => _removeWidgetFromSection(section, index)
        onReorderWidget: (section, fromIndex, toIndex) => _reorderWidgetInSection(section, fromIndex, toIndex)
        onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettingsInSection(section, index, settings)
        onMoveWidget: (fromSection, index, toSection) => _moveWidgetBetweenSections(fromSection, index, toSection)
        onDragPotentialStarted: root.handleDragStart()
        onDragPotentialEnded: root.handleDragEnd()
      }

      // Center Section
      SectionEditor {
        sectionName: "Center"
        sectionId: "center"
        settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Settings/Bar/BarWidgetSettingsDialog.qml")
        widgetRegistry: BarWidgetRegistry
        widgetModel: Settings.data.bar.widgets.center
        availableWidgets: availableWidgets
        onAddWidget: (widgetId, section) => _addWidgetToSection(widgetId, section)
        onRemoveWidget: (section, index) => _removeWidgetFromSection(section, index)
        onReorderWidget: (section, fromIndex, toIndex) => _reorderWidgetInSection(section, fromIndex, toIndex)
        onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettingsInSection(section, index, settings)
        onMoveWidget: (fromSection, index, toSection) => _moveWidgetBetweenSections(fromSection, index, toSection)
        onDragPotentialStarted: root.handleDragStart()
        onDragPotentialEnded: root.handleDragEnd()
      }

      // Right Section
      SectionEditor {
        sectionName: "Right"
        sectionId: "right"
        settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Settings/Bar/BarWidgetSettingsDialog.qml")
        widgetRegistry: BarWidgetRegistry
        widgetModel: Settings.data.bar.widgets.right
        availableWidgets: availableWidgets
        onAddWidget: (widgetId, section) => _addWidgetToSection(widgetId, section)
        onRemoveWidget: (section, index) => _removeWidgetFromSection(section, index)
        onReorderWidget: (section, fromIndex, toIndex) => _reorderWidgetInSection(section, fromIndex, toIndex)
        onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettingsInSection(section, index, settings)
        onMoveWidget: (fromSection, index, toSection) => _moveWidgetBetweenSections(fromSection, index, toSection)
        onDragPotentialStarted: root.handleDragStart()
        onDragPotentialEnded: root.handleDragEnd()
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Monitor Configuration
  ColumnLayout {
    spacing: Style.marginM * scaling
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
        description: I18n.tr("system.monitor-description", {
                               "model": modelData.model,
                               "width": modelData.width,
                               "height": modelData.height
                             })
        checked: (Settings.data.bar.monitors || []).indexOf(modelData.name) !== -1
        onToggled: checked => {
                     if (checked) {
                       Settings.data.bar.monitors = addMonitor(Settings.data.bar.monitors, modelData.name)
                     } else {
                       Settings.data.bar.monitors = removeMonitor(Settings.data.bar.monitors, modelData.name)
                     }
                   }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // ---------------------------------
  // Signal functions
  // ---------------------------------
  function _addWidgetToSection(widgetId, section) {
    var newWidget = {
      "id": widgetId
    }
    if (BarWidgetRegistry.widgetHasUserSettings(widgetId)) {
      var metadata = BarWidgetRegistry.widgetMetadata[widgetId]
      if (metadata) {
        Object.keys(metadata).forEach(function (key) {
          if (key !== "allowUserSettings") {
            newWidget[key] = metadata[key]
          }
        })
      }
    }
    Settings.data.bar.widgets[section].push(newWidget)
  }

  function _removeWidgetFromSection(section, index) {
    if (index >= 0 && index < Settings.data.bar.widgets[section].length) {
      var newArray = Settings.data.bar.widgets[section].slice()
      var removedWidgets = newArray.splice(index, 1)
      Settings.data.bar.widgets[section] = newArray

      // Check that we still have a control center
      if (removedWidgets[0].id === "ControlCenter" && BarService.lookupWidget("ControlCenter") === undefined) {
        ToastService.showWarning(I18n.tr("toast.missing-control-center.label"), I18n.tr("toast.missing-control-center.description"), 12000)
      }
    }
  }

  function _reorderWidgetInSection(section, fromIndex, toIndex) {
    if (fromIndex >= 0 && fromIndex < Settings.data.bar.widgets[section].length && toIndex >= 0 && toIndex < Settings.data.bar.widgets[section].length) {

      // Create a new array to avoid modifying the original
      var newArray = Settings.data.bar.widgets[section].slice()
      var item = newArray[fromIndex]
      newArray.splice(fromIndex, 1)
      newArray.splice(toIndex, 0, item)

      Settings.data.bar.widgets[section] = newArray
      //Logger.log("BarTab", "Widget reordered. New array:", JSON.stringify(newArray))
    }
  }

  function _updateWidgetSettingsInSection(section, index, settings) {
    // Update the widget settings in the Settings data
    Settings.data.bar.widgets[section][index] = settings
    //Logger.log("BarTab", `Updated widget settings for ${settings.id} in ${section} section`)
  }

  function _moveWidgetBetweenSections(fromSection, index, toSection) {
    // Get the widget from the source section
    if (index >= 0 && index < Settings.data.bar.widgets[fromSection].length) {
      var widget = Settings.data.bar.widgets[fromSection][index]

      // Remove from source section
      var sourceArray = Settings.data.bar.widgets[fromSection].slice()
      sourceArray.splice(index, 1)
      Settings.data.bar.widgets[fromSection] = sourceArray

      // Add to target section
      var targetArray = Settings.data.bar.widgets[toSection].slice()
      targetArray.push(widget)
      Settings.data.bar.widgets[toSection] = targetArray

      //Logger.log("BarTab", `Moved widget ${widget.id} from ${fromSection} to ${toSection}`)
    }
  }

  // Base list model for all combo boxes
  ListModel {
    id: availableWidgets
  }

  Component.onCompleted: {
    // Fill out availableWidgets ListModel
    availableWidgets.clear()
    BarWidgetRegistry.getAvailableWidgets().forEach(entry => {
                                                      availableWidgets.append({
                                                                                "key": entry,
                                                                                "name": entry
                                                                              })
                                                    })
  }
}
