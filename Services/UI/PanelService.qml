pragma Singleton

import Quickshell
import qs.Commons

Singleton {
  id: root

  // A ref. to the lockScreen, so it's accessible from anywhere
  // This is not a panel...
  property var lockScreen: null

  // Panels
  property var registeredPanels: ({})
  property var openedPanel: null
  signal willOpen
  signal didClose

  // Register this panel (called after panel is loaded)
  function registerPanel(panel) {
    registeredPanels[panel.objectName] = panel
    Logger.d("PanelService", "Registered panel:", panel.objectName)
  }

  // Returns a panel (loads it on-demand if not yet loaded)
  function getPanel(name, screen) {
    if (!screen) {
      Logger.d("PanelService", "missing screen for getPanel:", name)
      // If no screen specified, return the first matching panel
      for (var key in registeredPanels) {
        if (key.startsWith(name + "-")) {
          return registeredPanels[key]
        }
      }
      return null
    }

    var panelKey = `${name}-${screen.name}`

    // Check if panel is already loaded
    if (registeredPanels[panelKey]) {
      return registeredPanels[panelKey]
    }

    Logger.w("PanelService", "Panel not found:", panelKey)
    return null
  }

  // Check if a panel exists
  function hasPanel(name) {
    return name in registeredPanels
  }

  // Helper to keep only one panel open at any time
  function willOpenPanel(panel) {
    if (openedPanel && openedPanel !== panel) {
      openedPanel.close()
    }
    openedPanel = panel

    // emit signal
    willOpen()
  }

  function closedPanel(panel) {
    if (openedPanel && openedPanel === panel) {
      openedPanel = null
    }

    // emit signal
    didClose()
  }
}
