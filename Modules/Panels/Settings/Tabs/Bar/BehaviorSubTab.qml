import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  readonly property string effectiveWheelAction: Settings.data.bar.mouseWheelAction || "none"

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.bar.behavior-workspace-scroll-label")
    description: I18n.tr("panels.bar.behavior-workspace-scroll-description")
    model: {
      var items = [
        {
          "key": "none",
          "name": "Nothing"
        },
        {
          "key": "workspace",
          "name": "Workspace"
        }
      ];
      if (CompositorService.isNiri) {
        items.push({
                    "key": "content",
                    "name": "Content"
                  });
      }
      return items;
    }
    currentKey: root.effectiveWheelAction
    defaultValue: Settings.getDefaultValue("bar.mouseWheelAction")
    onSelected: key => Settings.data.bar.mouseWheelAction = key
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.general.reverse-scrolling-label")
    description: I18n.tr("panels.general.reverse-scrolling-description")
    checked: Settings.data.bar.reverseScroll
    defaultValue: Settings.getDefaultValue("bar.reverseScroll")
    onToggled: checked => Settings.data.bar.reverseScroll = checked
    visible: Settings.data.bar.mouseWheelAction !== "none"
  }
}
