import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Noctalia
import qs.Services.System
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: 0

  property list<var> cardsModel: []
  property list<var> cardsDefault: [
    {
      "id": "profile-card",
      "text": "Profile",
      "enabled": true,
      "required": true
    },
    {
      "id": "shortcuts-card",
      "text": "Shortcuts",
      "enabled": true,
      "required": false
    },
    {
      "id": "audio-card",
      "text": "Audio Sliders",
      "enabled": true,
      "required": false
    },
    {
      "id": "brightness-card",
      "text": "Brightness",
      "enabled": false,
      "required": false
    },
    {
      "id": "weather-card",
      "text": "Weather",
      "enabled": true,
      "required": false
    },
    {
      "id": "media-sysmon-card",
      "text": "Media and System Monitor",
      "enabled": true,
      "required": false
    }
  ]

  Component.onCompleted: {
    // Fill out availableWidgets ListModel
    availableWidgets.clear();
    var sortedEntries = ControlCenterWidgetRegistry.getAvailableWidgets().slice().sort();
    sortedEntries.forEach(entry => {
                            const isPlugin = ControlCenterWidgetRegistry.isPluginWidget(entry);
                            let displayName = entry;
                            let badges = [];
                            if (isPlugin) {
                              const pluginId = entry.replace("plugin:", "");
                              const manifest = PluginRegistry.getPluginManifest(pluginId);
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
                            availableWidgets.append({
                                                      "key": entry,
                                                      "name": displayName,
                                                      "badges": badges
                                                    });
                          });
    // Starts empty
    cardsModel = [];

    // Add the cards available in settings
    for (var i = 0; i < Settings.data.controlCenter.cards.length; i++) {
      const settingCard = Settings.data.controlCenter.cards[i];

      for (var j = 0; j < cardsDefault.length; j++) {
        if (settingCard.id === cardsDefault[j].id) {
          var card = cardsDefault[j];
          card.enabled = settingCard.enabled;
          // Auto-disable weather card if weather is disabled
          if (card.id === "weather-card" && !Settings.data.location.weatherEnabled) {
            card.enabled = false;
          }
          cardsModel.push(card);
        }
      }
    }

    // Add any missing cards from default
    for (var i = 0; i < cardsDefault.length; i++) {
      var found = false;
      for (var j = 0; j < cardsModel.length; j++) {
        if (cardsModel[j].id === cardsDefault[i].id) {
          found = true;
          break;
        }
      }

      if (!found) {
        var card = cardsDefault[i];
        // Auto-disable weather card if weather is disabled
        if (card.id === "weather-card" && !Settings.data.location.weatherEnabled) {
          card.enabled = false;
        }
        cardsModel.push(card);
      }
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
      text: I18n.tr("common.cards")
      tabIndex: 1
      checked: subTabBar.currentIndex === 1
    }
    NTabButton {
      text: I18n.tr("common.shortcuts")
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
    Layout.fillWidth: true
    Layout.fillHeight: true

    AppearanceSubTab {}

    CardsSubTab {
      cardsModel: root.cardsModel
      cardsDefault: root.cardsDefault
    }

    ShortcutsSubTab {
      availableWidgets: availableWidgets
      onAddWidgetToSection: (widgetId, section) => _addWidgetToSection(widgetId, section)
      onRemoveWidgetFromSection: (section, index) => _removeWidgetFromSection(section, index)
      onReorderWidgetInSection: (section, fromIndex, toIndex) => _reorderWidgetInSection(section, fromIndex, toIndex)
      onUpdateWidgetSettingsInSection: (section, index, settings) => _updateWidgetSettingsInSection(section, index, settings)
      onMoveWidgetBetweenSections: (fromSection, index, toSection) => _moveWidgetBetweenSections(fromSection, index, toSection)
      onOpenPluginSettingsRequested: manifest => pluginSettingsDialog.openPluginSettings(manifest)
    }
  }

  // ---------------------------------
  // Signal functions
  // ---------------------------------
  function _addWidgetToSection(widgetId, section) {
    var newWidget = {
      "id": widgetId
    };
    if (ControlCenterWidgetRegistry.widgetHasUserSettings(widgetId)) {
      var metadata = ControlCenterWidgetRegistry.widgetMetadata[widgetId];
      if (metadata) {
        Object.keys(metadata).forEach(function (key) {
          newWidget[key] = metadata[key];
        });
      }
    }
    Settings.data.controlCenter.shortcuts[section].push(newWidget);
  }

  function _removeWidgetFromSection(section, index) {
    if (index >= 0 && index < Settings.data.controlCenter.shortcuts[section].length) {
      var newArray = Settings.data.controlCenter.shortcuts[section].slice();
      var removedWidgets = newArray.splice(index, 1);
      Settings.data.controlCenter.shortcuts[section] = newArray;
    }
  }

  function _reorderWidgetInSection(section, fromIndex, toIndex) {
    if (fromIndex >= 0 && fromIndex < Settings.data.controlCenter.shortcuts[section].length && toIndex >= 0 && toIndex < Settings.data.controlCenter.shortcuts[section].length) {

      // Create a new array to avoid modifying the original
      var newArray = Settings.data.controlCenter.shortcuts[section].slice();
      var item = newArray[fromIndex];
      newArray.splice(fromIndex, 1);
      newArray.splice(toIndex, 0, item);

      Settings.data.controlCenter.shortcuts[section] = newArray;
    }
  }

  function _moveWidgetBetweenSections(fromSection, index, toSection) {
    // Get the widget from the source section
    if (index >= 0 && index < Settings.data.controlCenter.shortcuts[fromSection].length) {
      var widget = Settings.data.controlCenter.shortcuts[fromSection][index];

      // Remove from source section
      var sourceArray = Settings.data.controlCenter.shortcuts[fromSection].slice();
      sourceArray.splice(index, 1);
      Settings.data.controlCenter.shortcuts[fromSection] = sourceArray;

      // Add to target section
      var targetArray = Settings.data.controlCenter.shortcuts[toSection].slice();
      targetArray.push(widget);
      Settings.data.controlCenter.shortcuts[toSection] = targetArray;
    }
  }

  function _updateWidgetSettingsInSection(section, index, settings) {
    // Create a new array to trigger QML's change detection for persistence.
    // This is crucial for Settings.data to detect the change and persist it.
    var newSectionArray = Settings.data.controlCenter.shortcuts[section].slice();
    newSectionArray[index] = settings;
    Settings.data.controlCenter.shortcuts[section] = newSectionArray;
    Settings.saveImmediate();
  }

  // Base list model for all combo boxes
  ListModel {
    id: availableWidgets
  }

  // Shared Plugin Settings Popup
  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: false
  }
}
