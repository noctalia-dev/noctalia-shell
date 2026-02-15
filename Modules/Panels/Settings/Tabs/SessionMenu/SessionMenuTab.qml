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

  property var _activeDialog: null
  property list<var> entriesModel: []
  property list<var> entriesDefault: [
    {
      "id": "lock",
      "text": I18n.tr("common.lock"),
      "enabled": true,
      "required": false
    },
    {
      "id": "suspend",
      "text": I18n.tr("common.suspend"),
      "enabled": true,
      "required": false
    },
    {
      "id": "hibernate",
      "text": I18n.tr("common.hibernate"),
      "enabled": true,
      "required": false
    },
    {
      "id": "reboot",
      "text": I18n.tr("common.reboot"),
      "enabled": true,
      "required": false
    },
    {
      "id": "rebootToUefi",
      "text": I18n.tr("common.reboot-to-uefi"),
      "enabled": true,
      "required": false
    },
    {
      "id": "logout",
      "text": I18n.tr("common.logout"),
      "enabled": true,
      "required": false
    },
    {
      "id": "shutdown",
      "text": I18n.tr("common.shutdown"),
      "enabled": true,
      "required": false
    }
  ]

  function saveEntries() {
    var toSave = [];
    for (var i = 0; i < entriesModel.length; i++) {
      toSave.push({
                    "action": entriesModel[i].id,
                    "enabled": entriesModel[i].enabled,
                    "countdownEnabled": entriesModel[i].countdownEnabled !== undefined ? entriesModel[i].countdownEnabled : true,
                    "command": entriesModel[i].command || "",
                    "keybind": entriesModel[i].keybind || ""
                  });
    }
    Settings.data.sessionMenu.powerOptions = toSave;
  }

  function updateEntry(idx, properties) {
    var newModel = entriesModel.slice();
    newModel[idx] = Object.assign({}, newModel[idx], properties);
    entriesModel = newModel;
    saveEntries();
  }

  function reorderEntries(fromIndex, toIndex) {
    var newModel = entriesModel.slice();
    var item = newModel.splice(fromIndex, 1)[0];
    newModel.splice(toIndex, 0, item);
    entriesModel = newModel;
    saveEntries();
  }

  Component.onDestruction: {
    if (_activeDialog && _activeDialog.close) {
      var dialog = _activeDialog;
      _activeDialog = null;
      dialog.close();
      dialog.destroy();
    }
  }

  function openEntrySettingsDialog(index) {
    if (index < 0 || index >= entriesModel.length) {
      return;
    }

    var entry = entriesModel[index];
    var component = Qt.createComponent(Quickshell.shellDir + "/Modules/Panels/Settings/Tabs/SessionMenu/SessionMenuEntrySettingsDialog.qml");

    function instantiateAndOpen() {
      if (root._activeDialog) {
        root._activeDialog.close();
        root._activeDialog.destroy();
        root._activeDialog = null;
      }

      var dialog = component.createObject(Overlay.overlay, {
                                            "entryIndex": index,
                                            "entryData": entry,
                                            "entryId": entry.id,
                                            "entryText": entry.text
                                          });

      if (dialog) {
        root._activeDialog = dialog;
        dialog.updateEntryProperties.connect((idx, properties) => {
                                               root.updateEntry(idx, properties);
                                             });
        dialog.closed.connect(() => {
                                if (root._activeDialog === dialog) {
                                  root._activeDialog = null;
                                  dialog.destroy();
                                }
                              });
        dialog.open();
      } else {
        Logger.e("SessionMenuTab", "Failed to create entry settings dialog");
      }
    }

    if (component.status === Component.Ready) {
      instantiateAndOpen();
    } else if (component.status === Component.Error) {
      Logger.e("SessionMenuTab", "Error loading entry settings dialog:", component.errorString());
    } else {
      component.statusChanged.connect(function () {
        if (component.status === Component.Ready) {
          instantiateAndOpen();
        } else if (component.status === Component.Error) {
          Logger.e("SessionMenuTab", "Error loading entry settings dialog:", component.errorString());
        }
      });
    }
  }

  Component.onCompleted: {
    entriesModel = [];

    // Add the entries available in settings
    for (var i = 0; i < Settings.data.sessionMenu.powerOptions.length; i++) {
      const settingEntry = Settings.data.sessionMenu.powerOptions[i];

      for (var j = 0; j < entriesDefault.length; j++) {
        if (settingEntry.action === entriesDefault[j].id) {
          var entry = entriesDefault[j];
          entry.enabled = settingEntry.enabled;
          // Default countdownEnabled to true for backward compatibility
          entry.countdownEnabled = settingEntry.countdownEnabled !== undefined ? settingEntry.countdownEnabled : true;
          // Load custom command if defined
          entry.command = settingEntry.command || "";
          entry.keybind = settingEntry.keybind || "";
          entriesModel.push(entry);
        }
      }
    }

    // Add any missing entries from default
    for (var i = 0; i < entriesDefault.length; i++) {
      var found = false;
      for (var j = 0; j < entriesModel.length; j++) {
        if (entriesModel[j].id === entriesDefault[i].id) {
          found = true;
          break;
        }
      }

      if (!found) {
        var entry = entriesDefault[i];
        // Default countdownEnabled to true for new entries
        entry.countdownEnabled = true;
        // Default command to empty string for new entries
        entry.command = "";
        entry.keybind = "";
        entriesModel.push(entry);
      }
    }

    saveEntries();
  }

  NTabBar {
    id: subTabBar
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginM
    distributeEvenly: true
    currentIndex: tabView.currentIndex

    NTabButton {
      text: I18n.tr("common.general")
      tabIndex: 0
      checked: subTabBar.currentIndex === 0
    }
    NTabButton {
      text: I18n.tr("common.actions")
      tabIndex: 1
      checked: subTabBar.currentIndex === 1
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.marginL
  }

  NTabView {
    id: tabView
    currentIndex: subTabBar.currentIndex

    GeneralSubTab {}
    ActionsSubTab {
      entriesModel: root.entriesModel
      updateEntry: root.updateEntry
      reorderEntries: root.reorderEntries
      openEntrySettingsDialog: root.openEntrySettingsDialog
    }
  }
}
