import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: 0

  // Helper functions to update arrays immutably
  function addMonitor(list, name) {
    const arr = (list || []).slice();
    if (!arr.includes(name))
      arr.push(name);
    return arr;
  }
  function removeMonitor(list, name) {
    return (list || []).filter(function (n) {
      return n !== name;
    });
  }

  // File pickers for sound sub-tab
  function openUnifiedSoundPicker() {
    unifiedSoundFilePicker.open();
  }
  function openLowSoundPicker() {
    lowSoundFilePicker.open();
  }
  function openNormalSoundPicker() {
    normalSoundFilePicker.open();
  }
  function openCriticalSoundPicker() {
    criticalSoundFilePicker.open();
  }

  NTabBar {
    id: subTabBar
    Layout.fillWidth: true
    distributeEvenly: true
    currentIndex: tabView.currentIndex

    NTabButton {
      text: I18n.tr("settings.notifications.tabs.general")
      tabIndex: 0
      checked: subTabBar.currentIndex === 0
    }
    NTabButton {
      text: I18n.tr("settings.notifications.tabs.sounds")
      tabIndex: 1
      checked: subTabBar.currentIndex === 1
    }
    NTabButton {
      text: I18n.tr("settings.notifications.tabs.history")
      tabIndex: 2
      checked: subTabBar.currentIndex === 2
    }
    NTabButton {
      text: I18n.tr("settings.notifications.tabs.toast")
      tabIndex: 3
      checked: subTabBar.currentIndex === 3
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.marginL
  }

  NTabView {
    id: tabView
    currentIndex: subTabBar.currentIndex

    GeneralSubTab {
      addMonitor: root.addMonitor
      removeMonitor: root.removeMonitor
    }
    SoundsSubTab {
      onOpenUnifiedPicker: root.openUnifiedSoundPicker()
      onOpenLowPicker: root.openLowSoundPicker()
      onOpenNormalPicker: root.openNormalSoundPicker()
      onOpenCriticalPicker: root.openCriticalSoundPicker()
    }
    HistorySubTab {}
    ToastSubTab {}
  }

  // File Pickers for Sound Files
  NFilePicker {
    id: unifiedSoundFilePicker
    title: I18n.tr("settings.notifications.sounds.files.unified.select-title")
    selectionMode: "files"
    initialPath: Quickshell.env("HOME")
    nameFilters: ["*.wav", "*.mp3", "*.ogg", "*.flac", "*.m4a", "*.aac"]
    onAccepted: paths => {
                  if (paths.length > 0) {
                    const soundPath = paths[0];
                    Settings.data.notifications.sounds.normalSoundFile = soundPath;
                    Settings.data.notifications.sounds.lowSoundFile = soundPath;
                    Settings.data.notifications.sounds.criticalSoundFile = soundPath;
                  }
                }
  }

  NFilePicker {
    id: lowSoundFilePicker
    title: I18n.tr("settings.notifications.sounds.files.low.select-title")
    selectionMode: "files"
    initialPath: Quickshell.env("HOME")
    nameFilters: ["*.wav", "*.mp3", "*.ogg", "*.flac", "*.m4a", "*.aac"]
    onAccepted: paths => {
                  if (paths.length > 0) {
                    Settings.data.notifications.sounds.lowSoundFile = paths[0];
                  }
                }
  }

  NFilePicker {
    id: normalSoundFilePicker
    title: I18n.tr("settings.notifications.sounds.files.normal.select-title")
    selectionMode: "files"
    initialPath: Quickshell.env("HOME")
    nameFilters: ["*.wav", "*.mp3", "*.ogg", "*.flac", "*.m4a", "*.aac"]
    onAccepted: paths => {
                  if (paths.length > 0) {
                    Settings.data.notifications.sounds.normalSoundFile = paths[0];
                  }
                }
  }

  NFilePicker {
    id: criticalSoundFilePicker
    title: I18n.tr("settings.notifications.sounds.files.critical.select-title")
    selectionMode: "files"
    initialPath: Quickshell.env("HOME")
    nameFilters: ["*.wav", "*.mp3", "*.ogg", "*.flac", "*.m4a", "*.aac"]
    onAccepted: paths => {
                  if (paths.length > 0) {
                    Settings.data.notifications.sounds.criticalSoundFile = paths[0];
                  }
                }
  }
}
