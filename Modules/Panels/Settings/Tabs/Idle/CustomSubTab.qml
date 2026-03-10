import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Power
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true
  enabled: Settings.data.idle.enabled

  property bool _saving: false

  ListModel {
    id: entriesModel
  }

  function _loadToModel() {
    if (_saving)
      return;
    entriesModel.clear();
    var entries = [];
    try {
      entries = JSON.parse(Settings.data.idle.customCommands);
    } catch (e) {
      Logger.w("CustomSubTab", "Failed to parse customCommands:", e);
    }
    for (var i = 0; i < entries.length; i++) {
      entriesModel.append({
                            "name": String(entries[i].name || ""),
                            "timeout": parseInt(entries[i].timeout) || 60,
                            "command": String(entries[i].command || ""),
                            "resumeCommand": String(entries[i].resumeCommand || "")
                          });
    }
  }

  function _saveFromModel() {
    _saving = true;
    var arr = [];
    for (var i = 0; i < entriesModel.count; i++) {
      var item = entriesModel.get(i);
      arr.push({
                 "name": item.name,
                 "timeout": item.timeout,
                 "command": item.command,
                 "resumeCommand": item.resumeCommand
               });
    }
    Settings.data.idle.customCommands = JSON.stringify(arr);
    _saving = false;
  }

  function _removeEntry(index) {
    entriesModel.remove(index, 1);
    _saveFromModel();
  }

  Component.onCompleted: Qt.callLater(_loadToModel)

  Connections {
    target: Settings.data.idle
    function onCustomCommandsChanged() {
      root._loadToModel();
    }
  }

  // Shared Edit Popup
  IdleCommandEditPopup {
    id: editPopup
    parent: Overlay.overlay
  }

  function openEdit(index, nameVal, timeoutVal, cmdVal, resumeCmdVal) {
    editPopup.editIndex = index;
    editPopup.nameValue = nameVal;
    editPopup.timeoutValue = timeoutVal;
    editPopup.commandValue = cmdVal;
    editPopup.resumeCommandValue = resumeCmdVal;
    editPopup.showName = true;

    try {
      editPopup.saved.disconnect(editPopup._savedSlot);
    } catch (e) {}

    editPopup._savedSlot = function (timeout, cmd, resumeCmd, name) {
      if (index >= 0 && index < entriesModel.count) {
        entriesModel.setProperty(index, "name", name);
        entriesModel.setProperty(index, "timeout", timeout);
        entriesModel.setProperty(index, "command", cmd);
        entriesModel.setProperty(index, "resumeCommand", resumeCmd);
      } else {
        entriesModel.append({
                              "name": name,
                              "timeout": timeout,
                              "command": cmd,
                              "resumeCommand": resumeCmd
                            });
      }
      root._saveFromModel();
    };

    editPopup.saved.connect(editPopup._savedSlot);
    editPopup.open();
  }

  NLabel {
    label: I18n.tr("panels.idle.custom-label")
    description: I18n.tr("panels.idle.custom-description")
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
    Layout.bottomMargin: Style.marginS
  }

  Repeater {
    model: entriesModel

    delegate: RowLayout {
      id: entryDelegate
      required property int index
      required property string name
      required property int timeout
      required property string command
      required property string resumeCommand

      spacing: Style.marginM
      Layout.fillWidth: true

      NLabel {
        Layout.fillWidth: true
        label: entryDelegate.name || I18n.tr("panels.idle.custom-entry-unnamed")
        description: I18n.trp("common.second", entryDelegate.timeout)
        labelColor: (entryDelegate.command || entryDelegate.resumeCommand) ? Color.mPrimary : Color.mOnSurface
      }

      NIconButton {
        icon: "settings"
        tooltipText: I18n.tr("common.edit")
        onClicked: root.openEdit(entryDelegate.index, entryDelegate.name, entryDelegate.timeout, entryDelegate.command, entryDelegate.resumeCommand)
      }

      NIconButton {
        icon: "trash"
        tooltipText: I18n.tr("panels.idle.custom-entry-delete")
        onClicked: root._removeEntry(entryDelegate.index)
      }
    }
  }

  NButton {
    text: I18n.tr("panels.idle.custom-add")
    icon: "add"
    enabled: Settings.data.idle.enabled
    onClicked: {
      root.openEdit(-1, "", 60, "", "");
    }
  }
}
