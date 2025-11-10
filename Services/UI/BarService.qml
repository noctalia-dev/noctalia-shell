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
      hasAudioVisualizer = false
      if (getAllWidgetInstances("AudioVisualizer").length > 0) {
        hasAudioVisualizer = true
        return
      }
      const widgets = getAllWidgetInstances("MediaMini")
      for (var i = 0; i < widgets.length; i++) {
        const widget = widgets[i]
        if (widget.showVisualizer) {
          hasAudioVisualizer = true
          return
        }
      }
    }
  }

  Component.onCompleted: {
    Logger.i("BarService", "Service started")
  }

  // Function for the Bar to call when it's ready
  function registerBar(screenName) {
    if (!readyBars[screenName]) {
      readyBars[screenName] = true
      Logger.d("BarService", "Bar is ready on screen:", screenName)
      barReadyChanged(screenName)
    }
  }

  // Function for the Dock to check if the bar is ready
  function isBarReady(screenName) {
    return readyBars[screenName] || false
  }

  // Register a widget instance
  function registerWidget(screenName, section, widgetId, index, instance) {
    const key = [screenName, section, widgetId, index].join("|")
    widgetInstances[key] = {
      "key": key,
      "screenName": screenName,
      "section": section,
      "widgetId": widgetId,
      "index": index,
      "instance": instance
    }

    timerCheckVisualizer.restart()

    Logger.d("BarService", "Registered widget:", key)
    root.activeWidgetsChanged()
  }

  // Unregister a widget instance
  function unregisterWidget(screenName, section, widgetId, index) {
    const key = [screenName, section, widgetId, index].join("|")
    delete widgetInstances[key]
    Logger.d("BarService", "Unregistered widget:", key)
    root.activeWidgetsChanged()
  }

  // Lookup a specific widget instance (returns the actual QML instance)
  function lookupWidget(widgetId, screenName = null, section = null, index = null) {
    // If looking for a specific instance
    if (screenName && section !== null) {
      for (var key in widgetInstances) {
        var widget = widgetInstances[key]
        if (widget.widgetId === widgetId && widget.screenName === screenName && widget.section === section) {
          if (index === null) {
            return widget.instance
          } else if (widget.index == index) {
            return widget.instance
          }
        }
      }
    }

    // Return first match if no specific screen/section specified
    for (var key in widgetInstances) {
      var widget = widgetInstances[key]
      if (widget.widgetId === widgetId) {
        if (!screenName || widget.screenName === screenName) {
          if (section === null || widget.section === section) {
            return widget.instance
          }
        }
      }
    }

    return undefined
  }

  // Get all instances of a widget type
  function getAllWidgetInstances(widgetId = null, screenName = null, section = null) {
    var instances = []

    for (var key in widgetInstances) {
      var widget = widgetInstances[key]

      var matches = true
      if (widgetId && widget.widgetId !== widgetId)
        matches = false
      if (screenName && widget.screenName !== screenName)
        matches = false
      if (section !== null && widget.section !== section)
        matches = false

      if (matches) {
        instances.push(widget.instance)
      }
    }

    return instances
  }

  // Get widget with full metadata
  function getWidgetWithMetadata(widgetId, screenName = null, section = null) {
    for (var key in widgetInstances) {
      var widget = widgetInstances[key]
      if (widget.widgetId === widgetId) {
        if (!screenName || widget.screenName === screenName) {
          if (section === null || widget.section === section) {
            return widget
          }
        }
      }
    }
    return undefined
  }

  // Get all widgets in a specific section
  function getWidgetsBySection(section, screenName = null) {
    var widgets = []

    for (var key in widgetInstances) {
      var widget = widgetInstances[key]
      if (widget.section === section) {
        if (!screenName || widget.screenName === screenName) {
          widgets.push(widget.instance)
        }
      }
    }

    // Sort by index to maintain order
    widgets.sort(function (a, b) {
      var aWidget = getWidgetWithMetadata(a.widgetId, a.screen?.name, a.section)
      var bWidget = getWidgetWithMetadata(b.widgetId, b.screen?.name, b.section)
      return (aWidget?.index || 0) - (bWidget?.index || 0)
    })

    return widgets
  }

  // Get all registered widgets (for debugging)
  function getAllRegisteredWidgets() {
    var result = []
    for (var key in widgetInstances) {
      result.push({
                    "key": key,
                    "widgetId": widgetInstances[key].widgetId,
                    "section": widgetInstances[key].section,
                    "screenName": widgetInstances[key].screenName,
                    "index": widgetInstances[key].index
                  })
    }
    return result
  }

  // Check if a widget type exists in a section
  function hasWidget(widgetId, section = null, screenName = null) {
    for (var key in widgetInstances) {
      var widget = widgetInstances[key]
      if (widget.widgetId === widgetId) {
        if (section === null || widget.section === section) {
          if (!screenName || widget.screenName === screenName) {
            return true
          }
        }
      }
    }
    return false
  }

  // Get pill direction for a widget instance
  function getPillDirection(widgetInstance) {
    try {
      if (widgetInstance.section === "left") {
        return true
      } else if (widgetInstance.section === "right") {
        return false
      } else {
        // middle section
        if (widgetInstance.sectionWidgetIndex < widgetInstance.sectionWidgetsCount / 2) {
          return false
        } else {
          return true
        }
      }
    } catch (e) {
      Logger.e(e)
    }
    return false
  }

  function getTooltipDirection() {
    switch (Settings.data.bar.position) {
    case "right":
      return "left"
    case "left":
      return "right"
    case "bottom":
      return "top"
    default:
      return "bottom"
    }
  }
}
