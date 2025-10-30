import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginM

  // Header
  RowLayout {
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginL
    spacing: Style.marginM

    Rectangle {
      width: 40
      height: 40
      radius: Style.radiusL
      color: Color.mSurfaceVariant
      opacity: 0.6

      NIcon {
        icon: "device-desktop"
        pointSize: Style.fontSizeL
        color: Color.mPrimary
        anchors.centerIn: parent
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: I18n.tr("settings.dock.title") || "Dock"
        pointSize: Style.fontSizeXL
        font.weight: Style.fontWeightBold
        color: Color.mPrimary
      }

      NText {
        text: I18n.tr("settings.dock.monitors.section.description")
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
      }
    }
  }

  // Options
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginL

    NToggle {
      Layout.fillWidth: true
      label: I18n.tr("settings.dock.enabled.label")
      description: I18n.tr("settings.dock.enabled.description")
      checked: Settings.data.dock.enabled
      onToggled: checked => Settings.data.dock.enabled = checked
    }

    // Display behavior
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
      onSelected: key => Settings.data.dock.displayMode = key
    }

    // Background opacity
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

    // Floating distance
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

    // Icon size
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
      Layout.fillWidth: true
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

    NHeader {
      visible: Settings.data.dock.enabled
      label: I18n.tr("settings.dock.monitors.section.label")
      description: I18n.tr("settings.dock.monitors.section.description")
    }

    Repeater {
      visible: Settings.data.dock.enabled
      model: Quickshell.screens || []
      delegate: NCheckbox {
        Layout.fillWidth: true
        label: modelData.name || "Unknown"
        visible: Settings.data.dock.enabled
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
                       const arr = (Settings.data.dock.monitors || []).slice()
                       if (arr.indexOf(modelData.name) === -1)
                       arr.push(modelData.name)
                       Settings.data.dock.monitors = arr
                     } else {
                       Settings.data.dock.monitors = (Settings.data.dock.monitors || []).filter(function (n) {
                         return n !== modelData.name
                       })
                     }
                   }
      }
    }
  }
}
