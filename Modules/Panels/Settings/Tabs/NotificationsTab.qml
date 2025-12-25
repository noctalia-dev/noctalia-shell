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

  // General Notification Settings
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.notifications.settings.section.label")
      description: I18n.tr("settings.notifications.settings.section.description")
    }

    NToggle {
      label: I18n.tr("settings.notifications.settings.enabled.label")
      description: I18n.tr("settings.notifications.settings.enabled.description")
      checked: Settings.data.notifications.enabled !== false
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.enabled")
      onToggled: checked => Settings.data.notifications.enabled = checked
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
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.location") || "top_right"
      onSelected: key => Settings.data.notifications.location = key
    }

    NToggle {
      label: I18n.tr("settings.notifications.settings.always-on-top.label")
      description: I18n.tr("settings.notifications.settings.always-on-top.description")
      checked: Settings.data.notifications.overlayLayer
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.overlayLayer")
      onToggled: checked => Settings.data.notifications.overlayLayer = checked
    }

    // Background Opacity
    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("settings.notifications.settings.background-opacity.label")
      description: I18n.tr("settings.notifications.settings.background-opacity.description")
      from: 0
      to: 100
      stepSize: 1
      value: Settings.data.notifications.backgroundOpacity * 100
      isSettings: true
      defaultValue: (Settings.getDefaultValue("notifications.backgroundOpacity") || 1) * 100
      onMoved: value => Settings.data.notifications.backgroundOpacity = value / 100
      text: Math.round(Settings.data.notifications.backgroundOpacity * 100) + "%"
    }

    // OSD settings moved to the dedicated OSD tab
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Sound Settings
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.notifications.sounds.section.label")
      description: I18n.tr("settings.notifications.sounds.section.description")
    }

    // QtMultimedia unavailable message
    NBox {
      Layout.fillWidth: true
      visible: !SoundService.multimediaAvailable
      implicitHeight: unavailableContent.implicitHeight + Style.marginL * 2

      RowLayout {
        id: unavailableContent
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        NIcon {
          icon: "warning"
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeXL
          Layout.alignment: Qt.AlignVCenter
        }

        NLabel {
          Layout.fillWidth: true
          label: I18n.tr("settings.notifications.sounds.unavailable.label")
          description: I18n.tr("settings.notifications.sounds.unavailable.description")
        }
      }
    }

    NToggle {
      label: I18n.tr("settings.notifications.sounds.enabled.label")
      description: I18n.tr("settings.notifications.sounds.enabled.description")
      checked: Settings.data.notifications?.sounds?.enabled ?? false
      visible: SoundService.multimediaAvailable
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.sounds.enabled")
      onToggled: checked => Settings.data.notifications.sounds.enabled = checked
    }

    // Sound Volume
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true
      visible: SoundService.multimediaAvailable && (Settings.data.notifications?.sounds?.enabled ?? false)

      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("settings.notifications.sounds.volume.label")
        description: I18n.tr("settings.notifications.sounds.volume.description")
        from: 0
        to: 100
        stepSize: 1
        value: (Settings.data.notifications?.sounds?.volume ?? 0.5) * 100
        isSettings: true
        defaultValue: (Settings.getDefaultValue("notifications.sounds.volume") || 0.5) * 100
        onMoved: value => Settings.data.notifications.sounds.volume = value / 100
        text: Math.round((Settings.data.notifications?.sounds?.volume ?? 0.5) * 100) + "%"
      }
    }

    // Separate Sounds Toggle
    NToggle {
      Layout.fillWidth: true
      visible: SoundService.multimediaAvailable && (Settings.data.notifications?.sounds?.enabled ?? false)
      label: I18n.tr("settings.notifications.sounds.separate.label")
      description: I18n.tr("settings.notifications.sounds.separate.description")
      checked: Settings.data.notifications?.sounds?.separateSounds ?? false
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.sounds.separateSounds")
      onToggled: checked => Settings.data.notifications.sounds.separateSounds = checked
    }

    // Unified Sound File (shown when separateSounds is false)
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true
      visible: SoundService.multimediaAvailable && (Settings.data.notifications?.sounds?.enabled ?? false) && !(Settings.data.notifications?.sounds?.separateSounds ?? false)

      NLabel {
        label: I18n.tr("settings.notifications.sounds.files.unified.label")
        description: I18n.tr("settings.notifications.sounds.files.unified.description")
      }

      NTextInputButton {
        Layout.fillWidth: true
        placeholderText: I18n.tr("settings.notifications.sounds.files.placeholder")
        text: Settings.data.notifications?.sounds?.normalSoundFile ?? ""
        buttonIcon: "folder-open"
        buttonTooltip: I18n.tr("settings.notifications.sounds.files.select-file")
        onInputEditingFinished: {
          const soundPath = text;
          Settings.data.notifications.sounds.normalSoundFile = soundPath;
          Settings.data.notifications.sounds.lowSoundFile = soundPath;
          Settings.data.notifications.sounds.criticalSoundFile = soundPath;
        }
        onButtonClicked: unifiedSoundFilePicker.open()
      }
    }

    // Separate Sound Files (shown when separateSounds is true)
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true
      visible: SoundService.multimediaAvailable && (Settings.data.notifications?.sounds?.enabled ?? false) && (Settings.data.notifications?.sounds?.separateSounds ?? false)

      // Low Urgency Sound File
      ColumnLayout {
        spacing: Style.marginXXS
        Layout.fillWidth: true

        NLabel {
          label: I18n.tr("settings.notifications.sounds.files.low.label")
          description: I18n.tr("settings.notifications.sounds.files.low.description")
        }

        NTextInputButton {
          Layout.fillWidth: true
          placeholderText: I18n.tr("settings.notifications.sounds.files.placeholder")
          text: Settings.data.notifications?.sounds?.lowSoundFile ?? ""
          buttonIcon: "folder-open"
          buttonTooltip: I18n.tr("settings.notifications.sounds.files.select-file")
          onInputEditingFinished: Settings.data.notifications.sounds.lowSoundFile = text
          onButtonClicked: lowSoundFilePicker.open()
        }
      }

      // Normal Urgency Sound File
      ColumnLayout {
        spacing: Style.marginXXS
        Layout.fillWidth: true

        NLabel {
          label: I18n.tr("settings.notifications.sounds.files.normal.label")
          description: I18n.tr("settings.notifications.sounds.files.normal.description")
        }

        NTextInputButton {
          Layout.fillWidth: true
          placeholderText: I18n.tr("settings.notifications.sounds.files.placeholder")
          text: Settings.data.notifications?.sounds?.normalSoundFile ?? ""
          buttonIcon: "folder-open"
          buttonTooltip: I18n.tr("settings.notifications.sounds.files.select-file")
          onInputEditingFinished: Settings.data.notifications.sounds.normalSoundFile = text
          onButtonClicked: normalSoundFilePicker.open()
        }
      }

      // Critical Urgency Sound File
      ColumnLayout {
        spacing: Style.marginXXS
        Layout.fillWidth: true

        NLabel {
          label: I18n.tr("settings.notifications.sounds.files.critical.label")
          description: I18n.tr("settings.notifications.sounds.files.critical.description")
        }

        NTextInputButton {
          Layout.fillWidth: true
          placeholderText: I18n.tr("settings.notifications.sounds.files.placeholder")
          text: Settings.data.notifications?.sounds?.criticalSoundFile ?? ""
          buttonIcon: "folder-open"
          buttonTooltip: I18n.tr("settings.notifications.sounds.files.select-file")
          onInputEditingFinished: Settings.data.notifications.sounds.criticalSoundFile = text
          onButtonClicked: criticalSoundFilePicker.open()
        }
      }
    }
  }

  // Excluded Apps List
  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true
    visible: SoundService.multimediaAvailable && (Settings.data.notifications?.sounds?.enabled ?? false)

    NLabel {
      label: I18n.tr("settings.notifications.sounds.excluded-apps.label")
      description: I18n.tr("settings.notifications.sounds.excluded-apps.description")
    }

    NTextInput {
      Layout.fillWidth: true
      placeholderText: I18n.tr("settings.notifications.sounds.excluded-apps.placeholder")
      text: Settings.data.notifications?.sounds?.excludedApps ?? ""
      onEditingFinished: Settings.data.notifications.sounds.excludedApps = text
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
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
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.respectExpireTimeout")
      onToggled: checked => Settings.data.notifications.respectExpireTimeout = checked
    }

    // Low Urgency Duration
    RowLayout {
      spacing: Style.marginL
      Layout.fillWidth: true

      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("settings.notifications.duration.low-urgency.label")
        description: I18n.tr("settings.notifications.duration.low-urgency.description")
        from: 1
        to: 30
        stepSize: 1
        value: Settings.data.notifications.lowUrgencyDuration
        isSettings: true
        defaultValue: Settings.getDefaultValue("notifications.lowUrgencyDuration")
        onMoved: value => Settings.data.notifications.lowUrgencyDuration = value
        text: Settings.data.notifications.lowUrgencyDuration + "s"
      }
      // Reset button container
      Item {
        Layout.preferredWidth: 30 * Style.uiScaleRatio
        Layout.preferredHeight: 30 * Style.uiScaleRatio

        NIconButton {
          icon: "restore"
          baseSize: Style.baseWidgetSize * 0.8
          tooltipText: I18n.tr("settings.notifications.duration.reset")
          onClicked: Settings.data.notifications.lowUrgencyDuration = 3
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    // Normal Urgency Duration
    RowLayout {
      spacing: Style.marginL
      Layout.fillWidth: true

      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("settings.notifications.duration.normal-urgency.label")
        description: I18n.tr("settings.notifications.duration.normal-urgency.description")
        from: 1
        to: 30
        stepSize: 1
        value: Settings.data.notifications.normalUrgencyDuration
        isSettings: true
        defaultValue: Settings.getDefaultValue("notifications.normalUrgencyDuration")
        onMoved: value => Settings.data.notifications.normalUrgencyDuration = value
        text: Settings.data.notifications.normalUrgencyDuration + "s"
      }

      // Reset button container
      Item {
        Layout.preferredWidth: 30 * Style.uiScaleRatio
        Layout.preferredHeight: 30 * Style.uiScaleRatio

        NIconButton {
          icon: "restore"
          baseSize: Style.baseWidgetSize * 0.8
          tooltipText: I18n.tr("settings.notifications.duration.reset")
          onClicked: Settings.data.notifications.normalUrgencyDuration = 8
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    // Critical Urgency Duration
    RowLayout {
      spacing: Style.marginL
      Layout.fillWidth: true

      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("settings.notifications.duration.critical-urgency.label")
        description: I18n.tr("settings.notifications.duration.critical-urgency.description")
        from: 1
        to: 30
        stepSize: 1
        value: Settings.data.notifications.criticalUrgencyDuration
        isSettings: true
        defaultValue: Settings.getDefaultValue("notifications.criticalUrgencyDuration")
        onMoved: value => Settings.data.notifications.criticalUrgencyDuration = value
        text: Settings.data.notifications.criticalUrgencyDuration + "s"
      }
      // Reset button container
      Item {
        Layout.preferredWidth: 30 * Style.uiScaleRatio
        Layout.preferredHeight: 30 * Style.uiScaleRatio

        NIconButton {
          icon: "restore"
          baseSize: Style.baseWidgetSize * 0.8
          tooltipText: I18n.tr("settings.notifications.duration.reset")
          onClicked: Settings.data.notifications.criticalUrgencyDuration = 15
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    NDivider {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginL
      Layout.bottomMargin: Style.marginL
    }

    // History Configuration
    NHeader {
      label: I18n.tr("settings.notifications.history.section.label")
      description: I18n.tr("settings.notifications.history.section.description")
    }

    NToggle {
      label: I18n.tr("settings.notifications.history.low-urgency.label")
      description: I18n.tr("settings.notifications.history.low-urgency.description")
      checked: Settings.data.notifications?.saveToHistory?.low !== false
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.saveToHistory.low") ?? true
      onToggled: checked => Settings.data.notifications.saveToHistory.low = checked
    }

    NToggle {
      label: I18n.tr("settings.notifications.history.normal-urgency.label")
      description: I18n.tr("settings.notifications.history.normal-urgency.description")
      checked: Settings.data.notifications?.saveToHistory?.normal !== false
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.saveToHistory.normal") ?? true
      onToggled: checked => Settings.data.notifications.saveToHistory.normal = checked
    }

    NToggle {
      label: I18n.tr("settings.notifications.history.critical-urgency.label")
      description: I18n.tr("settings.notifications.history.critical-urgency.description")
      checked: Settings.data.notifications?.saveToHistory?.critical !== false
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.saveToHistory.critical") ?? true
      onToggled: checked => Settings.data.notifications.saveToHistory.critical = checked
    }

    NDivider {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginL
      Layout.bottomMargin: Style.marginL
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
                       Settings.data.notifications.monitors = addMonitor(Settings.data.notifications.monitors, modelData.name);
                     } else {
                       Settings.data.notifications.monitors = removeMonitor(Settings.data.notifications.monitors, modelData.name);
                     }
                   }
      }
    }

    NDivider {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginL
      Layout.bottomMargin: Style.marginL
    }

    // Toast Configuration
    NHeader {
      label: I18n.tr("settings.notifications.toast.section.label")
      description: I18n.tr("settings.notifications.toast.section.description")
    }

    NToggle {
      label: I18n.tr("settings.notifications.toast.keyboard.label")
      description: I18n.tr("settings.notifications.toast.keyboard.description")
      checked: Settings.data.notifications.enableKeyboardLayoutToast
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.enableKeyboardLayoutToast")
      onToggled: checked => Settings.data.notifications.enableKeyboardLayoutToast = checked
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // File Pickers for Sound Files
  NFilePicker {
    id: unifiedSoundFilePicker
    title: I18n.tr("settings.notifications.sounds.files.unified.select-title")
    selectionMode: "files"
    initialPath: Quickshell.env("HOME")
    nameFilters: ["*.wav", "*.mp3", "*.ogg", "*.flac", "*.m4a", "*.aac"]
    onAccepted: paths => {
                  if (paths.length > 0) {
                    const soundPath = paths[0];
                    Settings.data.notifications.sounds.normalSoundFile = soundPath;
                    Settings.data.notifications.sounds.lowSoundFile = soundPath;
                    Settings.data.notifications.sounds.criticalSoundFile = soundPath;
                  }
                }
  }

  NFilePicker {
    id: lowSoundFilePicker
    title: I18n.tr("settings.notifications.sounds.files.low.select-title")
    selectionMode: "files"
    initialPath: Quickshell.env("HOME")
    nameFilters: ["*.wav", "*.mp3", "*.ogg", "*.flac", "*.m4a", "*.aac"]
    onAccepted: paths => {
                  if (paths.length > 0) {
                    Settings.data.notifications.sounds.lowSoundFile = paths[0];
                  }
                }
  }

  NFilePicker {
    id: normalSoundFilePicker
    title: I18n.tr("settings.notifications.sounds.files.normal.select-title")
    selectionMode: "files"
    initialPath: Quickshell.env("HOME")
    nameFilters: ["*.wav", "*.mp3", "*.ogg", "*.flac", "*.m4a", "*.aac"]
    onAccepted: paths => {
                  if (paths.length > 0) {
                    Settings.data.notifications.sounds.normalSoundFile = paths[0];
                  }
                }
  }

  NFilePicker {
    id: criticalSoundFilePicker
    title: I18n.tr("settings.notifications.sounds.files.critical.select-title")
    selectionMode: "files"
    initialPath: Quickshell.env("HOME")
    nameFilters: ["*.wav", "*.mp3", "*.ogg", "*.flac", "*.m4a", "*.aac"]
    onAccepted: paths => {
                  if (paths.length > 0) {
                    Settings.data.notifications.sounds.criticalSoundFile = paths[0];
                  }
                }
  }
}
