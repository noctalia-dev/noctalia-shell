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

  NHeader {
    label: I18n.tr("settings.dock.appearance.section.label")
    description: I18n.tr("settings.dock.appearance.section.description")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.dock.enabled.label")
    description: I18n.tr("settings.dock.enabled.description")
    checked: Settings.data.dock.enabled
    onToggled: checked => Settings.data.dock.enabled = checked
  }

  NComboBox {
    visible: Settings.data.dock.enabled
    Layout.fillWidth: true
    label: I18n.tr("settings.dock.appearance.display.label")
    description: I18n.tr("settings.dock.appearance.display.description")
    model: [{
        "key": "always_visible",
        "name": I18n.tr("settings.dock.appearance.display.always-visible")
      }, {
        "key": "auto_hide",
        "name": I18n.tr("settings.dock.appearance.display.auto-hide")
      }, {
        "key": "exclusive",
        "name": I18n.tr("settings.dock.appearance.display.exclusive")
      }]
    currentKey: Settings.data.dock.displayMode
    onSelected: key => {
                  Settings.data.dock.displayMode = key
                }
  }

  ColumnLayout {
    visible: Settings.data.dock.enabled
    spacing: Style.marginXXS
    Layout.fillWidth: true
    NLabel {
      label: I18n.tr("settings.dock.appearance.background-opacity.label")
      description: I18n.tr("settings.dock.appearance.background-opacity.description")
    }
    NValueSlider {
      Layout.fillWidth: true
      from: 0
      to: 1
      stepSize: 0.01
      value: Settings.data.dock.backgroundOpacity
      onMoved: value => Settings.data.dock.backgroundOpacity = value
      text: Math.floor(Settings.data.dock.backgroundOpacity * 100) + "%"
    }
  }

  ColumnLayout {
    visible: Settings.data.dock.enabled
    spacing: Style.marginXXS
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("settings.dock.appearance.floating-distance.label")
      description: I18n.tr("settings.dock.appearance.floating-distance.description")
    }

    NValueSlider {
      Layout.fillWidth: true
      from: 0
      to: 4
      stepSize: 0.01
      value: Settings.data.dock.floatingRatio
      onMoved: value => Settings.data.dock.floatingRatio = value
      text: Math.floor(Settings.data.dock.floatingRatio * 100) + "%"
    }
  }

  ColumnLayout {
    visible: Settings.data.dock.enabled
    spacing: Style.marginXXS
    Layout.fillWidth: true
    NLabel {
      label: I18n.tr("settings.dock.appearance.icon-size.label")
      description: I18n.tr("settings.dock.appearance.icon-size.description")
    }
    NValueSlider {
      Layout.fillWidth: true
      from: 0
      to: 2
      stepSize: 0.01
      value: Settings.data.dock.size
      onMoved: value => Settings.data.dock.size = value
      text: Math.floor(Settings.data.dock.size * 100) + "%"
    }
  }

  NToggle {
    visible: Settings.data.dock.enabled
    label: I18n.tr("settings.dock.monitors.only-same-output.label")
    description: I18n.tr("settings.dock.monitors.only-same-output.description")
    checked: Settings.data.dock.onlySameOutput
    onToggled: checked => Settings.data.dock.onlySameOutput = checked
  }

  NToggle {
    visible: Settings.data.dock.enabled
    Layout.fillWidth: true
    label: I18n.tr("settings.dock.appearance.colorize-icons.label")
    description: I18n.tr("settings.dock.appearance.colorize-icons.description")
    checked: Settings.data.dock.colorizeIcons
    onToggled: checked => Settings.data.dock.colorizeIcons = checked
  }

  NDivider {
    visible: Settings.data.dock.enabled
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Monitor Configuration
  ColumnLayout {
    visible: Settings.data.dock.enabled
    spacing: Style.marginM
    Layout.fillWidth: true

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
          const compositorScale = CompositorService.getDisplayScale(modelData.name)
          I18n.tr("system.monitor-description", {
                    "model": modelData.model,
                    "width": modelData.width * compositorScale,
                    "height": modelData.height * compositorScale,
                    "scale": compositorScale
                  })
        }
        checked: (Settings.data.dock.monitors || []).indexOf(modelData.name) !== -1
        onToggled: checked => {
                     if (checked) {
                       Settings.data.dock.monitors = addMonitor(Settings.data.dock.monitors, modelData.name)
                     } else {
                       Settings.data.dock.monitors = removeMonitor(Settings.data.dock.monitors, modelData.name)
                     }
                   }
      }
    }
  }

  NDivider {
    visible: Settings.data.dock.enabled
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
