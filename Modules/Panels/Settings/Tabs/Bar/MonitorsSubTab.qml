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
    label: I18n.tr("settings.bar.monitors.section.label")
    description: I18n.tr("settings.bar.monitors.section.description")
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
      checked: (Settings.data.bar.monitors || []).indexOf(modelData.name) !== -1
      onToggled: checked => {
                   if (checked) {
                     Settings.data.bar.monitors = root.addMonitor(Settings.data.bar.monitors, modelData.name);
                   } else {
                     Settings.data.bar.monitors = root.removeMonitor(Settings.data.bar.monitors, modelData.name);
                   }
                 }
    }
  }
}
