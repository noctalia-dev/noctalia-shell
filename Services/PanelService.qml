pragma Singleton

import Quickshell
import qs.Commons

Singleton {
  id: root

  // A ref. to the lockScreen, so it's accessible from anywhere
  // This is not a panel...
  property var lockScreen: null

  // Currently opened panel
  property var openedPanel: null

  property var registeredPanels: ({})

  // Register this panel
  function registerPanel(panel) {
    registeredPanels[panel.objectName] = panel
    Logger.log("PanelService", "Registered:", panel.objectName)
  }

  // Returns a panel
  function getPanel(name) {
    return registeredPanels[name] || null
  }

  // Check if a panel exists
  function hasPanel(name) {
    return name in registeredPanels
  }

  // Helper to keep only one panel open at any time
  function willOpenPanel(panel) {
    if (openedPanel && openedPanel != panel) {
      openedPanel.close()
    }
    openedPanel = panel
  }
}
