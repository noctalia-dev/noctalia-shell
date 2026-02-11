import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

ColumnLayout {
  id: root
  enabled: true
  spacing: Style.marginL
  Layout.fillWidth: true

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

  NText {
    text: I18n.tr("panels.lock-screen.monitors-desc")
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
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
      checked: (Settings.data.general.lockScreenMonitors || []).indexOf(modelData.name) !== -1
      onToggled: checked => {
                   if (checked) {
                     Settings.data.general.lockScreenMonitors = root.addMonitor(Settings.data.general.lockScreenMonitors, modelData.name);
                   } else {
                     Settings.data.general.lockScreenMonitors = root.removeMonitor(Settings.data.general.lockScreenMonitors, modelData.name);
                   }
                 }
    }
  }
}
