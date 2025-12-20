pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  property bool hasAudioVisualizer: false
  property bool isVisible: true
  property var readyBars: ({})

  // Registry to store actual widget instances
  // Key format: "screenName|section|widgetId|index"
  property var widgetInstances: ({})

  signal activeWidgetsChanged
  signal barReadyChanged(string screenName)

  // onHasAudioVisualizerChanged: {
  //   Logger.d("BarService", "hasAudioVisualizer", hasAudioVisualizer)
  // }

  // Simple timer that run once when the widget structure has changed
  // and determine if any MediaMini widget has the visualizer on
  Timer {
    id: timerCheckVisualizer
    interval: 100
    repeat: false
    onTriggered: {
      hasAudioVisualizer = false;
      if (getAllWidgetInstances("AudioVisualizer").length > 0) {
        hasAudioVisualizer = true;
        return;
      }
      const widgets = getAllWidgetInstances("MediaMini");
      for (var i = 0; i < widgets.length; i++) {
        const widget = widgets[i];
        if (widget.showVisualizer) {
          hasAudioVisualizer = true;
          return;
        }
      }
    }
  }

  Component.onCompleted: {
    Logger.i("BarService", "Service started");
  }

  // Function for the Bar to call when it's ready
  function registerBar(screenName) {
    if (!readyBars[screenName]) {
      readyBars[screenName] = true;
      Logger.d("BarService", "Bar is ready on screen:", screenName);
      barReadyChanged(screenName);
    }
  }

  // Function for the Dock to check if the bar is ready
  function isBarReady(screenName) {
    return readyBars[screenName] || false;
  }

  // Register a widget instance
  function registerWidget(screenName, section, widgetId, index, instance) {
    const key = [screenName, section, widgetId, index].join("|");
    widgetInstances[key] = {
      "key": key,
      "screenName": screenName,
      "section": section,
      "widgetId": widgetId,
      "index": index,
      "instance": instance
    };

    timerCheckVisualizer.restart();

    Logger.d("BarService", "Registered widget:", key);
    root.activeWidgetsChanged();
  }

  // Unregister a widget instance
  function unregisterWidget(screenName, section, widgetId, index) {
    const key = [screenName, section, widgetId, index].join("|");
    delete widgetInstances[key];
    Logger.d("BarService", "Unregistered widget:", key);
    root.activeWidgetsChanged();
  }

  // Lookup a specific widget instance (returns the actual QML instance)
  function lookupWidget(widgetId, screenName = null, section = null, index = null) {
    // If looking for a specific instance
    if (screenName && section !== null) {
      for (var key in widgetInstances) {
        var widget = widgetInstances[key];
        if (!widget)
          continue;
        if (widget.widgetId === widgetId && widget.screenName === screenName && widget.section === section) {
          if (index === null) {
            return widget.instance;
          } else if (widget.index == index) {
            return widget.instance;
          }
        }
      }
    }

    // Return first match if no specific screen/section specified
    for (var key in widgetInstances) {
      var widget = widgetInstances[key];
      if (!widget)
        continue;
      if (widget.widgetId === widgetId) {
        if (!screenName || widget.screenName === screenName) {
          if (section === null || widget.section === section) {
            return widget.instance;
          }
        }
      }
    }

    return undefined;
  }

  // Get all instances of a widget type
  function getAllWidgetInstances(widgetId = null, screenName = null, section = null) {
    var instances = [];

    for (var key in widgetInstances) {
      var widget = widgetInstances[key];
      if (!widget)
        continue;

      var matches = true;
      if (widgetId && widget.widgetId !== widgetId)
        matches = false;
      if (screenName && widget.screenName !== screenName)
        matches = false;
      if (section !== null && widget.section !== section)
        matches = false;

      if (matches) {
        instances.push(widget.instance);
      }
    }

    return instances;
  }

  // Get widget with full metadata
  function getWidgetWithMetadata(widgetId, screenName = null, section = null) {
    for (var key in widgetInstances) {
      var widget = widgetInstances[key];
      if (!widget)
        continue;
      if (widget.widgetId === widgetId) {
        if (!screenName || widget.screenName === screenName) {
          if (section === null || widget.section === section) {
            return widget;
          }
        }
      }
    }
    return undefined;
  }

  // Get all widgets in a specific section
  function getWidgetsBySection(section, screenName = null) {
    var widgets = [];

    for (var key in widgetInstances) {
      var widget = widgetInstances[key];
      if (!widget)
        continue;
      if (widget.section === section) {
        if (!screenName || widget.screenName === screenName) {
          widgets.push(widget.instance);
        }
      }
    }

    // Sort by index to maintain order
    widgets.sort(function (a, b) {
      var aWidget = getWidgetWithMetadata(a.widgetId, a.screen?.name, a.section);
      var bWidget = getWidgetWithMetadata(b.widgetId, b.screen?.name, b.section);
      return (aWidget?.index || 0) - (bWidget?.index || 0);
    });

    return widgets;
  }

  // Get all registered widgets (for debugging)
  function getAllRegisteredWidgets() {
    var result = [];
    for (var key in widgetInstances) {
      var widget = widgetInstances[key];
      if (!widget)
        continue;
      result.push({
                    "key": key,
                    "widgetId": widget.widgetId,
                    "section": widget.section,
                    "screenName": widget.screenName,
                    "index": widget.index
                  });
    }
    return result;
  }

  // Check if a widget type exists in a section
  function hasWidget(widgetId, section = null, screenName = null) {
    for (var key in widgetInstances) {
      var widget = widgetInstances[key];
      if (!widget)
        continue;
      if (widget.widgetId === widgetId) {
        if (section === null || widget.section === section) {
          if (!screenName || widget.screenName === screenName) {
            return true;
          }
        }
      }
    }
    return false;
  }

  // Unregister all widget instances for a plugin (used during hot reload)
  // Note: We don't destroy instances here - the Loader manages that when the component is unregistered
  function destroyPluginWidgetInstances(pluginId) {
    var widgetId = "plugin:" + pluginId;
    var keysToRemove = [];

    // Find all instances of this plugin's widget
    for (var key in widgetInstances) {
      var widget = widgetInstances[key];
      if (widget && widget.widgetId === widgetId) {
        keysToRemove.push(key);
        Logger.d("BarService", "Unregistering plugin widget instance:", key);
      }
    }

    // Remove from registry
    for (var i = 0; i < keysToRemove.length; i++) {
      delete widgetInstances[keysToRemove[i]];
    }

    if (keysToRemove.length > 0) {
      Logger.i("BarService", "Unregistered", keysToRemove.length, "instance(s) of plugin widget:", widgetId);
      root.activeWidgetsChanged();
    }
  }

  // Get pill direction for a widget instance
  function getPillDirection(widgetInstance) {
    try {
      if (widgetInstance.section === "left") {
        return true;
      } else if (widgetInstance.section === "right") {
        return false;
      } else {
        // middle section
        if (widgetInstance.sectionWidgetIndex < widgetInstance.sectionWidgetsCount / 2) {
          return false;
        } else {
          return true;
        }
      }
    } catch (e) {
      Logger.e(e);
    }
    return false;
  }

  function getTooltipDirection() {
    switch (Settings.data.bar.position) {
    case "right":
      return "left";
    case "left":
      return "right";
    case "bottom":
      return "top";
    default:
      return "bottom";
    }
  }

  // Open widget settings dialog for a bar widget
  // Parameters:
  //   screen: The screen to show the dialog on
  //   section: Section id ("left", "center", "right")
  //   index: Widget index in section
  //   widgetId: Widget type id (e.g., "Volume")
  //   widgetData: Current widget settings object
  function openWidgetSettings(screen, section, index, widgetId, widgetData) {
    // Get the popup menu window to use as parent (avoids clipping issues with bar height)
    var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
    if (!popupMenuWindow) {
      Logger.e("BarService", "No popup menu window found for screen");
      return;
    }

    var component = Qt.createComponent(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml");

    function instantiateAndOpen() {
      // Use dialogParent (Item) instead of window directly for proper Popup anchoring
      var dialog = component.createObject(popupMenuWindow.dialogParent, {
                                            "widgetIndex": index,
                                            "widgetData": widgetData,
                                            "widgetId": widgetId,
                                            "sectionId": section
                                          });

      if (dialog) {
        dialog.updateWidgetSettings.connect((sec, idx, settings) => {
                                              var widgets = Settings.data.bar.widgets[sec];
                                              if (widgets && idx < widgets.length) {
                                                widgets[idx] = Object.assign({}, widgets[idx], settings);
                                                Settings.data.bar.widgets[sec] = widgets;
                                                Settings.saveImmediate();
                                              }
                                            });
        // Enable keyboard focus for the popup menu window when dialog is open
        popupMenuWindow.hasDialog = true;
        // Close the popup menu window when dialog closes
        dialog.closed.connect(() => {
                                popupMenuWindow.hasDialog = false;
                                popupMenuWindow.close();
                                dialog.destroy();
                              });
        // Show the popup menu window and open the dialog
        popupMenuWindow.open();
        dialog.open();
      } else {
        Logger.e("BarService", "Failed to create widget settings dialog");
      }
    }

    if (component.status === Component.Ready) {
      instantiateAndOpen();
    } else if (component.status === Component.Error) {
      Logger.e("BarService", "Error loading widget settings dialog:", component.errorString());
    } else {
      component.statusChanged.connect(function () {
        if (component.status === Component.Ready) {
          instantiateAndOpen();
        } else if (component.status === Component.Error) {
          Logger.e("BarService", "Error loading widget settings dialog:", component.errorString());
        }
      });
    }
  }
}
