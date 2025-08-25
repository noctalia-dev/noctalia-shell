import QtQuick
import qs.Commons

QtObject {
  id: root

  // Signal emitted when widget loading status changes
  signal widgetLoaded(string widgetName)
  signal widgetFailed(string widgetName, string error)
  signal loadingComplete(int total, int loaded, int failed)

  // Properties to track loading status
  property int totalWidgets: 0
  property int loadedWidgets: 0
  property int failedWidgets: 0

  // Auto-discover widget components
  function getWidgetComponent(widgetName) {
    if (!widgetName || widgetName.trim() === "") {
      return null
    }

    const widgetPath = `../Modules/Bar/Widgets/${widgetName}.qml`

    // Try to load the widget directly from file
    const component = Qt.createComponent(widgetPath)
    if (component.status === Component.Ready) {
      return component
    }

    const errorMsg = `Failed to load ${widgetName}.qml widget, status: ${component.status}, error: ${component.errorString(
                     )}`
    Logger.error("WidgetLoader", errorMsg)
    return null
  }

  // Initialize loading tracking
  function initializeLoading(widgetList) {
    totalWidgets = widgetList.length
    loadedWidgets = 0
    failedWidgets = 0
  }

  // Track widget loading success
  function onWidgetLoaded(widgetName) {
    loadedWidgets++
    widgetLoaded(widgetName)

    if (loadedWidgets + failedWidgets === totalWidgets) {
      Logger.log("WidgetLoader", `Loaded ${loadedWidgets} widgets`)
      loadingComplete(totalWidgets, loadedWidgets, failedWidgets)
    }
  }

  // Track widget loading failure
  function onWidgetFailed(widgetName, error) {
    failedWidgets++
    widgetFailed(widgetName, error)

    if (loadedWidgets + failedWidgets === totalWidgets) {
      loadingComplete(totalWidgets, loadedWidgets, failedWidgets)
    }
  }

  // This is where you should add your Modules/Bar/Widgets/
  // so it gets registered in the BarTab
  function discoverAvailableWidgets() {
    const widgetFiles = [
        "ActiveWindow",
        "ArchUpdater",
        "Battery",
        "Bluetooth",
        "Brightness",
        "Clock",
        "KeyboardLayout",
        "MediaMini",
        "NotificationHistory",
        "PowerProfile",
        "ScreenRecorderIndicator",
        "SidePanelToggle",
        "SystemMonitor",
        "Tray",
        "Volume",
        "WiFi",
        "Workspace"
    ]
    const availableWidgets = []

    widgetFiles.forEach(widgetName => {
                          // Test if the widget can be loaded
                          const component = getWidgetComponent(widgetName)
                          if (component) {
                            availableWidgets.push({
                                                    "key": widgetName,
                                                    "name": widgetName
                                                  })
                          }
                        })

    // Sort alphabetically
    availableWidgets.sort((a, b) => a.name.localeCompare(b.name))

    return availableWidgets
  }
}
