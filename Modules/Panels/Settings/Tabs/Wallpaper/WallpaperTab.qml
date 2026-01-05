import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: 0

  property var screen

  function openMainFolderPicker() {
    mainFolderPicker.open();
  }

  function openMonitorFolderPicker(monitorName) {
    specificFolderMonitorName = monitorName;
    monitorFolderPicker.open();
  }

  property string specificFolderMonitorName: ""

  NTabBar {
    id: subTabBar
    Layout.fillWidth: true
    distributeEvenly: true
    currentIndex: tabView.currentIndex

    NTabButton {
      text: I18n.tr("settings.wallpaper.tabs.settings")
      tabIndex: 0
      checked: subTabBar.currentIndex === 0
    }
    NTabButton {
      text: I18n.tr("settings.wallpaper.tabs.look-feel")
      tabIndex: 1
      checked: subTabBar.currentIndex === 1
    }
    NTabButton {
      text: I18n.tr("settings.wallpaper.tabs.automation")
      tabIndex: 2
      checked: subTabBar.currentIndex === 2
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.marginL
  }

  NTabView {
    id: tabView
    currentIndex: subTabBar.currentIndex

    SettingsSubTab {
      screen: root.screen
      onOpenMainFolderPicker: root.openMainFolderPicker()
      onOpenMonitorFolderPicker: monitorName => root.openMonitorFolderPicker(monitorName)
    }
    LookAndFeelSubTab {
      screen: root.screen
    }
    AutomationSubTab {}
  }

  NFilePicker {
    id: mainFolderPicker
    selectionMode: "folders"
    title: I18n.tr("settings.wallpaper.settings.select-folder")
    initialPath: Settings.data.wallpaper.directory || Quickshell.env("HOME") + "/Pictures"
    onAccepted: paths => {
                  if (paths.length > 0) {
                    Settings.data.wallpaper.directory = paths[0];
                  }
                }
  }

  NFilePicker {
    id: monitorFolderPicker
    selectionMode: "folders"
    title: I18n.tr("settings.wallpaper.settings.select-monitor-folder")
    initialPath: WallpaperService.getMonitorDirectory(specificFolderMonitorName) || Quickshell.env("HOME") + "/Pictures"
    onAccepted: paths => {
                  if (paths.length > 0) {
                    WallpaperService.setMonitorDirectory(specificFolderMonitorName, paths[0]);
                  }
                }
  }
}
