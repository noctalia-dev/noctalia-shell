pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI

Singleton {
  id: root

  property bool isVisible: true

  // Computed visibility that factors in compositor overview state
  readonly property bool effectivelyVisible: {
    if (!isVisible) {
      return false;
    }
    if (Settings.data.bar.hideOnOverview && CompositorService.overviewActive) {
      return false;
    }
    return true;
  }

  property var readyBars: ({})

  // Revision counter - increment when widget list structure changes (add/remove/reorder)
  // This triggers Bar.qml to re-sync its ListModels
  property int widgetsRevision: 0

  // Registry to store actual widget instances
  // Key format: "screenName|section|widgetId|index"
  property var widgetInstances: ({})

  signal activeWidgetsChanged
  signal barReadyChanged(string screenName)
  signal barAutoHideStateChanged(string screenName, bool hidden)
  signal barHoverStateChanged(string screenName, bool hovered)

  // Track if a popup menu is open from the bar (prevents auto-hide)
  property bool popupOpen: false

  // Auto-hide state per screen: { screenName: { hovered: bool, hidden: bool } }
  property var screenAutoHideState: ({})

  // Get or create auto-hide state for a screen
  function getOrCreateAutoHideState(screenName) {
    if (!screenAutoHideState[screenName]) {
      screenAutoHideState[screenName] = {
        "hovered": false,
        "hidden": Settings.getBarDisplayModeForScreen(screenName) === "auto_hide"
      };
    }
    return screenAutoHideState[screenName];
  }

  // Set hover state for a screen
  function setScreenHovered(screenName, hovered) {
    var state = getOrCreateAutoHideState(screenName);
    if (state.hovered !== hovered) {
      state.hovered = hovered;
      screenAutoHideState = Object.assign({}, screenAutoHideState);
      barHoverStateChanged(screenName, hovered);
    }
  }

  // Set hidden state for a screen
  function setScreenHidden(screenName, hidden) {
    var state = getOrCreateAutoHideState(screenName);
    if (state.hidden !== hidden) {
      state.hidden = hidden;
      screenAutoHideState = Object.assign({}, screenAutoHideState);
      barAutoHideStateChanged(screenName, hidden);
    }
  }

  // Check if bar is hidden on a screen
  function isBarHidden(screenName) {
    var state = screenAutoHideState[screenName];
    return state ? state.hidden : false;
  }

  // Check if bar is hovered on a screen
  function isBarHovered(screenName) {
    var state = screenAutoHideState[screenName];
    return state ? state.hovered : false;
  }

  // Toggle bar visibility. In auto-hide mode, toggles the auto-hide state
  // on screens with auto-hide enabled. For other screens, toggles global isVisible flag.
  function toggleVisibility() {
    // Check if any auto-hide screen is currently visible
    var anyAutoHideVisible = false;
    var hasAutoHideScreens = false;
    for (var screenName in screenAutoHideState) {
      if (Settings.getBarDisplayModeForScreen(screenName) === "auto_hide") {
        hasAutoHideScreens = true;
        if (!screenAutoHideState[screenName].hidden) {
          anyAutoHideVisible = true;
          break;
        }
      }
    }

    // Toggle auto-hide screens
    if (hasAutoHideScreens) {
      for (var screenName in screenAutoHideState) {
        if (Settings.getBarDisplayModeForScreen(screenName) === "auto_hide") {
          setScreenHidden(screenName, anyAutoHideVisible);
        }
      }
    }

    // Toggle global visibility (affects non-auto-hide screens)
    isVisible = !isVisible;
  }

  // Show bar. In auto-hide mode, un-hides on screens with auto-hide enabled.
  function show() {
    // Show auto-hide screens
    for (var screenName in screenAutoHideState) {
      if (Settings.getBarDisplayModeForScreen(screenName) === "auto_hide") {
        setScreenHidden(screenName, false);
      }
    }
    // Set global visibility (affects non-auto-hide screens)
    isVisible = true;
  }

  // Hide bar. In auto-hide mode, hides on screens with auto-hide enabled.
  function hide() {
    // Hide auto-hide screens
    for (var screenName in screenAutoHideState) {
      if (Settings.getBarDisplayModeForScreen(screenName) === "auto_hide") {
        setScreenHidden(screenName, true);
      }
    }
    // Set global visibility (affects non-auto-hide screens)
    isVisible = false;
  }

  Component.onCompleted: {
    Logger.i("BarService", "Service started");
  }

  // update bar's hidden state when mode changes
  Connections {
    target: Settings.data.bar
    function onDisplayModeChanged() {
      Logger.d("BarService", "Display mode changed to:", Settings.data.bar.displayMode);

      // Only affect screens without displayMode overrides
      for (let screenName in screenAutoHideState) {
        if (!Settings.hasScreenOverride(screenName, "displayMode")) {
          var displayMode = Settings.getBarDisplayModeForScreen(screenName);
          if (displayMode === "auto_hide") {
            setScreenHidden(screenName, true);
          } else {
            if (screenAutoHideState[screenName].hidden) {
              setScreenHidden(screenName, false);
            }
          }
        }
      }
    }

    function onScreenOverridesChanged() {
      Logger.d("BarService", "Screen overrides changed, re-evaluating auto-hide states");

      // Re-evaluate auto-hide state for all screens
      for (let screenName in screenAutoHideState) {
        var displayMode = Settings.getBarDisplayModeForScreen(screenName);
        if (displayMode === "auto_hide") {
          if (!screenAutoHideState[screenName].hidden) {
            setScreenHidden(screenName, true);
          }
        } else {
          if (screenAutoHideState[screenName].hidden) {
            setScreenHidden(screenName, false);
          }
        }
      }
    }
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
    var widgetEntries = [];

    for (var key in widgetInstances) {
      var widget = widgetInstances[key];
      if (!widget)
        continue;
      if (widget.section === section) {
        if (!screenName || widget.screenName === screenName) {
          widgetEntries.push(widget);
        }
      }
    }

    // Sort by index to maintain order
    widgetEntries.sort(function (a, b) {
      return (a.index || 0) - (b.index || 0);
    });

    // Return just the instances
    return widgetEntries.map(function (w) {
      return w.instance;
    });
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
        return false;
      } else if (widgetInstance.section === "right") {
        return true;
      } else {
        // middle section
        if (widgetInstance.sectionWidgetIndex < widgetInstance.sectionWidgetsCount / 2) {
          return true;
        } else {
          return false;
        }
      }
    } catch (e) {
      Logger.e(e);
    }
    return true;
  }

  function getTooltipDirection(screenName) {
    const position = Settings.getBarPositionForScreen(screenName);
    switch (position) {
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

  // Helper to close any existing dialogs in a popup menu window
  function closeExistingDialogs(popupMenuWindow) {
    if (!popupMenuWindow || !popupMenuWindow.dialogParent)
      return;

    var dialogParent = popupMenuWindow.dialogParent;
    for (var i = dialogParent.children.length - 1; i >= 0; i--) {
      var child = dialogParent.children[i];
      if (child && typeof child.close === "function") {
        child.close();
      }
    }
    popupMenuWindow.hasDialog = false;
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

    // Close any existing dialogs first to prevent stacking
    closeExistingDialogs(popupMenuWindow);

    if (PanelService.openedPanel) {
      PanelService.openedPanel.close();
    }

    var component = Qt.createComponent(Quickshell.shellDir + "/Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml");

    function instantiateAndOpen() {
      // Use dialogParent (Item) instead of window directly for proper Popup anchoring
      var dialog = component.createObject(popupMenuWindow.dialogParent, {
                                            "widgetIndex": index,
                                            "widgetData": widgetData,
                                            "widgetId": widgetId,
                                            "sectionId": section,
                                            "screen": screen
                                          });

      if (dialog) {
        dialog.updateWidgetSettings.connect((sec, idx, settings) => {
                                              var screenName = screen?.name || "";
                                              if (Settings.hasScreenOverride(screenName, "widgets")) {
                                                var overrideWidgets = Settings.getBarWidgetsForScreen(screenName);
                                                if (overrideWidgets && overrideWidgets[sec] && idx < overrideWidgets[sec].length) {
                                                  overrideWidgets[sec][idx] = Object.assign({}, overrideWidgets[sec][idx], settings);
                                                  Settings.setScreenOverride(screenName, "widgets", overrideWidgets);
                                                }
                                              } else {
                                                var widgets = Settings.data.bar.widgets[sec];
                                                if (widgets && idx < widgets.length) {
                                                  widgets[idx] = Object.assign({}, widgets[idx], settings);
                                                  Settings.data.bar.widgets[sec] = widgets;
                                                  Settings.saveImmediate();
                                                }
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

  // Open plugin settings dialog
  // Parameters:
  //   screen: The screen to show the dialog on
  //   pluginManifest: The plugin's manifest object (must have entryPoints.settings)
  function openPluginSettings(screen, pluginManifest) {
    if (!pluginManifest || !pluginManifest.entryPoints || !pluginManifest.entryPoints.settings) {
      Logger.e("BarService", "Cannot open plugin settings: no settings entry point");
      return;
    }

    // Get the popup menu window to use as parent
    var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
    if (!popupMenuWindow) {
      Logger.e("BarService", "No popup menu window found for screen");
      return;
    }

    // Close any existing dialogs first to prevent stacking
    closeExistingDialogs(popupMenuWindow);

    var component = Qt.createComponent(Quickshell.shellDir + "/Widgets/NPluginSettingsPopup.qml");

    function instantiateAndOpen() {
      var dialog = component.createObject(popupMenuWindow.dialogParent, {
                                            "showToastOnSave": true,
                                            "screen": screen
                                          });

      if (dialog) {
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
        dialog.openPluginSettings(pluginManifest);
      } else {
        Logger.e("BarService", "Failed to create plugin settings dialog");
      }
    }

    if (component.status === Component.Ready) {
      instantiateAndOpen();
    } else if (component.status === Component.Error) {
      Logger.e("BarService", "Error loading plugin settings dialog:", component.errorString());
    } else {
      component.statusChanged.connect(function () {
        if (component.status === Component.Ready) {
          instantiateAndOpen();
        } else if (component.status === Component.Error) {
          Logger.e("BarService", "Error loading plugin settings dialog:", component.errorString());
        }
      });
    }
  }
}
