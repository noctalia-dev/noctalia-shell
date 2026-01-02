import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.OSD
import qs.Services.Compositor
import qs.Widgets

ColumnLayout {
  id: root

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
  function addType(list, type) {
    const arr = (list || []).slice();
    if (!arr.includes(type))
      arr.push(type);
    return arr;
  }
  function removeType(list, type) {
    return (list || []).filter(function (t) {
      return t !== type;
    });
  }

  // Display
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NComboBox {
      label: I18n.tr("settings.osd.location.label")
      description: I18n.tr("settings.osd.location.description")
      model: [
        {
          "key": "top",
          "name": I18n.tr("options.osd.position.top_center")
        },
        {
          "key": "top_left",
          "name": I18n.tr("options.osd.position.top_left")
        },
        {
          "key": "top_right",
          "name": I18n.tr("options.osd.position.top_right")
        },
        {
          "key": "bottom",
          "name": I18n.tr("options.osd.position.bottom_center")
        },
        {
          "key": "bottom_left",
          "name": I18n.tr("options.osd.position.bottom_left")
        },
        {
          "key": "bottom_right",
          "name": I18n.tr("options.osd.position.bottom_right")
        },
        {
          "key": "left",
          "name": I18n.tr("options.osd.position.center_left")
        },
        {
          "key": "right",
          "name": I18n.tr("options.osd.position.center_right")
        }
      ]
      currentKey: Settings.data.osd.location || "top_right"
      isSettings: true
      defaultValue: Settings.getDefaultValue("osd.location")
      onSelected: key => Settings.data.osd.location = key
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // General
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.osd.section.general.label")
      description: I18n.tr("settings.osd.section.general.description")
    }

    NToggle {
      label: I18n.tr("settings.osd.enabled.label")
      description: I18n.tr("settings.osd.enabled.description")
      checked: Settings.data.osd.enabled
      isSettings: true
      defaultValue: Settings.getDefaultValue("osd.enabled")
      onToggled: checked => Settings.data.osd.enabled = checked
    }

    NToggle {
      label: I18n.tr("settings.osd.always-on-top.label")
      description: I18n.tr("settings.osd.always-on-top.description")
      checked: Settings.data.osd.overlayLayer
      isSettings: true
      defaultValue: Settings.getDefaultValue("osd.overlayLayer")
      onToggled: checked => Settings.data.osd.overlayLayer = checked
    }

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("settings.osd.background-opacity.label", "Background opacity")
      description: I18n.tr("settings.osd.background-opacity.description", "Controls the transparency of the OSD background.")
      from: 0
      to: 100
      stepSize: 1
      value: Settings.data.osd.backgroundOpacity * 100
      isSettings: true
      defaultValue: (Settings.getDefaultValue("osd.backgroundOpacity") || 1) * 100
      onMoved: value => Settings.data.osd.backgroundOpacity = value / 100
      text: Math.round(Settings.data.osd.backgroundOpacity * 100) + "%"
    }

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("settings.osd.duration.auto-hide.label")
      description: I18n.tr("settings.osd.duration.auto-hide.description")
      from: 500
      to: 5000
      stepSize: 100
      value: Settings.data.osd.autoHideMs
      isSettings: true
      defaultValue: Settings.getDefaultValue("osd.autoHideMs")
      onMoved: value => Settings.data.osd.autoHideMs = value
      text: Math.round(Settings.data.osd.autoHideMs / 1000 * 10) / 10 + "s"
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // OSD Types Configuration
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.osd.types.section.label")
      description: I18n.tr("settings.osd.types.section.description")
    }

    Repeater {
      model: [
        {
          type: OSD.Type.Volume,
          key: "volume"
        },
        {
          type: OSD.Type.InputVolume,
          key: "input-volume"
        },
        {
          type: OSD.Type.Brightness,
          key: "brightness"
        },
        {
          type: OSD.Type.LockKey,
          key: "lockkey"
        },
        {
          type: OSD.Type.CustomText,
          key: "custom-text"
        }
      ]
      delegate: NCheckbox {
        required property var modelData
        Layout.fillWidth: true
        label: I18n.tr("settings.osd.types." + modelData.key + ".label")
        description: I18n.tr("settings.osd.types." + modelData.key + ".description")
        checked: (Settings.data.osd.enabledTypes || []).includes(modelData.type)
        onToggled: checked => {
                     if (checked) {
                       Settings.data.osd.enabledTypes = addType(Settings.data.osd.enabledTypes, modelData.type);
                     } else {
                       Settings.data.osd.enabledTypes = removeType(Settings.data.osd.enabledTypes, modelData.type);
                     }
                   }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Monitor Configuration
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.osd.monitors.section.label")
      description: I18n.tr("settings.osd.monitors.section.description")
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
        checked: (Settings.data.osd.monitors || []).indexOf(modelData.name) !== -1
        onToggled: checked => {
                     if (checked) {
                       Settings.data.osd.monitors = addMonitor(Settings.data.osd.monitors, modelData.name);
                     } else {
                       Settings.data.osd.monitors = removeMonitor(Settings.data.osd.monitors, modelData.name);
                     }
                   }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
