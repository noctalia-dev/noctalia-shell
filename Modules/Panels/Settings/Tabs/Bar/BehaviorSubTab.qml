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

  readonly property string effectiveWheelAction: {
    if (Settings.data.bar.mouseWheelAction !== undefined && Settings.data.bar.mouseWheelAction !== "")
      return Settings.data.bar.mouseWheelAction;
    return Settings.data.bar.enableWorkspaceScroll ? "workspace" : "none";
  }

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
    onSelected: key => {
                  Settings.data.bar.mouseWheelAction = key;
                  Settings.data.bar.enableWorkspaceScroll = (key === "workspace");
                }
  }
}
