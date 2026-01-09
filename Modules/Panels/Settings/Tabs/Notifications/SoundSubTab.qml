import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  signal openUnifiedPicker
  signal openLowPicker
  signal openNormalPicker
  signal openCriticalPicker

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
        label: I18n.tr("panels.notifications.sounds-unavailable-label")
        description: I18n.tr("panels.notifications.sounds-unavailable-description")
      }
    }
  }

  NToggle {
    label: I18n.tr("panels.notifications.sounds-enabled-label")
    description: I18n.tr("panels.notifications.sounds-enabled-description")
    checked: Settings.data.notifications?.sounds?.enabled ?? false
    visible: SoundService.multimediaAvailable
    onToggled: checked => Settings.data.notifications.sounds.enabled = checked
    defaultValue: Settings.getDefaultValue("notifications.sounds.enabled")
  }

  // Sound Volume
  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true
    visible: SoundService.multimediaAvailable && (Settings.data.notifications?.sounds?.enabled ?? false)

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("panels.notifications.sounds-volume-label")
      description: I18n.tr("panels.notifications.sounds-volume-description")
      from: 0
      to: 1
      stepSize: 0.01
      value: Settings.data.notifications?.sounds?.volume ?? 0.5
      onMoved: value => Settings.data.notifications.sounds.volume = value
      text: Math.round((Settings.data.notifications?.sounds?.volume ?? 0.5) * 100) + "%"
      defaultValue: Settings.getDefaultValue("notifications.sounds.volume")
    }
  }

  // Separate Sounds Toggle
  NToggle {
    Layout.fillWidth: true
    visible: SoundService.multimediaAvailable && (Settings.data.notifications?.sounds?.enabled ?? false)
    label: I18n.tr("panels.notifications.sounds-separate-label")
    description: I18n.tr("panels.notifications.sounds-separate-description")
    checked: Settings.data.notifications?.sounds?.separateSounds ?? false
    onToggled: checked => Settings.data.notifications.sounds.separateSounds = checked
    defaultValue: Settings.getDefaultValue("notifications.sounds.separateSounds")
  }

  // Unified Sound File (shown when separateSounds is false)
  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true
    visible: SoundService.multimediaAvailable && (Settings.data.notifications?.sounds?.enabled ?? false) && !(Settings.data.notifications?.sounds?.separateSounds ?? false)

    NLabel {
      label: I18n.tr("panels.notifications.sounds-files-unified-label")
      description: I18n.tr("panels.notifications.sounds-files-unified-description")
    }

    NTextInputButton {
      Layout.fillWidth: true
      placeholderText: I18n.tr("panels.notifications.sounds-files-placeholder")
      text: Settings.data.notifications?.sounds?.normalSoundFile ?? ""
      buttonIcon: "folder-open"
      buttonTooltip: I18n.tr("panels.notifications.sounds-files-select-file")
      onInputEditingFinished: {
        const soundPath = text;
        Settings.data.notifications.sounds.normalSoundFile = soundPath;
        Settings.data.notifications.sounds.lowSoundFile = soundPath;
        Settings.data.notifications.sounds.criticalSoundFile = soundPath;
      }
      onButtonClicked: root.openUnifiedPicker()
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
        label: I18n.tr("panels.notifications.sounds-files-low-label")
        description: I18n.tr("panels.notifications.sounds-files-low-description")
      }

      NTextInputButton {
        Layout.fillWidth: true
        placeholderText: I18n.tr("panels.notifications.sounds-files-placeholder")
        text: Settings.data.notifications?.sounds?.lowSoundFile ?? ""
        buttonIcon: "folder-open"
        buttonTooltip: I18n.tr("panels.notifications.sounds-files-select-file")
        onInputEditingFinished: Settings.data.notifications.sounds.lowSoundFile = text
        onButtonClicked: root.openLowPicker()
      }
    }

    // Normal Urgency Sound File
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("panels.notifications.sounds-files-normal-label")
        description: I18n.tr("panels.notifications.sounds-files-normal-description")
      }

      NTextInputButton {
        Layout.fillWidth: true
        placeholderText: I18n.tr("panels.notifications.sounds-files-placeholder")
        text: Settings.data.notifications?.sounds?.normalSoundFile ?? ""
        buttonIcon: "folder-open"
        buttonTooltip: I18n.tr("panels.notifications.sounds-files-select-file")
        onInputEditingFinished: Settings.data.notifications.sounds.normalSoundFile = text
        onButtonClicked: root.openNormalPicker()
      }
    }

    // Critical Urgency Sound File
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("panels.notifications.sounds-files-critical-label")
        description: I18n.tr("panels.notifications.sounds-files-critical-description")
      }

      NTextInputButton {
        Layout.fillWidth: true
        placeholderText: I18n.tr("panels.notifications.sounds-files-placeholder")
        text: Settings.data.notifications?.sounds?.criticalSoundFile ?? ""
        buttonIcon: "folder-open"
        buttonTooltip: I18n.tr("panels.notifications.sounds-files-select-file")
        onInputEditingFinished: Settings.data.notifications.sounds.criticalSoundFile = text
        onButtonClicked: root.openCriticalPicker()
      }
    }
  }

  // Excluded Apps List
  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true
    visible: SoundService.multimediaAvailable && (Settings.data.notifications?.sounds?.enabled ?? false)

    NLabel {
      label: I18n.tr("panels.notifications.sounds-excluded-apps-label")
      description: I18n.tr("panels.notifications.sounds-excluded-apps-description")
    }

    NTextInput {
      Layout.fillWidth: true
      placeholderText: I18n.tr("panels.notifications.sounds-excluded-apps-placeholder")
      text: Settings.data.notifications?.sounds?.excludedApps ?? ""
      onEditingFinished: Settings.data.notifications.sounds.excludedApps = text
    }
  }
}
