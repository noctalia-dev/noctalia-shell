pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Compositor

Singleton {
  id: root

  // A ref. to the lockScreen, so it's accessible from anywhere.
  property var lockScreen: null

  // Panels
  property var registeredPanels: ({})
  property var openedPanel: null
  property var closingPanel: null
  property bool closedImmediately: false
  // Brief window after panel opens where Exclusive keyboard is allowed on Hyprland
  // This allows text inputs to receive focus, then switches to OnDemand for click-to-close
  property bool isInitializingKeyboard: false
  signal willOpen
  signal didClose

  // Background slot assignments for dynamic panel background rendering
  // Slot 0: currently opening/open panel, Slot 1: closing panel
  property var backgroundSlotAssignments: [null, null]
  signal slotAssignmentChanged(int slotIndex, var panel)

  function assignToSlot(slotIndex, panel) {
    if (backgroundSlotAssignments[slotIndex] !== panel) {
      var newAssignments = backgroundSlotAssignments.slice();
      newAssignments[slotIndex] = panel;
      backgroundSlotAssignments = newAssignments;
      slotAssignmentChanged(slotIndex, panel);
    }
  }

  // Popup menu windows (one per screen) - used for both tray menus and context menus
  property var popupMenuWindows: ({})
  signal popupMenuWindowRegistered(var screen)

  // Register this panel (called after panel is loaded)
  function registerPanel(panel) {
    registeredPanels[panel.objectName] = panel;
    Logger.d("PanelService", "Registered panel:", panel.objectName);
  }

  // Register popup menu window for a screen
  function registerPopupMenuWindow(screen, window) {
    if (!screen || !window)
      return;
    var key = screen.name;
    popupMenuWindows[key] = window;
    Logger.d("PanelService", "Registered popup menu window for screen:", key);
    popupMenuWindowRegistered(screen);
  }

  // Get popup menu window for a screen
  function getPopupMenuWindow(screen) {
    if (!screen)
      return null;
    return popupMenuWindows[screen.name] || null;
  }

  // Returns a panel (loads it on-demand if not yet loaded)
  function getPanel(name, screen) {
    if (!screen) {
      Logger.d("PanelService", "missing screen for getPanel:", name);
      // If no screen specified, return the first matching panel
      for (var key in registeredPanels) {
        if (key.startsWith(name + "-")) {
          return registeredPanels[key];
        }
      }
      return null;
    }

    var panelKey = `${name}-${screen.name}`;

    // Check if panel is already loaded
    if (registeredPanels[panelKey]) {
      return registeredPanels[panelKey];
    }

    Logger.w("PanelService", "Panel not found:", panelKey);
    return null;
  }

  // Check if a panel exists
  function hasPanel(name) {
    return name in registeredPanels;
  }

  // Check if panels can be shown on a given screen (has bar enabled or allowPanelsOnScreenWithoutBar)
  function canShowPanelsOnScreen(screen) {
    const name = screen?.name || "";
    const monitors = Settings.data.bar.monitors || [];
    const allowPanelsOnScreenWithoutBar = Settings.data.general.allowPanelsOnScreenWithoutBar;
    return allowPanelsOnScreenWithoutBar || monitors.length === 0 || monitors.includes(name);
  }

  // Find a screen that can show panels
  function findScreenForPanels() {
    for (let i = 0; i < Quickshell.screens.length; i++) {
      if (canShowPanelsOnScreen(Quickshell.screens[i])) {
        return Quickshell.screens[i];
      }
    }
    return null;
  }

  // Timer to switch from Exclusive to OnDemand keyboard focus on Hyprland
  Timer {
    id: keyboardInitTimer
    interval: 100
    repeat: false
    onTriggered: {
      root.isInitializingKeyboard = false;
    }
  }

  // Helper to keep only one panel open at any time
  function willOpenPanel(panel) {
    if (openedPanel && openedPanel !== panel) {
      // Move current panel to closing slot before closing it
      closingPanel = openedPanel;
      assignToSlot(1, closingPanel);
      openedPanel.close();
    }

    // Assign new panel to open slot
    openedPanel = panel;
    assignToSlot(0, panel);

    // Start keyboard initialization period (for Hyprland workaround)
    if (panel.exclusiveKeyboard) {
      isInitializingKeyboard = true;
      keyboardInitTimer.restart();
    }

    // emit signal
    willOpen();
  }

  function closedPanel(panel) {
    if (openedPanel && openedPanel === panel) {
      openedPanel = null;
      assignToSlot(0, null);
    }

    if (closingPanel && closingPanel === panel) {
      closingPanel = null;
      assignToSlot(1, null);
    }

    // Reset keyboard init state
    isInitializingKeyboard = false;
    keyboardInitTimer.stop();

    // emit signal
    didClose();
  }

  // Close panels when compositor overview opens (if setting is enabled)
  Connections {
    target: CompositorService
    enabled: Settings.data.bar.hideOnOverview

    function onOverviewActiveChanged() {
      if (CompositorService.overviewActive && root.openedPanel) {
        root.openedPanel.close();
      }
    }
  }
}
