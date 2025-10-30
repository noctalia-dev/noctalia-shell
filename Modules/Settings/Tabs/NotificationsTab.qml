import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  // Helper functions to update arrays immutably
  function addMonitor(list, name) {
    const arr = (list || []).slice()
    if (!arr.includes(name))
      arr.push(name)
    return arr
  }
  function removeMonitor(list, name) {
    return (list || []).filter(function (n) {
      return n !== name
    })
  }

  // General Notification Settings
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.notifications.settings.section.label")
      description: I18n.tr("settings.notifications.settings.section.description")
    }

    NToggle {
      label: I18n.tr("settings.notifications.settings.do-not-disturb.label")
      description: I18n.tr("settings.notifications.settings.do-not-disturb.description")
      checked: Settings.data.notifications.doNotDisturb
      onToggled: checked => Settings.data.notifications.doNotDisturb = checked
    }

    NComboBox {
      label: I18n.tr("settings.notifications.settings.location.label")
      description: I18n.tr("settings.notifications.settings.location.description")
      model: [{
          "key": "top",
          "name": I18n.tr("options.launcher.position.top_center")
        }, {
          "key": "top_left",
          "name": I18n.tr("options.launcher.position.top_left")
        }, {
          "key": "top_right",
          "name": I18n.tr("options.launcher.position.top_right")
        }, {
          "key": "bottom",
          "name": I18n.tr("options.launcher.position.bottom_center")
        }, {
          "key": "bottom_left",
          "name": I18n.tr("options.launcher.position.bottom_left")
        }, {
          "key": "bottom_right",
          "name": I18n.tr("options.launcher.position.bottom_right")
        }]
      currentKey: Settings.data.notifications.location || "top_right"
      onSelected: key => Settings.data.notifications.location = key
    }

    NToggle {
      label: I18n.tr("settings.notifications.settings.always-on-top.label")
      description: I18n.tr("settings.notifications.settings.always-on-top.description")
      checked: Settings.data.notifications.overlayLayer
      onToggled: checked => Settings.data.notifications.overlayLayer = checked
    }

    // Background Opacity
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("settings.notifications.settings.background-opacity.label")
        description: I18n.tr("settings.notifications.settings.background-opacity.description")
      }

      NValueSlider {
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 1
        value: Settings.data.notifications.backgroundOpacity * 100
        onMoved: value => Settings.data.notifications.backgroundOpacity = value / 100
        text: Math.round(Settings.data.notifications.backgroundOpacity * 100) + "%"
      }
    }

    // OSD settings moved to the dedicated OSD tab
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }

  // Duration
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.notifications.duration.section.label")
      description: I18n.tr("settings.notifications.duration.section.description")
    }

    // Respect Expire Timeout (eg. --expire-time flag in notify-send)
    NToggle {
      label: I18n.tr("settings.notifications.duration.respect-expire.label")
      description: I18n.tr("settings.notifications.duration.respect-expire.description")
      checked: Settings.data.notifications.respectExpireTimeout
      onToggled: checked => Settings.data.notifications.respectExpireTimeout = checked
    }

    // Low Urgency Duration
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("settings.notifications.duration.low-urgency.label")
        description: I18n.tr("settings.notifications.duration.low-urgency.description")
      }

      NValueSlider {
        Layout.fillWidth: true
        from: 1
        to: 30
        stepSize: 1
        value: Settings.data.notifications.lowUrgencyDuration
        onMoved: value => Settings.data.notifications.lowUrgencyDuration = value
        text: Settings.data.notifications.lowUrgencyDuration + "s"
      }
    }

    // Normal Urgency Duration
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("settings.notifications.duration.normal-urgency.label")
        description: I18n.tr("settings.notifications.duration.normal-urgency.description")
      }

      NValueSlider {
        Layout.fillWidth: true
        from: 1
        to: 30
        stepSize: 1
        value: Settings.data.notifications.normalUrgencyDuration
        onMoved: value => Settings.data.notifications.normalUrgencyDuration = value
        text: Settings.data.notifications.normalUrgencyDuration + "s"
      }
    }

    // Critical Urgency Duration
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("settings.notifications.duration.critical-urgency.label")
        description: I18n.tr("settings.notifications.duration.critical-urgency.description")
      }

      NValueSlider {
        Layout.fillWidth: true
        from: 1
        to: 30
        stepSize: 1
        value: Settings.data.notifications.criticalUrgencyDuration
        onMoved: value => Settings.data.notifications.criticalUrgencyDuration = value
        text: Settings.data.notifications.criticalUrgencyDuration + "s"
      }
    }

    NDivider {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginXL
      Layout.bottomMargin: Style.marginXL
    }

    // Monitor Configuration
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
          const compositorScale = CompositorService.getDisplayScale(modelData.name)
          I18n.tr("system.monitor-description", {
                    "model": modelData.model,
                    "width": modelData.width * compositorScale,
                    "height": modelData.height * compositorScale,
                    "scale": compositorScale
                  })
        }
        checked: (Settings.data.notifications.monitors || []).indexOf(modelData.name) !== -1
        onToggled: checked => {
                     if (checked) {
                       Settings.data.notifications.monitors = addMonitor(Settings.data.notifications.monitors, modelData.name)
                     } else {
                       Settings.data.notifications.monitors = removeMonitor(Settings.data.notifications.monitors, modelData.name)
                     }
                   }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }
}
