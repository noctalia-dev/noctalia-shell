import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL

  property list<var> cardsModel: []
  property list<var> cardsDefault: [{
      "id": "profile-card",
      "text": "Profile",
      "enabled": true,
      "required": true
    }, {
      "id": "shortcuts-card",
      "text": "Shortcuts",
      "enabled": true,
      "required": false
    }, {
      "id": "audio-card",
      "text": "Audio Sliders",
      "enabled": true,
      "required": false
    }, {
      "id": "weather-card",
      "text": "Weather",
      "enabled": true,
      "required": false
    }, {
      "id": "media-sysmon-card",
      "text": "Media and System Monitor",
      "enabled": true,
      "required": false
    }]

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

  function saveCards() {
    var toSave = []
    for (var i = 0; i < cardsModel.length; i++) {
      toSave.push({
                    "id": cardsModel[i].id,
                    "enabled": cardsModel[i].enabled
                  })
    }
    Settings.data.controlCenter.cards = toSave
  }

  Component.onCompleted: {
    // Fill out availableWidgets ListModel
    availableWidgets.clear()
    ControlCenterWidgetRegistry.getAvailableWidgets().forEach(entry => {
                                                                availableWidgets.append({
                                                                                          "key": entry,
                                                                                          "name": entry
                                                                                        })
                                                              })
    // Starts empty
    cardsModel = []

    // Add the cards available in settings
    for (var i = 0; i < Settings.data.controlCenter.cards.length; i++) {
      const settingCard = Settings.data.controlCenter.cards[i]

      for (var j = 0; j < cardsDefault.length; j++) {
        if (settingCard.id === cardsDefault[j].id) {
          var card = cardsDefault[j]
          card.enabled = settingCard.enabled
          cardsModel.push(card)
        }
      }
    }

    // Add any missing cards from default
    for (var i = 0; i < cardsDefault.length; i++) {
      var found = false
      for (var j = 0; j < cardsModel.length; j++) {
        if (cardsModel[j].id === cardsDefault[i].id) {
          found = true
          break
        }
      }

      if (!found) {
        cardsModel.push(cardsDefault[i])
      }
    }

    saveCards()
  }

  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.control-center.section.label")
      description: I18n.tr("settings.control-center.section.description")
    }

    NComboBox {
      id: controlCenterPosition
      label: I18n.tr("settings.control-center.position.label")
      description: I18n.tr("settings.control-center.position.description")
      Layout.fillWidth: true
      model: [{
          "key": "close_to_bar_button",
          "name": I18n.tr("options.control-center.position.close_to_bar_button")
        }, {
          "key": "top_left",
          "name": I18n.tr("options.control-center.position.top_left")
        }, {
          "key": "top_right",
          "name": I18n.tr("options.control-center.position.top_right")
        }, {
          "key": "bottom_left",
          "name": I18n.tr("options.control-center.position.bottom_left")
        }, {
          "key": "bottom_right",
          "name": I18n.tr("options.control-center.position.bottom_right")
        }, {
          "key": "bottom_center",
          "name": I18n.tr("options.control-center.position.bottom_center")
        }, {
          "key": "top_center",
          "name": I18n.tr("options.control-center.position.top_center")
        }, {
          "key": "center",
          "name": I18n.tr("options.control-center.position.center")
        }]
      currentKey: Settings.data.controlCenter.position
      onSelected: function (key) {
        Settings.data.controlCenter.position = key
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }

  // Widgets Management Section
  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.control-center.cards.section.label")
      description: I18n.tr("settings.control-center.cards.section.description")
    }

    NReorderCheckboxes {
      Layout.fillWidth: true
      model: cardsModel
      onDragPotentialStarted: {
        root.handleDragStart()
      }
      onDragPotentialEnded: {
        root.handleDragEnd()
      }
      onItemToggled: function (index, enabled) {
        //Logger.log("ControlCenterTab", "Item", index, "toggled to", enabled)
        var newModel = cardsModel.slice()
        newModel[index] = Object.assign({}, newModel[index], {
                                          "enabled": enabled
                                        })
        cardsModel = newModel
        saveCards()
      }
      onItemsReordered: function (fromIndex, toIndex) {
        //Logger.log("ControlCenterTab", "Item moved from", fromIndex, "to", toIndex)
        var newModel = cardsModel.slice()
        var item = newModel.splice(fromIndex, 1)[0]
        newModel.splice(toIndex, 0, item)
        cardsModel = newModel
        saveCards()
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }

  // Widgets Management Section
  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.control-center.shortcuts.section.label")
      description: I18n.tr("settings.control-center.shortcuts.section.description")
    }

    // Sections
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.topMargin: Style.marginM
      spacing: Style.marginM

      // Left
      NSectionEditor {
        sectionName: I18n.tr("settings.control-center.shortcuts.sectionLeft")
        sectionId: "left"
        settingsDialogComponent: ""
        maxWidgets: 5
        widgetRegistry: ControlCenterWidgetRegistry
        widgetModel: Settings.data.controlCenter.shortcuts["left"]
        availableWidgets: availableWidgets
        availableSections: ["left", "right"]
        onAddWidget: (widgetId, section) => _addWidgetToSection(widgetId, section)
        onRemoveWidget: (section, index) => _removeWidgetFromSection(section, index)
        onReorderWidget: (section, fromIndex, toIndex) => _reorderWidgetInSection(section, fromIndex, toIndex)
        onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettingsInSection(section, index, settings)
        onMoveWidget: (fromSection, index, toSection) => _moveWidgetBetweenSections(fromSection, index, toSection)
        onDragPotentialStarted: root.handleDragStart()
        onDragPotentialEnded: root.handleDragEnd()
      }

      // Right
      NSectionEditor {
        sectionName: I18n.tr("settings.control-center.shortcuts.sectionRight")
        sectionId: "right"
        settingsDialogComponent: ""
        maxWidgets: 5
        widgetRegistry: ControlCenterWidgetRegistry
        widgetModel: Settings.data.controlCenter.shortcuts["right"]
        availableWidgets: availableWidgets
        availableSections: ["left", "right"]
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
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }

  // ---------------------------------
  // Signal functions
  // ---------------------------------
  function _addWidgetToSection(widgetId, section) {
    var newWidget = {
      "id": widgetId
    }
    if (ControlCenterWidgetRegistry.widgetHasUserSettings(widgetId)) {
      var metadata = ControlCenterWidgetRegistry.widgetMetadata[widgetId]
      if (metadata) {
        Object.keys(metadata).forEach(function (key) {
          if (key !== "allowUserSettings") {
            newWidget[key] = metadata[key]
          }
        })
      }
    }
    Settings.data.controlCenter.shortcuts[section].push(newWidget)
  }

  function _removeWidgetFromSection(section, index) {
    if (index >= 0 && index < Settings.data.controlCenter.shortcuts[section].length) {
      var newArray = Settings.data.controlCenter.shortcuts[section].slice()
      var removedWidgets = newArray.splice(index, 1)
      Settings.data.controlCenter.shortcuts[section] = newArray
    }
  }

  function _reorderWidgetInSection(section, fromIndex, toIndex) {
    if (fromIndex >= 0 && fromIndex < Settings.data.controlCenter.shortcuts[section].length && toIndex >= 0 && toIndex < Settings.data.controlCenter.shortcuts[section].length) {

      // Create a new array to avoid modifying the original
      var newArray = Settings.data.controlCenter.shortcuts[section].slice()
      var item = newArray[fromIndex]
      newArray.splice(fromIndex, 1)
      newArray.splice(toIndex, 0, item)

      Settings.data.controlCenter.shortcuts[section] = newArray
    }
  }

  function _moveWidgetBetweenSections(fromSection, index, toSection) {
    // Get the widget from the source section
    if (index >= 0 && index < Settings.data.controlCenter.shortcuts[fromSection].length) {
      var widget = Settings.data.controlCenter.shortcuts[fromSection][index]

      // Remove from source section
      var sourceArray = Settings.data.controlCenter.shortcuts[fromSection].slice()
      sourceArray.splice(index, 1)
      Settings.data.controlCenter.shortcuts[fromSection] = sourceArray

      // Add to target section
      var targetArray = Settings.data.controlCenter.shortcuts[toSection].slice()
      targetArray.push(widget)
      Settings.data.controlCenter.shortcuts[toSection] = targetArray

      //Logger.log("BarTab", `Moved widget ${widget.id} from ${fromSection} to ${toSection}`)
    }
  }

  function _updateWidgetSettingsInSection(section, index, settings) {
    // Update the widget settings in the Settings data
    Settings.data.controlCenter.shortcuts[section][index] = settings
  }

  // Base list model for all combo boxes
  ListModel {
    id: availableWidgets
  }
}
