import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var addMonitor
  property var removeMonitor

  NToggle {
    label: I18n.tr("panels.notifications.settings-enabled-label")
    description: I18n.tr("panels.notifications.settings-enabled-description")
    checked: Settings.data.notifications.enabled !== false
    onToggled: checked => Settings.data.notifications.enabled = checked
    defaultValue: Settings.getDefaultValue("notifications.enabled")
  }

  NComboBox {
    label: I18n.tr("panels.notifications.settings-density-label")
    description: I18n.tr("panels.notifications.settings-density-description")
    model: [
      {
        "key": "default",
        "name": I18n.tr("options.notification-density.default")
      },
      {
        "key": "compact",
        "name": I18n.tr("options.notification-density.compact")
      }
    ]
    currentKey: Settings.data.notifications.density || "default"
    onSelected: key => Settings.data.notifications.density = key
    defaultValue: Settings.getDefaultValue("notifications.density")
  }

  NToggle {
    label: I18n.tr("tooltips.do-not-disturb-enabled")
    description: I18n.tr("panels.notifications.settings-do-not-disturb-description")
    checked: NotificationService.doNotDisturb
    onToggled: checked => NotificationService.doNotDisturb = checked
  }

  NComboBox {
    label: I18n.tr("common.position")
    description: I18n.tr("panels.notifications.settings-location-description")
    model: [
      {
        "key": "top",
        "name": I18n.tr("positions.top-center")
      },
      {
        "key": "top_left",
        "name": I18n.tr("positions.top-left")
      },
      {
        "key": "top_right",
        "name": I18n.tr("positions.top-right")
      },
      {
        "key": "bottom",
        "name": I18n.tr("positions.bottom-center")
      },
      {
        "key": "bottom_left",
        "name": I18n.tr("positions.bottom-left")
      },
      {
        "key": "bottom_right",
        "name": I18n.tr("positions.bottom-right")
      }
    ]
    currentKey: Settings.data.notifications.location || "top_right"
    onSelected: key => Settings.data.notifications.location = key
    defaultValue: Settings.getDefaultValue("notifications.location")
  }

  NToggle {
    label: I18n.tr("panels.osd.always-on-top-label")
    description: I18n.tr("panels.notifications.settings-always-on-top-description")
    checked: Settings.data.notifications.overlayLayer
    onToggled: checked => Settings.data.notifications.overlayLayer = checked
    defaultValue: Settings.getDefaultValue("notifications.overlayLayer")
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("panels.osd.background-opacity-label")
    description: I18n.tr("panels.notifications.settings-background-opacity-description")
    from: 0
    to: 1
    stepSize: 0.01
    showReset: true
    value: Settings.data.notifications.backgroundOpacity
    onMoved: value => Settings.data.notifications.backgroundOpacity = value
    text: Math.round(Settings.data.notifications.backgroundOpacity * 100) + "%"
    defaultValue: Settings.getDefaultValue("notifications.backgroundOpacity")
  }

  NDivider {
    Layout.fillWidth: true
  }

  NText {
    text: I18n.tr("panels.notifications.monitors-desc")
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  Repeater {
    model: Quickshell.screens || []
    delegate: NCheckbox {
      Layout.fillWidth: true
      label: modelData.name || I18n.tr("common.unknown")
      description: {
        const compositorScale = CompositorService.getDisplayScale(modelData.name);
        I18n.tr("system.monitor-description", {
                  "model": modelData.model,
                  "width": modelData.width * compositorScale,
                  "height": modelData.height * compositorScale,
                  "scale": compositorScale
                });
      }
      checked: (Settings.data.notifications.monitors || []).indexOf(modelData.name) !== -1
      onToggled: checked => {
                   if (checked) {
                     Settings.data.notifications.monitors = root.addMonitor(Settings.data.notifications.monitors, modelData.name);
                   } else {
                     Settings.data.notifications.monitors = root.removeMonitor(Settings.data.notifications.monitors, modelData.name);
                   }
                 }
    }
  }
}
