import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var addMonitor
  property var removeMonitor

  NHeader {
    label: I18n.tr("settings.dock.monitors.section.label")
    description: I18n.tr("settings.dock.monitors.section.description")
  }

  Repeater {
    model: Quickshell.screens || []
    delegate: NCheckbox {
      Layout.fillWidth: true
      label: modelData.name || "Unknown"
      description: {
        const compositorScale = CompositorService.getDisplayScale(modelData.name);
        I18n.tr("system.monitor-description", {
                  "model": modelData.model,
                  "width": modelData.width * compositorScale,
                  "height": modelData.height * compositorScale,
                  "scale": compositorScale
                });
      }
      checked: (Settings.data.dock.monitors || []).indexOf(modelData.name) !== -1
      onToggled: checked => {
                   if (checked) {
                     Settings.data.dock.monitors = addMonitor(Settings.data.dock.monitors, modelData.name);
                   } else {
                     Settings.data.dock.monitors = removeMonitor(Settings.data.dock.monitors, modelData.name);
                   }
                 }
    }
  }
}
