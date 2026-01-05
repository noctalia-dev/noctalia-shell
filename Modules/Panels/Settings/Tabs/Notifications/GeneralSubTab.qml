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

  NHeader {
    label: I18n.tr("settings.notifications.settings.section.label")
    description: I18n.tr("settings.notifications.settings.section.description")
  }

  NToggle {
    label: I18n.tr("settings.notifications.settings.enabled.label")
    description: I18n.tr("settings.notifications.settings.enabled.description")
    checked: Settings.data.notifications.enabled !== false
    onToggled: checked => Settings.data.notifications.enabled = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("notifications.enabled")
  }

  NToggle {
    label: I18n.tr("settings.notifications.settings.do-not-disturb.label")
    description: I18n.tr("settings.notifications.settings.do-not-disturb.description")
    checked: NotificationService.doNotDisturb
    onToggled: checked => NotificationService.doNotDisturb = checked
  }

  NComboBox {
    label: I18n.tr("settings.notifications.settings.location.label")
    description: I18n.tr("settings.notifications.settings.location.description")
    model: [
      {
        "key": "top",
        "name": I18n.tr("options.launcher.position.top_center")
      },
      {
        "key": "top_left",
        "name": I18n.tr("options.launcher.position.top_left")
      },
      {
        "key": "top_right",
        "name": I18n.tr("options.launcher.position.top_right")
      },
      {
        "key": "bottom",
        "name": I18n.tr("options.launcher.position.bottom_center")
      },
      {
        "key": "bottom_left",
        "name": I18n.tr("options.launcher.position.bottom_left")
      },
      {
        "key": "bottom_right",
        "name": I18n.tr("options.launcher.position.bottom_right")
      }
    ]
    currentKey: Settings.data.notifications.location || "top_right"
    onSelected: key => Settings.data.notifications.location = key
    isSettings: true
    defaultValue: Settings.getDefaultValue("notifications.location")
  }

  NToggle {
    label: I18n.tr("settings.notifications.settings.always-on-top.label")
    description: I18n.tr("settings.notifications.settings.always-on-top.description")
    checked: Settings.data.notifications.overlayLayer
    onToggled: checked => Settings.data.notifications.overlayLayer = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("notifications.overlayLayer")
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("settings.notifications.settings.background-opacity.label")
    description: I18n.tr("settings.notifications.settings.background-opacity.description")
    from: 0
    to: 1
    stepSize: 0.01
    value: Settings.data.notifications.backgroundOpacity
    onMoved: value => Settings.data.notifications.backgroundOpacity = value
    text: Math.round(Settings.data.notifications.backgroundOpacity * 100) + "%"
    isSettings: true
    defaultValue: Settings.getDefaultValue("notifications.backgroundOpacity")
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  NHeader {
    label: I18n.tr("settings.notifications.monitors.section.label")
    description: I18n.tr("settings.notifications.monitors.section.description")
  }

  Repeater {
    model: Quickshell.screens || []
    delegate: NCheckbox {
      Layout.fillWidth: true
      label: modelData.name || I18n.tr("system.unknown")
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
