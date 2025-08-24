pragma Singleton

import Quickshell

Singleton {
  id: root

  // A ref. to the sidePanel, so it's accessible from other services
  property var sidePanel: null

  // A ref. to the lockScreen, so it's accessible from other services
  property var lockScreen: null

  // A ref. to the updatePanel, so it's accessible from other services
  property var updatePanel: null

  // Currently opened panel
  property var openedPanel: null

  function registerOpen(panel) {
    if (openedPanel && openedPanel != panel) {
      openedPanel.close()
    }
    openedPanel = panel
  }
}
