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

  // Sync visibility with service
  onVisibleChanged: {
    if (visible) {
      if (!isInitialized) {
        // Check if we have a search entry to navigate to
        if (SettingsPanelService.requestedEntry) {
          const entry = SettingsPanelService.requestedEntry;
          SettingsPanelService.requestedEntry = null;
          settingsContent.requestedTab = entry.tab;
          settingsContent.initialize();
          Qt.callLater(() => settingsContent.navigateToResult(entry));
        } else {
          settingsContent.requestedTab = SettingsPanelService.requestedTab;
          settingsContent.initialize();
          if (SettingsPanelService.requestedSubTab >= 0) {
            const tab = SettingsPanelService.requestedTab;
            const subTab = SettingsPanelService.requestedSubTab;
            SettingsPanelService.requestedSubTab = -1;
            Qt.callLater(() => settingsContent.navigateToTab(tab, subTab));
          }
        }
        isInitialized = true;
      }
      SettingsPanelService.isWindowOpen = true;
    } else {
      isInitialized = false;
      SettingsPanelService.isWindowOpen = false;
    }
  }

  // Keyboard shortcuts
  Shortcut {
    sequence: "Escape"
    onActivated: SettingsPanelService.closeWindow()
  }

  Shortcut {
    sequence: "Tab"
    onActivated: settingsContent.selectNextTab()
  }

  Shortcut {
    sequence: "Backtab"
    onActivated: settingsContent.selectPreviousTab()
  }

  Shortcut {
    sequence: "Up"
    onActivated: settingsContent.scrollUp()
  }

  Shortcut {
    sequence: "Down"
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
