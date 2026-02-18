import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI
import qs.Widgets

FloatingWindow {
  id: root

  title: "Noctalia"
  minimumSize: Qt.size(840 * Style.uiScaleRatio, 910 * Style.uiScaleRatio)
  implicitWidth: Math.round(840 * Style.uiScaleRatio)
  implicitHeight: Math.round(910 * Style.uiScaleRatio)
  color: Color.mSurface

  visible: false

  // Register with SettingsPanelService
  Component.onCompleted: {
    SettingsPanelService.settingsWindow = root;
  }

  property bool isInitialized: false

  // Navigate to a specific tab and optional subtab.
  // Works whether the window is already visible or just becoming visible.
  function navigateTo(tab, subTab) {
    const tabId = tab !== undefined ? tab : 0;
    const subTabId = (subTab !== undefined && subTab !== null && subTab >= 0) ? subTab : -1;
    if (isInitialized) {
      settingsContent.navigateToTab(tabId, subTabId);
    } else {
      settingsContent.requestedTab = tabId;
      if (subTabId >= 0)
        settingsContent._pendingSubTab = subTabId;
      settingsContent.initialize();
      isInitialized = true;
    }
  }

  // Navigate to a search result entry.
  // Works whether the window is already visible or just becoming visible.
  function navigateToEntry(entry) {
    if (isInitialized) {
      Qt.callLater(() => settingsContent.navigateToResult(entry));
    } else {
      settingsContent.requestedTab = entry.tab;
      settingsContent.initialize();
      Qt.callLater(() => settingsContent.navigateToResult(entry));
      isInitialized = true;
    }
  }

  // Sync visibility with service
  onVisibleChanged: {
    if (visible) {
      SettingsPanelService.isWindowOpen = true;
    } else {
      isInitialized = false;
      SettingsPanelService.isWindowOpen = false;
    }
  }

  // Keyboard shortcuts
  Shortcut {
    sequence: "Escape"
    enabled: !PanelService.isKeybindRecording
    onActivated: SettingsPanelService.closeWindow()
  }

  Shortcut {
    sequence: "Tab"
    enabled: !PanelService.isKeybindRecording
    onActivated: settingsContent.selectNextTab()
  }

  Shortcut {
    sequence: "Backtab"
    enabled: !PanelService.isKeybindRecording
    onActivated: settingsContent.selectPreviousTab()
  }

  Shortcut {
    sequence: "Up"
    enabled: !PanelService.isKeybindRecording
    onActivated: settingsContent.scrollUp()
  }

  Shortcut {
    sequence: "Down"
    enabled: !PanelService.isKeybindRecording
    onActivated: settingsContent.scrollDown()
  }

  // Main content
  Rectangle {
    anchors.fill: parent
    color: "transparent"
    radius: Style.radiusL

    SettingsContent {
      id: settingsContent
      anchors.fill: parent
      onCloseRequested: SettingsPanelService.closeWindow()
    }
  }
}
