import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true
  enabled: Settings.data.notifications.enabled

  function _saveToService() {
    NotificationRulesService.save();
  }

  function _removeRule(index) {
    var arr = (NotificationRulesService.rules || []).slice();
    arr.splice(index, 1);
    NotificationRulesService.rules = arr;
    _saveToService();
  }

  NotificationRuleEditPopup {
    id: editPopup
    parent: Overlay.overlay
  }

  function openEdit(index, patternVal, actionVal) {
    editPopup.editIndex = index;
    editPopup.patternValue = patternVal || "";
    editPopup.actionValue = actionVal || "block";

    try {
      editPopup.saved.disconnect(editPopup._savedSlot);
    } catch (e) {}

    editPopup._savedSlot = function (pattern, action) {
      const trimmed = (pattern || "").trim();
      if (trimmed === "")
        return;
      var arr = (NotificationRulesService.rules || []).slice();
      var rule = {
        "pattern": trimmed,
        "action": action
      };
      if (index >= 0 && index < arr.length) {
        arr[index] = rule;
      } else {
        arr.push(rule);
      }
      NotificationRulesService.rules = arr;
      _saveToService();
    };

    editPopup.saved.connect(editPopup._savedSlot);
    editPopup.open();
  }

  NLabel {
    label: I18n.tr("panels.notifications.rules-label")
    description: I18n.tr("panels.notifications.rules-description")
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
    Layout.bottomMargin: Style.marginS
  }

  Repeater {
    model: NotificationRulesService.rules || []

    delegate: RowLayout {
      id: entryDelegate
      required property int index
      required property var modelData

      property string pattern: modelData.pattern || ""
      property string action: modelData.action || "block"
      property bool isRegex: pattern.length >= 3 && pattern.startsWith("/") && pattern.endsWith("/")

      spacing: Style.marginM
      Layout.fillWidth: true

      NLabel {
        Layout.fillWidth: true
        label: (entryDelegate.isRegex ? "regex: " : "") + entryDelegate.pattern
        description: entryDelegate.action === "block" ? I18n.tr("panels.notifications.rules-action-block") : (entryDelegate.action === "mute" ? I18n.tr("panels.notifications.rules-action-mute") : I18n.tr("panels.notifications.rules-action-hide"))
        labelColor: entryDelegate.pattern ? Color.mPrimary : Color.mOnSurface
      }

      NIconButton {
        icon: "settings"
        tooltipText: I18n.tr("common.edit")
        onClicked: root.openEdit(entryDelegate.index, entryDelegate.pattern, entryDelegate.action)
      }

      NIconButton {
        icon: "trash"
        tooltipText: I18n.tr("panels.notifications.rules-delete")
        onClicked: root._removeRule(entryDelegate.index)
      }
    }
  }

  NButton {
    text: I18n.tr("panels.notifications.rules-add")
    icon: "add"
    enabled: Settings.data.notifications.enabled
    onClicked: root.openEdit(-1, "", "block")
  }
}
