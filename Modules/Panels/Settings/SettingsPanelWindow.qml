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
  minimumSize: Qt.size(820 * Style.uiScaleRatio, 910 * Style.uiScaleRatio)
  implicitWidth: Math.round(820 * Style.uiScaleRatio)
  implicitHeight: Math.round(910 * Style.uiScaleRatio)
  color: Color.mSurface

  visible: false

  // Register with SettingsPanelService
  Component.onCompleted: {
    SettingsPanelService.settingsWindow = root;
  }

  // Sync visibility with service
  onVisibleChanged: {
    if (visible) {
      settingsContent.requestedTab = SettingsPanelService.requestedTab;
      settingsContent.initialize();
      SettingsPanelService.isWindowOpen = true;
    } else {
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
